package appleauth_test

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"porkhelper/server/internal/appleauth"
)

const (
	appleIssuer   = "https://appleid.apple.com"
	appleClientID = "com.porkhelper.PokerCoach"
	appleSubject  = "001234.fedcba9876543210fedcba9876543210.1234"
)

func TestVerifyAcceptsAWellFormedAppleIdentityToken(t *testing.T) {
	fixture := newAppleFixture(t)
	token := fixture.sign(t, fixture.claims())

	claims, err := fixture.verifier.Verify(context.Background(), token, "expected-nonce")
	if err != nil {
		t.Fatalf("verify: %v", err)
	}

	if claims.Subject != appleSubject {
		t.Errorf("subject = %q, want %q", claims.Subject, appleSubject)
	}
	if claims.Email != "player@example.test" {
		t.Errorf("email = %q, want player@example.test", claims.Email)
	}
	if !claims.EmailVerified {
		t.Error("email_verified must survive Apple's string-encoded boolean")
	}
	if claims.Nonce != "expected-nonce" {
		t.Errorf("nonce = %q, want expected-nonce", claims.Nonce)
	}
}

func TestVerifyRejectsATamperedSignature(t *testing.T) {
	fixture := newAppleFixture(t)
	token := fixture.sign(t, fixture.claims())

	parts := strings.Split(token, ".")
	forged := parts[0] + "." + parts[1] + "." + corruptSignature(t, parts[2])

	assertAppleRejects(t, fixture, forged, "expected-nonce", "signature")
}

func TestVerifyRejectsAPayloadEditedAfterSigning(t *testing.T) {
	fixture := newAppleFixture(t)
	token := fixture.sign(t, fixture.claims())

	claims := fixture.claims()
	claims["sub"] = "001234.attacker.0000"
	forgedPayload := encodeSegment(t, claims)
	parts := strings.Split(token, ".")
	forged := parts[0] + "." + forgedPayload + "." + parts[2]

	assertAppleRejects(t, fixture, forged, "expected-nonce", "signature")
}

func TestVerifyRejectsAnUnknownSigningKey(t *testing.T) {
	fixture := newAppleFixture(t)
	fixture.keyID = "not-published"
	token := fixture.sign(t, fixture.claims())

	assertAppleRejects(t, fixture, token, "expected-nonce", "unknownKey")
}

func TestVerifyRejectsAnUnexpectedAlgorithm(t *testing.T) {
	fixture := newAppleFixture(t)
	header := map[string]any{"alg": "none", "kid": fixture.publishedKeyID, "typ": "JWT"}
	token := encodeSegment(t, header) + "." + encodeSegment(t, fixture.claims()) + "."

	assertAppleRejects(t, fixture, token, "expected-nonce", "algorithm")
}

func TestVerifyRejectsAForeignIssuer(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	claims["iss"] = "https://accounts.example.test"

	assertAppleRejects(t, fixture, fixture.sign(t, claims), "expected-nonce", "issuer")
}

func TestVerifyRejectsAnotherApplicationsAudience(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	claims["aud"] = "com.example.other"

	assertAppleRejects(t, fixture, fixture.sign(t, claims), "expected-nonce", "audience")
}

func TestVerifyRejectsAnExpiredToken(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	claims["exp"] = fixture.now.Add(-time.Second).Unix()

	assertAppleRejects(t, fixture, fixture.sign(t, claims), "expected-nonce", "expired")
}

func TestVerifyRejectsATokenIssuedInTheFuture(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	claims["iat"] = fixture.now.Add(10 * time.Minute).Unix()

	assertAppleRejects(t, fixture, fixture.sign(t, claims), "expected-nonce", "issuedAt")
}

func TestVerifyRejectsAMismatchedOrMissingNonce(t *testing.T) {
	fixture := newAppleFixture(t)

	assertAppleRejects(t, fixture, fixture.sign(t, fixture.claims()), "different-nonce", "nonce")

	withoutNonce := fixture.claims()
	delete(withoutNonce, "nonce")
	assertAppleRejects(t, fixture, fixture.sign(t, withoutNonce), "expected-nonce", "nonce")
}

func TestVerifyRejectsAMalformedToken(t *testing.T) {
	fixture := newAppleFixture(t)

	for _, token := range []string{"", "a.b", "a.b.c.d", "not-a-jwt", "!!!.???.***"} {
		if _, err := fixture.verifier.Verify(context.Background(), token, "expected-nonce"); err == nil {
			t.Errorf("token %q must be rejected", token)
		}
	}
}

func TestVerifyRejectsATokenWithoutASubject(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	delete(claims, "sub")

	assertAppleRejects(t, fixture, fixture.sign(t, claims), "expected-nonce", "subject")
}

