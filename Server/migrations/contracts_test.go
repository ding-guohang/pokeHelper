package migrations_test

import (
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

	gotHash := sha256.Sum256(body)
	const wantHash = "11888453f78924f0c6743db2cc614baf8d82dbd9772804a0157aa414320a28b6"
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

func TestHistoricalMigrationChecksums(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		filename string
		want     string
	}{
		{
			name:     "0001",
			filename: "0001_m1b_initial.sql",
			want:     "757b0e6e59e6d58979530268cbda204d133ead45d6f58c1d369017a4574220ad",
		},
		{
			name:     "0002",
			filename: "0002_m1b_schema_corrections.sql",
			want:     "5a1fb0fe582f33f4726c8c33165fb710f52356798b398a8d7a27830221d0eb2a",
		},
		{
			name:     "0003",
			filename: "0003_m1b_registration_fields.sql",
			want:     "9ba50f6b1be1223214112e26347c28348e15b12dd7f370d9d7aaa08c2a20a127",
		},
		{
			name:     "0004",
			filename: "0004_auth_identity_subject_binary.sql",
			want:     "3294a886adc509c580d87019947237a7ff4103435a5ccbd88b270fbf019f0602",
		},
		{
			name:     "0005",
			filename: "0005_auth_throttle_attempts.sql",
			want:     "2a0dae10c22f3f7aba7bfb801e68c7242dcf41086f7b57133cb339567e9e62b3",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			body, err := os.ReadFile(tt.filename)
			if err != nil {
				t.Fatalf("read %s: %v", tt.filename, err)
			}
			got := sha256.Sum256(body)
			if gotHex := hex.EncodeToString(got[:]); gotHex != tt.want {
				t.Fatalf("%s SHA-256 = %s, want %s", tt.filename, gotHex, tt.want)
			}
		})
	}
}
