//go:build integration

// Package e2e drives the real router over a real MySQL schema.
//
// Unlike the per-package integration tests, nothing here is substituted: the
// requests go through HTTP, the responses come from the composed handlers, and
// the rows land in the same tables production uses. It exists to catch the
// failures that only appear when the pieces meet.
package e2e_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/httpapi"
	"porkhelper/server/internal/mail"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/password"
	"porkhelper/server/internal/session"
	"porkhelper/server/internal/sync"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

const accountPassword = "a sufficiently long passphrase"

// Two installations of one account must converge after working offline,
// losing an upload response, and paging one event at a time.
func TestTwoDevicesConvergeThroughTheRealAPI(t *testing.T) {
	server := newServer(t)
	server.register(t, "player@example.test")

	phone := server.login(t, "player@example.test", newUUID(t))
	tablet := server.login(t, "player@example.test", newUUID(t))

	phoneEvent := newUUID(t)
	tabletEvent := newUUID(t)

	// Each device recorded a hand while the other was offline.
	phone.upload(t, "phone-batch-1", phoneEvent)
	tablet.upload(t, "tablet-batch-1", tabletEvent)

	// The phone's acknowledgement was lost, so it replays the identical batch.
	// The server must recognize the replay rather than store a second copy.
	phone.upload(t, "phone-batch-1", phoneEvent)

	phoneSeen := phone.pullAll(t)
	tabletSeen := tablet.pullAll(t)

	want := map[string]bool{phoneEvent: true, tabletEvent: true}
	assertSameEventSet(t, "phone", phoneSeen, want)
	assertSameEventSet(t, "tablet", tabletSeen, want)
}

// A client whose clock ran backwards must not corrupt the server's order.
func TestAClientClockRollbackDoesNotReorderTheServerLog(t *testing.T) {
	server := newServer(t)
	server.register(t, "player@example.test")
	device := server.login(t, "player@example.test", newUUID(t))

	later := newUUID(t)
	earlier := newUUID(t)
	device.uploadAt(t, "batch-later", later, "2026-08-07T12:00:00.000Z")
	device.uploadAt(t, "batch-earlier", earlier, "2026-08-07T09:00:00.000Z")

	// Server order follows arrival, not the client's timestamps.
	page := device.pull(t, 0, 10)
	if len(page.Events) != 2 {
		t.Fatalf("pulled %d events, want 2", len(page.Events))
	}
	if page.Events[0].ID != later || page.Events[1].ID != earlier {
		t.Errorf(
			"order = %s,%s want arrival order %s,%s",
			page.Events[0].ID, page.Events[1].ID, later, earlier,
		)
	}
}

func TestReusingAnIdempotencyKeyForDifferentContentIsRefused(t *testing.T) {
	server := newServer(t)
	server.register(t, "player@example.test")
	device := server.login(t, "player@example.test", newUUID(t))

	device.upload(t, "batch-1", newUUID(t))
	status, body := device.uploadRaw(t, "batch-1", newUUID(t), "2026-08-07T00:00:00.000Z")

	if status != http.StatusConflict {
		t.Fatalf("status = %d, want 409: %s", status, body)
	}
	if !strings.Contains(body, "idempotencyKeyReused") {
		t.Errorf("body = %s, want an idempotencyKeyReused code", body)
	}

	// The refused batch wrote nothing.
	page := device.pull(t, 0, 10)
	if len(page.Events) != 1 {
		t.Errorf("a refused batch left %d events, want the original 1", len(page.Events))
	}
}

func TestOneAccountCannotReadAnother(t *testing.T) {
	server := newServer(t)
	server.register(t, "owner@example.test")
	server.register(t, "stranger@example.test")

	owner := server.login(t, "owner@example.test", newUUID(t))
	stranger := server.login(t, "stranger@example.test", newUUID(t))
	owner.upload(t, "owner-batch", newUUID(t))

	page := stranger.pull(t, 0, 10)

	if len(page.Events) != 0 {
		t.Errorf("another account pulled %d events", len(page.Events))
	}
}

// --- harness ---

type e2eServer struct {
	http   *httptest.Server
	mailer *mail.MemoryMailer
}

func newServer(t *testing.T) *e2eServer {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}

	authStore := mysqlstore.NewAuthStore(db)
	throttle, err := auth.NewThrottle(
		authStore,
		bytes.Repeat([]byte{0x5a}, sha256.Size),
		time.Now,
	)
	if err != nil {
		t.Fatalf("new throttle: %v", err)
	}

	mailer := &mail.MemoryMailer{}
	manager := session.NewManager(mysqlstore.NewSessionStore(db), nil, time.Now)
	issuer := session.NewAuthAdapter(manager)
	hasher := password.NewHasher(nil)

	authService := auth.NewService(
		authStore,
		password.NewPolicy(password.Blocklist{}),
		hasher,
		mailer,
		nil,
		time.Now,
		auth.WithThrottle(throttle),
		auth.WithSessionIssuer(issuer),
	)
	syncStore := mysqlstore.NewSyncStore(db)

	router := httpapi.NewRouter(httpapi.Handlers{
		Auth: authService,
		Apple: auth.NewAppleService(
			nil,
			mysqlstore.NewAppleIdentityStore(db),
			issuer,
			nil,
			time.Now,
		),
		Account: account.NewService(
			mysqlstore.NewAccountStore(db),
			hasher,
			nil,
			time.Now,
		),
		Upload:  sync.NewUploadService(syncStore),
		Pull:    sync.NewPullService(syncStore),
		Session: manager,
	}, nil)

	server := httptest.NewServer(router)
	t.Cleanup(server.Close)
	return &e2eServer{http: server, mailer: mailer}
}

