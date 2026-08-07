package appleauth

import (
	"encoding/json"
	"fmt"
	"strconv"
	"time"
)

// Error reports a rejected Apple credential. Reason is a diagnostic label for
// tests and server logs; it must never reach a client, because distinguishing
// "wrong audience" from "bad signature" would help an attacker probe.
type Error struct {
	Reason string
	Err    error
}

func (e *Error) Error() string {
	return fmt.Sprintf("appleauth: %s", e.Reason)
}

func (e *Error) Unwrap() error {
	return e.Err
}

// Claims holds the verified subset of an Apple identity token. A Claims value
// is only ever returned together with a nil error.
type Claims struct {
	Issuer        string
	Subject       string
	Audience      string
	IssuedAt      time.Time
	ExpiresAt     time.Time
	Nonce         string
	Email         string
	EmailVerified bool
}

// rawClaims mirrors the token payload. Apple encodes email_verified as either
// a JSON boolean or the strings "true"/"false", so it is decoded leniently.
type rawClaims struct {
	Issuer        string          `json:"iss"`
	Subject       string          `json:"sub"`
	Audience      audienceClaim   `json:"aud"`
	IssuedAt      int64           `json:"iat"`
	ExpiresAt     int64           `json:"exp"`
	Nonce         string          `json:"nonce"`
	Email         string          `json:"email"`
	EmailVerified flexibleBoolean `json:"email_verified"`
}

// audienceClaim accepts both JWT audience encodings: a bare string and an
// array of strings.
type audienceClaim []string

func (a *audienceClaim) UnmarshalJSON(data []byte) error {
	var single string
	if err := json.Unmarshal(data, &single); err == nil {
		*a = audienceClaim{single}
		return nil
	}
	var multiple []string
	if err := json.Unmarshal(data, &multiple); err != nil {
		return fmt.Errorf("appleauth: decode audience: %w", err)
	}
	*a = multiple
	return nil
}

func (a audienceClaim) contains(expected string) bool {
	for _, value := range a {
		if value == expected {
			return true
		}
	}
	return false
}

// flexibleBoolean accepts Apple's string-encoded booleans as well as real
// JSON booleans.
type flexibleBoolean bool

func (b *flexibleBoolean) UnmarshalJSON(data []byte) error {
	var boolean bool
	if err := json.Unmarshal(data, &boolean); err == nil {
		*b = flexibleBoolean(boolean)
		return nil
	}
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return fmt.Errorf("appleauth: decode boolean claim: %w", err)
	}
	parsed, err := strconv.ParseBool(text)
	if err != nil {
		return fmt.Errorf("appleauth: parse boolean claim: %w", err)
	}
	*b = flexibleBoolean(parsed)
	return nil
}
