package sync_test

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"porkhelper/server/internal/sync"
)

func TestCanonicalHashMatchesTheSharedContractFixture(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "Contracts", "training-event-upload-v1.json"))
	if err != nil {
		t.Fatalf("read contract fixture: %v", err)
	}

	var body sync.UploadBody
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("decode contract fixture: %v", err)
	}

	// Re-encoding must reproduce the fixture byte for byte, or Swift and Go
	// would hash the same events differently and every retry would look new.
	canonical, err := sync.CanonicalBody(body)
	if err != nil {
		t.Fatalf("canonical body: %v", err)
	}
	if string(canonical) != string(raw) {
		t.Fatalf("canonical re-encoding differs:\n got %s\nwant %s", canonical, raw)
	}

	hash, err := sync.HashUploadRequest(sync.UploadCommand{Body: body, RawBody: raw})
	if err != nil {
		t.Fatalf("hash upload: %v", err)
	}
	goldenPath := filepath.Join("..", "..", "..", "Contracts", "training-event-upload-v1.sha256")
	golden, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("read checksum fixture: %v", err)
	}
	want := string(golden)
	if len(want) > 0 && want[len(want)-1] == '\n' {
		want = want[:len(want)-1]
	}
	if hex.EncodeToString(hash[:]) != want {
		t.Errorf("hash = %s, want %s", hex.EncodeToString(hash[:]), want)
	}
}

func TestValidationRejectsOutOfBoundsAndMalformedUploads(t *testing.T) {
	valid := contractCommand(t)

	tests := map[string]func(*sync.UploadCommand){
		"missing idempotency key": func(c *sync.UploadCommand) { c.IdempotencyKey = "" },
		"wrong schema version":    func(c *sync.UploadCommand) { c.Body.SchemaVersion = 2 },
		"empty batch":             func(c *sync.UploadCommand) { c.Body.Events = nil },
		"malformed uuid": func(c *sync.UploadCommand) {
			c.Body.Events[0].ID = "00000000-0000-0000-0000-00000000000g"
		},
		"short uuid": func(c *sync.UploadCommand) {
			c.Body.Events[0].ID = "00000000-0000-0000-0000-0000000000"
		},
		"missing dimension": func(c *sync.UploadCommand) {
			c.Body.Events[0].AbilityDimension = ""
		},
		"bad occurredAt": func(c *sync.UploadCommand) {
			c.Body.Events[0].OccurredAt = "2026-08-07"
		},
	}

	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			command := cloneCommand(t, valid)
			mutate(&command)
			// The raw body follows the mutation, so only the rule under test
			// fails rather than the canonical-bytes check.
			command.RawBody = mustCanonical(t, command.Body)

			if err := sync.ValidateUpload(command); err == nil {
				t.Fatal("expected rejection")
			}
		})
	}
}

// Foundation encodes UUID in uppercase and Go's convention is lowercase.
// Rejecting either would mean one of the two clients could never upload.
func TestValidationAcceptsBothUUIDCasings(t *testing.T) {
	for name, id := range map[string]string{
		"lowercase": "a1b2c3d4-0000-4000-8000-00000000000f",
		"uppercase": "A1B2C3D4-0000-4000-8000-00000000000F",
	} {
		t.Run(name, func(t *testing.T) {
			command := cloneCommand(t, contractCommand(t))
			command.Body.Events[0].ID = id
			command.RawBody = mustCanonical(t, command.Body)

			if err := sync.ValidateUpload(command); err != nil {
				t.Fatalf("%s identifier rejected: %v", name, err)
			}
		})
	}
}

// Both casings must land on the same row, or one client could duplicate
// another's event just by writing it differently.
func TestBothUUIDCasingsDecodeToTheSameBytes(t *testing.T) {
	lower, err := sync.UUIDBytes("a1b2c3d4-0000-4000-8000-00000000000f")
	if err != nil {
		t.Fatalf("decode lowercase: %v", err)
	}
	upper, err := sync.UUIDBytes("A1B2C3D4-0000-4000-8000-00000000000F")
	if err != nil {
		t.Fatalf("decode uppercase: %v", err)
	}
	if string(lower) != string(upper) {
		t.Error("the same identifier in two casings decoded to different bytes")
	}
}

func TestValidationRejectsANonCanonicalBody(t *testing.T) {
	command := contractCommand(t)
	command.RawBody = append([]byte(" "), command.RawBody...)

	err := sync.ValidateUpload(command)

	assertSyncCode(t, err, sync.ValidationFailed)
}

func TestValidationRejectsDuplicateEventIDsInOneBatch(t *testing.T) {
	command := contractCommand(t)
	command.Body.Events = append(command.Body.Events, command.Body.Events[0])
	command.RawBody = mustCanonical(t, command.Body)

	err := sync.ValidateUpload(command)

	assertSyncCode(t, err, sync.ValidationFailed)
}

