package appleauth

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"strings"
	"time"
)

// clockLeeway absorbs small clock differences between Apple and this server.
const clockLeeway = 2 * time.Minute

// maxTokenBytes bounds parsing work for an untrusted credential.
const maxTokenBytes = 8 << 10

// Verifier validates Sign in with Apple identity tokens. Every rejection
// returns a zero Claims value, so a caller cannot accidentally act on
// unverified data.
type Verifier struct {
	keys     KeyProvider
	issuer   string
	audience string
	now      func() time.Time
}

func NewVerifier(
	keys KeyProvider,
	issuer string,
	audience string,
	now func() time.Time,
) *Verifier {
	if issuer == "" {
		issuer = "https://appleid.apple.com"
	}
	if now == nil {
		now = time.Now
	}
	return &Verifier{keys: keys, issuer: issuer, audience: audience, now: now}
}

// Verify checks the signature and every registered claim, then confirms the
// nonce matches the value the caller expects. expectedNonce is compared with
// the token's nonce claim verbatim in constant time; hashing conventions, if
// any, are the client's responsibility.
func (v *Verifier) Verify(
	ctx context.Context,
	identityToken string,
	expectedNonce string,
) (Claims, error) {
	if identityToken == "" || len(identityToken) > maxTokenBytes {
		return Claims{}, &Error{Reason: "malformed"}
	}

	header, payload, signature, signingInput, err := splitToken(identityToken)
	if err != nil {
		return Claims{}, err
	}

	if header.Algorithm != "RS256" {
		return Claims{}, &Error{Reason: "algorithm"}
	}

	key, err := v.keys.Key(ctx, header.KeyID)
	if err != nil {
		return Claims{}, err
	}

	digest := sha256.Sum256([]byte(signingInput))
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], signature); err != nil {
		return Claims{}, &Error{Reason: "signature", Err: err}
	}

	var raw rawClaims
	if err := json.Unmarshal(payload, &raw); err != nil {
		return Claims{}, &Error{Reason: "malformed", Err: err}
	}

	if raw.Issuer != v.issuer {
		return Claims{}, &Error{Reason: "issuer"}
	}
	if !raw.Audience.contains(v.audience) {
		return Claims{}, &Error{Reason: "audience"}
	}
	if raw.Subject == "" {
		return Claims{}, &Error{Reason: "subject"}
	}

	now := v.now().UTC()
	// Expiry is enforced strictly: Apple identity tokens are short lived, and
	// granting leeway here would widen the window for replaying a stale
	// credential. Leeway applies only to issued-at, where a fast client clock
	// is a benign and common cause of rejection.
	if raw.ExpiresAt == 0 || !time.Unix(raw.ExpiresAt, 0).UTC().After(now) {
		return Claims{}, &Error{Reason: "expired"}
	}
	if raw.IssuedAt == 0 || time.Unix(raw.IssuedAt, 0).UTC().After(now.Add(clockLeeway)) {
		return Claims{}, &Error{Reason: "issuedAt"}
	}

	if expectedNonce == "" || subtle.ConstantTimeCompare(
		[]byte(raw.Nonce),
		[]byte(expectedNonce),
	) != 1 {
		return Claims{}, &Error{Reason: "nonce"}
	}

	return Claims{
		Issuer:        raw.Issuer,
		Subject:       raw.Subject,
		Audience:      v.audience,
		IssuedAt:      time.Unix(raw.IssuedAt, 0).UTC(),
		ExpiresAt:     time.Unix(raw.ExpiresAt, 0).UTC(),
		Nonce:         raw.Nonce,
		Email:         raw.Email,
		EmailVerified: bool(raw.EmailVerified),
	}, nil
}

type tokenHeader struct {
	Algorithm string `json:"alg"`
	KeyID     string `json:"kid"`
}

func splitToken(token string) (tokenHeader, []byte, []byte, string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return tokenHeader{}, nil, nil, "", &Error{Reason: "malformed"}
	}

	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return tokenHeader{}, nil, nil, "", &Error{Reason: "malformed", Err: err}
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return tokenHeader{}, nil, nil, "", &Error{Reason: "malformed", Err: err}
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return tokenHeader{}, nil, nil, "", &Error{Reason: "malformed", Err: err}
	}

	var header tokenHeader
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return tokenHeader{}, nil, nil, "", &Error{Reason: "malformed", Err: err}
	}
	return header, payload, signature, parts[0] + "." + parts[1], nil
}
