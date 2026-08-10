package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/sync"
)

// These tests decode request bodies exactly as the Swift client emits them.
//
// Every other test on this side builds its request in Go, and every test on the
// client side asserts against a Swift-built stub, so both sides can be
// internally perfect while disagreeing about the wire. The bodies below are
// captured from the iOS encoders; changing them means the client changed and
// the server must follow.
func TestSwiftLoginBodyIsAccepted(t *testing.T) {
	// PokerCoach/Infrastructure/Auth/AccountAPI.swift LoginBody, whose `device`
	// is DeviceDescriptor — which carries appVersion.
	body := `{"email":"player@example.test","password":"a-sufficiently-long-passphrase",` +
		`"device":{"deviceID":"6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071",` +
		`"displayName":"iPhone","platform":"iOS","appVersion":"1.0.0"}}`

	var input auth.LoginInput
	if err := decodeJSON(request(body), &input); err != nil {
		t.Fatalf("the server rejects the client's own login body: %v", err)
	}
	if input.Device.AppVersion != "1.0.0" {
		t.Errorf("appVersion = %q, want it preserved for the device list", input.Device.AppVersion)
	}
}

func TestSwiftAppleSignInBodyIsAccepted(t *testing.T) {
	body := `{"identityToken":"token","nonce":"nonce",` +
		`"device":{"deviceID":"6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071",` +
		`"displayName":"iPhone","platform":"iOS","appVersion":"1.0.0"}}`

	var input auth.AppleSignInInput
	if err := decodeJSON(request(body), &input); err != nil {
		t.Fatalf("the server rejects the client's own Apple sign-in body: %v", err)
	}
}

// Foundation encodes UUID as uppercase. The shared contract fixture uses UUIDs
// made only of digits, so a byte-exact comparison against it cannot see case —
// which is how uppercase identifiers reached validation unnoticed.
func TestUploadAcceptsTheUUIDCasingSwiftEmits(t *testing.T) {
	body := swiftShapedUpload(t, "ABCDEF00-1111-4222-8333-AAABBBCCCDDD")

	var decoded sync.UploadBody
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decode upload: %v", err)
	}
	command := sync.UploadCommand{
		IdempotencyKey: "batch-1",
		Body:           decoded,
		RawBody:        body,
	}

	if err := sync.ValidateUpload(command); err != nil {
		t.Fatalf("the server rejects the identifier casing the client emits: %v", err)
	}
}

// The contract fixture is the one artifact both languages assert against, so it
// has to contain a UUID that can actually distinguish the two casings.
func TestTheSharedContractFixtureExercisesHexLetters(t *testing.T) {
	path := filepath.Join("..", "..", "..", "Contracts", "training-event-upload-v1.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read contract fixture: %v", err)
	}

	var body sync.UploadBody
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("decode contract fixture: %v", err)
	}
	if len(body.Events) == 0 {
		t.Fatal("the fixture carries no events")
	}

	for _, id := range []string{
		body.Events[0].ID,
		body.Events[0].LocalUserID,
		body.Events[0].DeviceID,
	} {
		if !strings.ContainsAny(id, "abcdefABCDEF") {
			t.Errorf(
				"identifier %q contains no hex letters, so the fixture cannot detect a casing mismatch",
				id,
			)
		}
	}
}

func request(body string) *http.Request {
	return httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body))
}

func swiftShapedUpload(t *testing.T, eventID string) []byte {
	t.Helper()
	body := sync.UploadBody{
		SchemaVersion: sync.SchemaVersion,
		Events: []sync.Event{{
			AbilityDimension:       "bet-sizing",
			DeviceID:               "20000000-0000-0000-0000-000000000001",
			Grade:                  json.RawMessage(`{"score":100}`),
			ID:                     eventID,
			LocalUserID:            "10000000-0000-0000-0000-000000000001",
			OccurredAt:             "2026-08-07T00:00:00.000Z",
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
	return canonical
}
