package session

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
)

// tokenBytes is the opaque entropy carried by every access and refresh token.
const tokenBytes = 32

// mintToken draws a fresh opaque token and returns it with the hash the store
// persists. The plaintext is returned to the caller exactly once.
func mintToken(random io.Reader) (string, [32]byte, error) {
	raw := make([]byte, tokenBytes)
	if _, err := io.ReadFull(random, raw); err != nil {
		return "", [32]byte{}, fmt.Errorf("session: draw token entropy: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	return token, hashToken(token), nil
}

// hashToken is the single definition of how a presented token maps to its
// stored form. Stores must never see plaintext.
func hashToken(token string) [32]byte {
	return sha256.Sum256([]byte(token))
}

// newID draws a random RFC 4122 version 4 identifier.
func newID(random io.Reader) (ID, error) {
	var id ID
	if _, err := io.ReadFull(random, id[:]); err != nil {
		return ID{}, fmt.Errorf("session: draw identifier: %w", err)
	}
	id[6] = (id[6] & 0x0f) | 0x40
	id[8] = (id[8] & 0x3f) | 0x80
	return id, nil
}
