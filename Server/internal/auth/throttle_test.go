package auth

import (
	"encoding/hex"
	"testing"
)

func TestThrottleSignalHashesAreDomainSeparatedAndKeyed(t *testing.T) {
	t.Parallel()

	// GIVEN the same authentication signal in the account and network domains
	secret := [32]byte{
		0, 1, 2, 3, 4, 5, 6, 7,
		8, 9, 10, 11, 12, 13, 14, 15,
		16, 17, 18, 19, 20, 21, 22, 23,
		24, 25, 26, 27, 28, 29, 30, 31,
	}

	// WHEN HMAC-SHA-256 signal hashes are derived
	account := signalHash(secret, accountSignalDomain, "person@example.com")
	network := signalHash(secret, networkSignalDomain, "person@example.com")

	// THEN the hashes match independent fixed vectors and do not collide
	if got := hex.EncodeToString(account[:]); got != "dcae18d75f6bee467207e34908833721ab256168c89138b6c46770c6dd794b0e" {
		t.Fatalf("account hash = %s", got)
	}
	if got := hex.EncodeToString(network[:]); got != "53d15a9ba6ab5e941c87e3107f3d20ad448874638112124f6c8d6653184ee5b2" {
		t.Fatalf("network hash = %s", got)
	}
	if account == network {
		t.Fatal("account and network hashes collide")
	}
}
