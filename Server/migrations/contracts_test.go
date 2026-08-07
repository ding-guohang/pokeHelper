package migrations_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

func TestTrainingEventUploadV1MatchesCanonicalChecksum(t *testing.T) {
	body, err := os.ReadFile("../../Contracts/training-event-upload-v1.json")
	if err != nil {
		t.Fatalf("read canonical upload: %v", err)
	}
	body = bytes.TrimSuffix(body, []byte{'\n'})

	gotHash := sha256.Sum256(body)
	const wantHash = "8b2cd9fe4fdaef8dc33e2968809ecc9f37b9646efde5f0bd449ca6e06e2a2345"
	if hex.EncodeToString(gotHash[:]) != wantHash {
		t.Errorf("canonical upload SHA-256 = %s, want %s", hex.EncodeToString(gotHash[:]), wantHash)
	}

	golden, err := os.ReadFile("../../Contracts/training-event-upload-v1.sha256")
	if err != nil {
		t.Fatalf("read checksum fixture: %v", err)
	}
	if got := strings.TrimSuffix(string(golden), "\n"); got != wantHash {
		t.Errorf("checksum fixture = %q, want %q", got, wantHash)
	}
}