func TestPullLimitsAreRejectedRatherThanClamped(t *testing.T) {
	for _, limit := range []int{0, -1, sync.MaxPullLimit + 1} {
		if err := sync.ValidatePullLimit(limit); err == nil {
			t.Errorf("limit %d must be rejected", limit)
		}
	}
	for _, limit := range []int{sync.MinPullLimit, sync.MaxPullLimit} {
		if err := sync.ValidatePullLimit(limit); err != nil {
			t.Errorf("limit %d must be accepted: %v", limit, err)
		}
	}
}

// Ownership comes from the session. A payload naming another user must still
// be stored under the caller's account.
func TestUploadIgnoresThePayloadUserIDAndUsesTheSession(t *testing.T) {
	store := &uploadStoreDouble{}
	service := sync.NewUploadService(store)
	command := contractCommand(t)

	_, err := service.Upload(
		context.Background(),
		sync.Principal{
			UserID:               "11111111-1111-4111-8111-111111111111",
			DeviceInstallationID: "20000000-0000-0000-0000-000000000001",
		},
		command,
	)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}

	if store.lastRequest.UserID != "11111111-1111-4111-8111-111111111111" {
		t.Errorf("stored under %q, want the session user", store.lastRequest.UserID)
	}
	if store.lastRequest.UserID == command.Body.Events[0].LocalUserID {
		t.Error("the payload's localUserID must not decide ownership")
	}
}

func TestPullReportsCheckpointsAndHasMore(t *testing.T) {
	store := &pullStoreDouble{
		events: []sync.StoredEvent{
			{Event: sync.Event{ID: "a"}, ServerSequence: 7},
			{Event: sync.Event{ID: "b"}, ServerSequence: 8},
			{Event: sync.Event{ID: "c"}, ServerSequence: 9},
		},
	}
	service := sync.NewPullService(store)
	principal := sync.Principal{UserID: "11111111-1111-4111-8111-111111111111"}

	page, err := service.Pull(context.Background(), principal, 6, 2)
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(page.Events) != 2 {
		t.Fatalf("returned %d events, want 2", len(page.Events))
	}
	if page.Checkpoint != 8 {
		t.Errorf("checkpoint = %d, want the last returned sequence 8", page.Checkpoint)
	}
	if !page.HasMore {
		t.Error("a truncated page must report hasMore")
	}
	if store.lastLimit != 3 {
		t.Errorf("store queried with limit %d, want limit+1", store.lastLimit)
	}
}

// An idle client must neither advance nor rewind.
func TestAnEmptyPullReturnsTheRequestedCheckpoint(t *testing.T) {
	service := sync.NewPullService(&pullStoreDouble{})

	page, err := service.Pull(
		context.Background(),
		sync.Principal{UserID: "11111111-1111-4111-8111-111111111111"},
		42,
		10,
	)
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if page.Checkpoint != 42 {
		t.Errorf("checkpoint = %d, want the requested 42", page.Checkpoint)
	}
	if page.HasMore {
		t.Error("an empty page has no more")
	}
}

func contractCommand(t *testing.T) sync.UploadCommand {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "Contracts", "training-event-upload-v1.json"))
	if err != nil {
		t.Fatalf("read contract fixture: %v", err)
	}
	var body sync.UploadBody
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("decode contract fixture: %v", err)
	}
	return sync.UploadCommand{IdempotencyKey: "batch-1", Body: body, RawBody: raw}
}

func cloneCommand(t *testing.T, command sync.UploadCommand) sync.UploadCommand {
	t.Helper()
	encoded, err := json.Marshal(command.Body)
	if err != nil {
		t.Fatalf("clone body: %v", err)
	}
	var body sync.UploadBody
	if err := json.Unmarshal(encoded, &body); err != nil {
		t.Fatalf("clone body: %v", err)
	}
	return sync.UploadCommand{
		IdempotencyKey: command.IdempotencyKey,
		Body:           body,
		RawBody:        encoded,
	}
}

func mustCanonical(t *testing.T, body sync.UploadBody) []byte {
	t.Helper()
	encoded, err := sync.CanonicalBody(body)
	if err != nil {
		t.Fatalf("canonical body: %v", err)
	}
	return encoded
}

func assertSyncCode(t *testing.T, err error, want sync.ErrorCode) {
	t.Helper()
	var syncError *sync.Error
	if !errors.As(err, &syncError) {
		t.Fatalf("error %v is not a *sync.Error", err)
	}
	if syncError.Code != want {
		t.Errorf("code = %q, want %q", syncError.Code, want)
	}
}

type uploadStoreDouble struct {
	lastRequest sync.UploadRequest
}

func (s *uploadStoreDouble) Upload(
	_ context.Context,
	request sync.UploadRequest,
) (sync.UploadResult, error) {
	s.lastRequest = request
	return sync.UploadResult{AcceptedEventIDs: []string{}, Checkpoint: 1}, nil
}

type pullStoreDouble struct {
	events    []sync.StoredEvent
	lastLimit int
}

func (s *pullStoreDouble) Pull(
	_ context.Context,
	_ string,
	after uint64,
	limit int,
) ([]sync.StoredEvent, error) {
	s.lastLimit = limit
	var page []sync.StoredEvent
	for _, event := range s.events {
		if event.ServerSequence > after {
			page = append(page, event)
		}
		if len(page) == limit {
			break
		}
	}
	return page, nil
}
