package password

import (
	"bytes"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
)

func TestHasherUsesIndependentSaltsAndExactArgon2idParameters(t *testing.T) {
	t.Parallel()

	random := append(bytes.Repeat([]byte{0x11}, 16), bytes.Repeat([]byte{0x22}, 16)...)
	hasher := NewHasher(bytes.NewReader(random))

	first, err := hasher.Hash("fifteen chars!!")
	if err != nil {
		t.Fatalf("first Hash() error = %v", err)
	}
	second, err := hasher.Hash("fifteen chars!!")
	if err != nil {
		t.Fatalf("second Hash() error = %v", err)
	}
	if first == second {
		t.Fatal("Hash() reused a salt")
	}
	if !strings.HasPrefix(first, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Fatalf("Hash() = %q, want exact Argon2id parameters", first)
	}

	parts := strings.Split(first, "$")
	if len(parts) != 6 {
		t.Fatalf("Hash() PHC parts = %d, want 6", len(parts))
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		t.Fatalf("decode salt: %v", err)
	}
	key, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		t.Fatalf("decode key: %v", err)
	}
	if len(salt) != 16 || len(key) != 32 {
		t.Fatalf("salt/key lengths = %d/%d, want 16/32", len(salt), len(key))
	}
}

func TestHasherVerifyOnlyRequestsUpgradeAfterValidCandidate(t *testing.T) {
	t.Parallel()

	current := NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x33}, 16)))
	phc, err := current.Hash("correct normalized password")
	if err != nil {
		t.Fatalf("Hash() error = %v", err)
	}

	valid, upgrade, err := current.Verify(phc, "wrong normalized password")
	if err != nil {
		t.Fatalf("Verify(wrong) error = %v", err)
	}
	if valid || upgrade {
		t.Fatalf("Verify(wrong) = valid %v upgrade %v, want false false", valid, upgrade)
	}

	weaker := Hasher{
		Random:      bytes.NewReader(bytes.Repeat([]byte{0x44}, 16)),
		MemoryKiB:   8 * 1024,
		Iterations:  1,
		Parallelism: 1,
	}
	weakPHC, err := weaker.Hash("correct normalized password")
	if err != nil {
		t.Fatalf("weaker Hash() error = %v", err)
	}
	valid, upgrade, err = current.Verify(weakPHC, "correct normalized password")
	if err != nil {
		t.Fatalf("Verify(valid weak PHC) error = %v", err)
	}
	if !valid || !upgrade {
		t.Fatalf("Verify(valid weak PHC) = valid %v upgrade %v, want true true", valid, upgrade)
	}

	valid, upgrade, err = current.Verify(phc, "correct normalized password")
	if err != nil {
		t.Fatalf("Verify(current PHC) error = %v", err)
	}
	if !valid || upgrade {
		t.Fatalf("Verify(current PHC) = valid %v upgrade %v, want true false", valid, upgrade)
	}
}

func TestHasherRejectsUnsafePHCBeforeArgon2(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		parameters string
		saltLength int
		keyLength  int
	}{
		{name: "memory above maximum", parameters: "m=65537,t=2,p=1", saltLength: 16, keyLength: 32},
		{name: "memory below lanes minimum", parameters: "m=31,t=2,p=4", saltLength: 16, keyLength: 32},
		{name: "iterations above maximum", parameters: "m=19456,t=5,p=1", saltLength: 16, keyLength: 32},
		{name: "parallelism above maximum", parameters: "m=19456,t=2,p=5", saltLength: 16, keyLength: 32},
		{name: "salt below minimum", parameters: "m=19456,t=2,p=1", saltLength: 15, keyLength: 32},
		{name: "salt above maximum", parameters: "m=19456,t=2,p=1", saltLength: 33, keyLength: 32},
		{name: "output below minimum", parameters: "m=19456,t=2,p=1", saltLength: 16, keyLength: 15},
		{name: "output above maximum", parameters: "m=19456,t=2,p=1", saltLength: 16, keyLength: 65},
		{name: "trailing parameter", parameters: "m=19456,t=2,p=1,x=1", saltLength: 16, keyLength: 32},
		{name: "trailing parameter garbage", parameters: "m=19456,t=2,p=1garbage", saltLength: 16, keyLength: 32},
		{name: "signed parameter", parameters: "m=+19456,t=2,p=1", saltLength: 16, keyLength: 32},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			phc := testPHC(tt.parameters, tt.saltLength, tt.keyLength)

			_, _, _, parseErr := parsePHC(phc)
			var passwordError *Error
			if !errors.As(parseErr, &passwordError) || passwordError.Code != Invalid {
				t.Fatalf("parsePHC() error = %v, want passwordInvalid before Argon2", parseErr)
			}

			valid, upgrade, verifyErr := (Hasher{}).Verify(phc, "candidate")
			if !errors.As(verifyErr, &passwordError) || passwordError.Code != Invalid {
				t.Fatalf("Verify() error = %v, want passwordInvalid", verifyErr)
			}
			if valid || upgrade {
				t.Fatalf("Verify() = valid %v upgrade %v, want false false", valid, upgrade)
			}
		})
	}
}

func TestHasherRejectsMalformedPHCOutputEncoding(t *testing.T) {
	t.Parallel()

	salt := base64.RawStdEncoding.EncodeToString(bytes.Repeat([]byte{0x11}, 16))
	phc := "$argon2id$v=19$m=19456,t=2,p=1$" + salt + "$not!base64"
	valid, upgrade, err := (Hasher{}).Verify(phc, "candidate")
	var passwordError *Error
	if !errors.As(err, &passwordError) || passwordError.Code != Invalid {
		t.Fatalf("Verify() error = %v, want passwordInvalid", err)
	}
	if valid || upgrade {
		t.Fatalf("Verify() = valid %v upgrade %v, want false false", valid, upgrade)
	}
}

func testPHC(parameters string, saltLength, outputLength int) string {
	return "$argon2id$v=19$" + parameters + "$" +
		base64.RawStdEncoding.EncodeToString(bytes.Repeat([]byte{0x11}, saltLength)) + "$" +
		base64.RawStdEncoding.EncodeToString(bytes.Repeat([]byte{0x22}, outputLength))
}