func (s *e2eServer) register(t *testing.T, email string) {
	t.Helper()
	status, body := s.do(t, http.MethodPost, "/v1/auth/register", "",
		fmt.Sprintf(`{"email":%q,"password":%q}`, email, accountPassword))
	if status != http.StatusAccepted {
		t.Fatalf("register %s = %d %s", email, status, body)
	}

	delivered := s.mailer.Delivered()
	token := delivered[len(delivered)-1].Body
	status, body = s.do(t, http.MethodPost, "/v1/auth/verify-email", "",
		fmt.Sprintf(`{"token":%q}`, token))
	if status != http.StatusNoContent && status != http.StatusOK {
		t.Fatalf("verify %s = %d %s", email, status, body)
	}
}

type e2eDevice struct {
	server         *e2eServer
	accessToken    string
	installationID string
}

func (s *e2eServer) login(t *testing.T, email string, installationID string) *e2eDevice {
	t.Helper()
	status, body := s.do(t, http.MethodPost, "/v1/auth/login", "",
		fmt.Sprintf(
			`{"email":%q,"password":%q,"device":{"deviceID":%q,"displayName":"Device","platform":"iOS"}}`,
			email, accountPassword, installationID,
		))
	if status != http.StatusOK {
		t.Fatalf("login = %d %s", status, body)
	}

	var tokens struct {
		AccessToken string `json:"accessToken"`
	}
	if err := json.Unmarshal([]byte(body), &tokens); err != nil {
		t.Fatalf("decode login: %v", err)
	}
	return &e2eDevice{server: s, accessToken: tokens.AccessToken, installationID: installationID}
}

func (d *e2eDevice) upload(t *testing.T, key string, eventID string) {
	t.Helper()
	d.uploadAt(t, key, eventID, "2026-08-07T00:00:00.000Z")
}

func (d *e2eDevice) uploadAt(t *testing.T, key string, eventID string, occurredAt string) {
	t.Helper()
	status, body := d.uploadRaw(t, key, eventID, occurredAt)
	if status != http.StatusOK {
		t.Fatalf("upload = %d %s", status, body)
	}
}

func (d *e2eDevice) uploadRaw(
	t *testing.T,
	key string,
	eventID string,
	occurredAt string,
) (int, string) {
	t.Helper()
	body := sync.UploadBody{
		SchemaVersion: sync.SchemaVersion,
		Events: []sync.Event{{
			AbilityDimension:       "bet-sizing",
			DeviceID:               d.installationID,
			Grade:                  json.RawMessage(`{"score":100}`),
			ID:                     eventID,
			LocalUserID:            "10000000-0000-4000-8000-000000000001",
			OccurredAt:             occurredAt,
			ScenarioID:             "scenario-1",
			StrategyContentVersion: "2026.08.06",
			StrategyPackID:         "cash-pack",
			Submission:             json.RawMessage(`{"confidence":"verySure"}`),
		}},
	}
	canonical, err := sync.CanonicalBody(body)
	if err != nil {
		t.Fatalf("canonical body: %v", err)
	}
	return d.server.doWithHeaders(
		t,
		http.MethodPost,
		"/v1/sync/events",
		d.accessToken,
		string(canonical),
		map[string]string{"Idempotency-Key": key},
	)
}

func (d *e2eDevice) pull(t *testing.T, after uint64, limit int) sync.EventPage {
	t.Helper()
	path := fmt.Sprintf("/v1/sync/events?after=%d&limit=%d", after, limit)
	status, body := d.server.do(t, http.MethodGet, path, d.accessToken, "")
	if status != http.StatusOK {
		t.Fatalf("pull = %d %s", status, body)
	}
	var page sync.EventPage
	if err := json.Unmarshal([]byte(body), &page); err != nil {
		t.Fatalf("decode page: %v", err)
	}
	return page
}

// pullAll walks the log one event at a time, which is the paging path a real
// client takes and the one where a checkpoint bug would show up.
func (d *e2eDevice) pullAll(t *testing.T) map[string]bool {
	t.Helper()
	seen := map[string]bool{}
	var checkpoint uint64
	for range 20 {
		page := d.pull(t, checkpoint, 1)
		for _, event := range page.Events {
			seen[event.ID] = true
		}
		checkpoint = page.Checkpoint
		if !page.HasMore {
			return seen
		}
	}
	t.Fatal("pull did not terminate")
	return nil
}

func (s *e2eServer) do(
	t *testing.T,
	method string,
	path string,
	accessToken string,
	body string,
) (int, string) {
	t.Helper()
	return s.doWithHeaders(t, method, path, accessToken, body, nil)
}

func (s *e2eServer) doWithHeaders(
	t *testing.T,
	method string,
	path string,
	accessToken string,
	body string,
	headers map[string]string,
) (int, string) {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	request, err := http.NewRequest(method, s.http.URL+path, reader)
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	if accessToken != "" {
		request.Header.Set("Authorization", "Bearer "+accessToken)
	}
	for name, value := range headers {
		request.Header.Set(name, value)
	}

	response, err := s.http.Client().Do(request)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = response.Body.Close() }()

	payload, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("read response: %v", err)
	}
	return response.StatusCode, string(payload)
}

func assertSameEventSet(t *testing.T, name string, got map[string]bool, want map[string]bool) {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("%s saw %d events, want %d", name, len(got), len(want))
	}
	for id := range want {
		if !got[id] {
			t.Errorf("%s never saw event %s", name, id)
		}
	}
}

func newUUID(t *testing.T) string {
	t.Helper()
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		t.Fatalf("generate uuid: %v", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf(
		"%08x-%04x-%04x-%04x-%012x",
		value[0:4], value[4:6], value[6:8], value[8:10], value[10:16],
	)
}