func TestKeysAreCachedAndRefetchedOnlyForAnUnseenKeyID(t *testing.T) {
	fixture := newAppleFixture(t)
	token := fixture.sign(t, fixture.claims())

	for range 3 {
		if _, err := fixture.verifier.Verify(context.Background(), token, "expected-nonce"); err != nil {
			t.Fatalf("verify: %v", err)
		}
	}
	if fetches := fixture.jwksFetches.Load(); fetches != 1 {
		t.Errorf("JWKS fetched %d times for a cached key, want 1", fetches)
	}

	// An unseen key ID triggers exactly one refetch, so Apple key rotation is
	// picked up without hammering the endpoint on every bogus kid.
	fixture.keyID = "rotated-but-unpublished"
	rotated := fixture.sign(t, fixture.claims())
	if _, err := fixture.verifier.Verify(context.Background(), rotated, "expected-nonce"); err == nil {
		t.Fatal("an unpublished key ID must not verify")
	}
	if fetches := fixture.jwksFetches.Load(); fetches != 2 {
		t.Errorf("JWKS fetched %d times, want exactly one refetch for the unseen kid", fetches)
	}
}

func TestVerifierNeverReturnsClaimsAlongsideAnError(t *testing.T) {
	fixture := newAppleFixture(t)
	claims := fixture.claims()
	claims["aud"] = "com.example.other"

	returned, err := fixture.verifier.Verify(context.Background(), fixture.sign(t, claims), "expected-nonce")
	if err == nil {
		t.Fatal("expected a rejection")
	}
	if returned.Subject != "" || returned.Email != "" {
		t.Error("a rejected credential must not leak any claim back to the caller")
	}
}

type appleFixture struct {
	verifier       *appleauth.Verifier
	privateKey     *rsa.PrivateKey
	publishedKeyID string
	keyID          string
	now            time.Time
	jwksFetches    atomic.Int64
}

// newAppleFixture builds an ephemeral RSA key and a local JWKS endpoint. No
// private key or Apple credential is ever committed to the repository.
func newAppleFixture(t *testing.T) *appleFixture {
	t.Helper()
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate ephemeral RSA key: %v", err)
	}

	fixture := &appleFixture{
		privateKey:     privateKey,
		publishedKeyID: "test-key-1",
		keyID:          "test-key-1",
		now:            time.Date(2026, 8, 7, 12, 0, 0, 0, time.UTC),
	}

	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		fixture.jwksFetches.Add(1)
		response.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(response).Encode(map[string]any{
			"keys": []map[string]string{{
				"kty": "RSA",
				"kid": fixture.publishedKeyID,
				"use": "sig",
				"alg": "RS256",
				"n":   base64.RawURLEncoding.EncodeToString(privateKey.N.Bytes()),
				"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(privateKey.E)).Bytes()),
			}},
		})
	}))
	t.Cleanup(server.Close)

	fixture.verifier = appleauth.NewVerifier(
		appleauth.NewKeyCache(server.URL, server.Client(), func() time.Time { return fixture.now }),
		appleIssuer,
		appleClientID,
		func() time.Time { return fixture.now },
	)
	return fixture
}

// claims loads the canonical Apple payload shape from testdata and stamps the
// time-dependent claims, so tests exercise the encodings Apple really sends
// (notably email_verified as a string) rather than a hand-written map.
func (f *appleFixture) claims() map[string]any {
	raw, err := os.ReadFile(filepath.Join("testdata", "apple_claims.json"))
	if err != nil {
		panic("read apple claims fixture: " + err.Error())
	}
	var claims map[string]any
	if err := json.Unmarshal(raw, &claims); err != nil {
		panic("decode apple claims fixture: " + err.Error())
	}
	claims["iat"] = f.now.Add(-time.Minute).Unix()
	claims["exp"] = f.now.Add(time.Hour).Unix()
	claims["nonce"] = "expected-nonce"
	return claims
}

func (f *appleFixture) sign(t *testing.T, claims map[string]any) string {
	t.Helper()
	header := map[string]any{"alg": "RS256", "kid": f.keyID, "typ": "JWT"}
	signingInput := encodeSegment(t, header) + "." + encodeSegment(t, claims)
	digest := sha256.Sum256([]byte(signingInput))
	signature, err := rsa.SignPKCS1v15(rand.Reader, f.privateKey, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(signature)
}

func encodeSegment(t *testing.T, value any) string {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("encode segment: %v", err)
	}
	return base64.RawURLEncoding.EncodeToString(encoded)
}

// corruptSignature flips a byte of the decoded signature rather than a
// character of its base64 text. The final base64 character of a 256-byte
// signature carries padding bits, so editing it can leave the decoded bytes
// unchanged and let a "tampered" token verify — a flaky test that would
// silently stop guarding signature checking.
func corruptSignature(t *testing.T, encoded string) string {
	t.Helper()
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatalf("decode signature: %v", err)
	}
	if len(raw) == 0 {
		t.Fatal("signature is empty")
	}
	raw[0] ^= 0xFF
	return base64.RawURLEncoding.EncodeToString(raw)
}

func assertAppleRejects(t *testing.T, fixture *appleFixture, token string, nonce string, reason string) {
	t.Helper()
	_, err := fixture.verifier.Verify(context.Background(), token, nonce)
	if err == nil {
		t.Fatalf("expected rejection for reason %q", reason)
	}
	var appleError *appleauth.Error
	if !errors.As(err, &appleError) {
		t.Fatalf("error %v is not an *appleauth.Error", err)
	}
	if appleError.Reason != reason {
		t.Errorf("rejection reason = %q, want %q", appleError.Reason, reason)
	}
}
