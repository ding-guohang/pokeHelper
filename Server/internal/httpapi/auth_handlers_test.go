//go:build integration

package httpapi_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/httpapi"
	"porkhelper/server/internal/mail"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/password"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestLoginFailuresAreIndistinguishableAndAnOpenThrottlePrecedesVerification(t *testing.T) {
	handler, mailer, db, issuer := accessHandler(t)
	registerForAccess(t, handler, mailer, "unverified@example.com", false)
	registerForAccess(t, handler, mailer, "verified@example.com", true)

	// GIVEN missing, unverified, and wrong-password email identities
	requests := []string{
		`{"email":"missing@example.com","password":"wrong password value","device":{"deviceID":"device-1","displayName":"Phone","platform":"ios"}}`,
		`{"email":"unverified@example.com","password":"fifteen characters","device":{"deviceID":"device-1","displayName":"Phone","platform":"ios"}}`,
		`{"email":"verified@example.com","password":"wrong password value","device":{"deviceID":"device-1","displayName":"Phone","platform":"ios"}}`,
	}

	// WHEN password login is attempted
	var body string
	for index, payload := range requests {
		response := serveAccessJSON(t, handler, "/v1/auth/login", payload, "203.0.113.10:5000", "login-failed")

		// THEN every failure exposes the identical authenticationFailed response
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("failure %d status = %d body %s", index, response.Code, response.Body.String())
		}
		if index == 0 {
			body = response.Body.String()
		}
		if response.Body.String() != body ||
			body != `{"error":{"code":"authenticationFailed","requestID":"login-failed"}}` {
			t.Fatalf("failure %d body = %q, want identical authenticationFailed", index, response.Body.String())
		}
	}
	if issuer.issueCount() != 0 {
		t.Fatalf("Issue calls = %d, want 0", issuer.issueCount())
	}

	// GIVEN five failed attempts have filled the account allowance
	for index := 0; index < 4; index++ {
		response := serveAccessJSON(t, handler, "/v1/auth/login", requests[2],
			"203.0.113.11:5000", "account-fill")
		if index < 3 && response.Code != http.StatusUnauthorized {
			t.Fatalf("fill attempt %d status = %d", index+2, response.Code)
		}
	}
	if _, err := db.Exec(`
		UPDATE password_credentials AS p
		INNER JOIN auth_identities AS i ON i.user_id = p.user_id
		SET p.password_hash = 'malformed-phc'
		WHERE i.subject = 'verified@example.com'`); err != nil {
		t.Fatalf("inject malformed PHC after opening throttle: %v", err)
	}

	// WHEN correct credentials are submitted after the sixth attempt opened the block
	correct := `{"email":"verified@example.com","password":"fifteen characters","device":{"deviceID":"device-1","displayName":"Phone","platform":"ios"}}`
	blocked := serveAccessJSON(t, handler, "/v1/auth/login", correct,
		"203.0.113.12:5000", "account-blocked")

	// THEN the open window returns generic rateLimited before credentials can bypass it
	assertRateLimited(t, blocked, "account-blocked")
	if issuer.issueCount() != 0 {
		t.Fatalf("Issue calls after blocked correct login = %d, want 0", issuer.issueCount())
	}
}

func TestSuccessfulLoginIssuesAtServiceTimeAndClearsOnlyAccountThrottle(t *testing.T) {
	handler, mailer, db, issuer := accessHandler(t)
	registerForAccess(t, handler, mailer, "successful@example.com", true)

	// GIVEN a verified identity with a consumed account and network registration quota
	payload := `{"email":" SUCCESSFUL@example.com ","password":"fifteen characters","device":{"deviceID":"device-42","displayName":"Main Phone","platform":"ios"}}`

	// WHEN correct password login succeeds
	response := serveAccessJSON(t, handler, "/v1/auth/login",
		payload, "203.0.113.99:9000", "login-success")

	// THEN SessionIssuer receives canonical user/device data and service-clock recent auth
	if response.Code != http.StatusOK {
		t.Fatalf("login status = %d body %s", response.Code, response.Body.String())
	}
	call := issuer.lastIssue()
	wantNow := time.Date(2026, 8, 7, 3, 4, 5, 250_000_000, time.UTC)
	if call.device != (auth.DeviceMetadata{
		DeviceID: "device-42", DisplayName: "Main Phone", Platform: "ios",
	}) || !call.recentAuthAt.Equal(wantNow) ||
		call.userID != "01020304-0506-0708-090a-0b0c0d0e0f10" {
		t.Fatalf("Issue call = %#v", call)
	}
	zero := make([]byte, 32)
	var accountRows, networkRows int
	if err := db.QueryRow(`
		SELECT COUNT(*) FROM auth_throttles WHERE network_signal_hash = ?`, zero,
	).Scan(&accountRows); err != nil {
		t.Fatalf("count account throttles: %v", err)
	}
	if err := db.QueryRow(`
		SELECT COUNT(*) FROM auth_throttles WHERE identity_signal_hash = ?`, zero,
	).Scan(&networkRows); err != nil {
		t.Fatalf("count network throttles: %v", err)
	}
	if accountRows != 0 || networkRows != 1 {
		t.Fatalf("throttle rows after login = account %d network %d, want 0/1",
			accountRows, networkRows)
	}
}

func TestPasswordResetIsEnumerationSafeSingleUseAndRevokesSessionsAtomically(t *testing.T) {
	handler, mailer, db, issuer := accessHandler(t)
	registerForAccess(t, handler, mailer, "verified@example.com", true)
	registerForAccess(t, handler, mailer, "unverified@example.com", false)
	initialMessages := len(mailer.Delivered())

	// GIVEN registered, unregistered, and unverified canonical emails
	requests := []string{
		`{"email":" VERIFIED@example.com "}`,
		`{"email":"missing@example.com"}`,
		`{"email":"UNVERIFIED@example.com"}`,
	}

	// WHEN each address requests a password reset
	for _, payload := range requests {
		response := serveAccessJSON(t, handler, "/v1/auth/password-reset/request",
			payload, "198.51.100.10:6000", "reset-request")

		// THEN every request returns the exact indistinguishable accepted envelope
		if response.Code != http.StatusAccepted || response.Body.String() != `{"accepted":true}` {
			t.Fatalf("reset request = %d %q, want 202 accepted", response.Code, response.Body.String())
		}
	}
	delivered := mailer.Delivered()
	if len(delivered) != initialMessages+1 || delivered[len(delivered)-1].Subject != "Reset your password" {
		t.Fatalf("reset deliveries = %#v, want exactly one verified delivery", delivered[initialMessages:])
	}
	token := delivered[len(delivered)-1].Body
	if strings.Contains(token, "=") {
		t.Fatalf("reset token contains base64 padding")
	}
	tokenBytes, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(tokenBytes) != 32 {
		t.Fatalf("reset token bytes = %d error %v, want 32", len(tokenBytes), err)
	}
	tokenHash := sha256.Sum256([]byte(token))
	var storedHash []byte
	var purpose string
	var expiresAt time.Time
	if err := db.QueryRow(`
		SELECT token_hash, purpose, expires_at
		FROM email_challenges
		WHERE purpose = 'resetPassword'`,
	).Scan(&storedHash, &purpose, &expiresAt); err != nil {
		t.Fatalf("read reset challenge: %v", err)
	}
	wantExpiry := time.Date(2026, 8, 7, 4, 4, 5, 250_000_000, time.UTC)
	if !bytes.Equal(storedHash, tokenHash[:]) ||
		bytes.Equal(storedHash, []byte(token)) ||
		purpose != "resetPassword" ||
		!expiresAt.Equal(wantExpiry) {
		t.Fatalf("stored reset challenge hash/purpose/expiry mismatch")
	}

	// GIVEN session revocation initially fails
	issuer.setRevokeError(errors.New("injected revocation failure"))
	payload := `{"token":"` + token + `","password":"replacement password"}`

	// WHEN reset confirmation attempts credential replacement
	failed := serveAccessJSON(t, handler, "/v1/auth/password-reset/confirm",
		payload, "198.51.100.10:6000", "reset-revoke-failed")

	// THEN the transaction fails without consuming the retryable challenge
	if failed.Code != http.StatusInternalServerError {
		t.Fatalf("failed revoke status = %d body %s", failed.Code, failed.Body.String())
	}
	var phcAfterFailure string
	if err := db.QueryRow("SELECT password_hash FROM password_credentials").Scan(&phcAfterFailure); err != nil {
		t.Fatalf("read password after failed revoke: %v", err)
	}
	hasher := password.NewHasher(nil)
	oldValid, _, err := hasher.Verify(phcAfterFailure, "fifteen characters")
	if err != nil {
		t.Fatalf("verify old password after failed revoke: %v", err)
	}
	newValid, _, err := hasher.Verify(phcAfterFailure, "replacement password")
	if err != nil {
		t.Fatalf("verify new password after failed revoke: %v", err)
	}
	if !oldValid || newValid {
		t.Fatalf("password changed despite failed revocation: old=%v new=%v", oldValid, newValid)
	}

	// GIVEN revocation is available again
	issuer.setRevokeError(nil)

	// WHEN the same reset challenge is retried and then reused
	first := serveAccessJSON(t, handler, "/v1/auth/password-reset/confirm",
		payload, "198.51.100.10:6000", "reset-confirm")
	second := serveAccessJSON(t, handler, "/v1/auth/password-reset/confirm",
		payload, "198.51.100.10:6000", "reset-consumed")

	// THEN replacement succeeds once, revokes all sessions, and reuse is challengeInvalid
	if first.Code != http.StatusNoContent || first.Body.Len() != 0 {
		t.Fatalf("first confirm = %d %q", first.Code, first.Body.String())
	}
	if second.Code != http.StatusBadRequest ||
		second.Body.String() != `{"error":{"code":"challengeInvalid","requestID":"reset-consumed"}}` {
		t.Fatalf("second confirm = %d %q", second.Code, second.Body.String())
	}
	if got := issuer.lastRevokeReason(); got != "passwordReset" {
		t.Fatalf("RevokeAll reason = %q, want passwordReset", got)
	}
	var phcAfterSuccess string
	if err := db.QueryRow("SELECT password_hash FROM password_credentials").Scan(&phcAfterSuccess); err != nil {
		t.Fatalf("read password after successful reset: %v", err)
	}
	oldValid, _, err = hasher.Verify(phcAfterSuccess, "fifteen characters")
	if err != nil {
		t.Fatalf("verify old password after reset: %v", err)
	}
	newValid, _, err = hasher.Verify(phcAfterSuccess, "replacement password")
	if err != nil {
		t.Fatalf("verify replacement password: %v", err)
	}
	if oldValid || !newValid {
		t.Fatalf("replacement credential validity = old %v new %v", oldValid, newValid)
	}

	// GIVEN expired and unknown reset challenges
	expiredRequest := serveAccessJSON(t, handler, "/v1/auth/password-reset/request",
		`{"email":"verified@example.com"}`, "198.51.100.11:6000", "reset-expired-request")
	if expiredRequest.Code != http.StatusAccepted {
		t.Fatalf("expired-token setup request = %d %s", expiredRequest.Code, expiredRequest.Body.String())
	}
	expiredToken := mailer.Delivered()[len(mailer.Delivered())-1].Body
	expiredHash := sha256.Sum256([]byte(expiredToken))
	if _, err := db.Exec(`
		UPDATE email_challenges SET expires_at = ?
		WHERE token_hash = ?`,
		time.Date(2026, 8, 7, 3, 4, 5, 250_000_000, time.UTC),
		expiredHash[:],
	); err != nil {
		t.Fatalf("expire reset challenge: %v", err)
	}

	// WHEN confirmation uses either invalid challenge
	expired := serveAccessJSON(t, handler, "/v1/auth/password-reset/confirm",
		`{"token":"`+expiredToken+`","password":"another replacement"}`,
		"198.51.100.11:6000", "reset-expired")
	unknown := serveAccessJSON(t, handler, "/v1/auth/password-reset/confirm",
		`{"token":"unknown-token","password":"another replacement"}`,
		"198.51.100.11:6000", "reset-unknown")

	// THEN both expose challengeInvalid
	for requestID, response := range map[string]*httptest.ResponseRecorder{
		"reset-expired": expired,
		"reset-unknown": unknown,
	} {
		if response.Code != http.StatusBadRequest ||
			response.Body.String() != `{"error":{"code":"challengeInvalid","requestID":"`+requestID+`"}}` {
			t.Fatalf("%s response = %d %q", requestID, response.Code, response.Body.String())
		}
	}
}

func TestNetworkThrottleIsGenericAndDoesNotTrustForwardedFor(t *testing.T) {
	handler, _, _, _ := accessHandler(t)

	// GIVEN twenty-five distinct account reset requests from one RemoteAddr IP
	for index := 0; index < 25; index++ {
		payload := `{"email":"missing-` + string(rune('a'+index)) + `@example.com"}`
		request := httptest.NewRequest(http.MethodPost, "/v1/auth/password-reset/request",
			bytes.NewBufferString(payload))
		request.RemoteAddr = "192.0.2.44:7000"
		request.Header.Set("X-Forwarded-For", "198.51.100."+string(rune('a'+index)))
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusAccepted {
			t.Fatalf("request %d status = %d body %s", index+1, response.Code, response.Body.String())
		}
	}

	// WHEN a twenty-sixth distinct account uses the same RemoteAddr with a new forwarded value
	blocked := serveAccessJSON(t, handler, "/v1/auth/password-reset/request",
		`{"email":"missing-z@example.com"}`, "192.0.2.44:7000", "network-blocked")

	// THEN the network bucket returns the same generic rateLimited envelope and whole-second retry
	assertRateLimited(t, blocked, "network-blocked")
}

func accessHandler(t *testing.T) (http.Handler, *mail.MemoryMailer, *sql.DB, *sessionIssuerDouble) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	now := time.Date(2026, 8, 7, 3, 4, 5, 250_000_000, time.UTC)
	store := mysqlstore.NewAuthStore(db)
	throttle, err := auth.NewThrottle(store, bytes.Repeat([]byte{0x5a}, 32), func() time.Time { return now })
	if err != nil {
		t.Fatalf("NewThrottle() error = %v", err)
	}
	mailer := &mail.MemoryMailer{}
	issuer := &sessionIssuerDouble{}
	service := auth.NewService(
		store,
		password.NewPolicy(password.Blocklist{}),
		password.NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x73}, 512))),
		mailer,
		bytes.NewReader(accessSequentialBytes(2048)),
		func() time.Time { return now },
		auth.WithThrottle(throttle),
		auth.WithSessionIssuer(issuer),
	)
	handler := httpapi.NewAuthHandler(service, func() string { return "generated-request" })
	return handler, mailer, db, issuer
}

func registerForAccess(
	t *testing.T,
	handler http.Handler,
	mailer *mail.MemoryMailer,
	email string,
	verify bool,
) {
	t.Helper()
	response := serveAccessJSON(t, handler, "/v1/auth/register",
		`{"email":"`+email+`","password":"fifteen characters"}`,
		"203.0.113.200:8000", "register")
	if response.Code != http.StatusAccepted {
		t.Fatalf("register %s = %d %s", email, response.Code, response.Body.String())
	}
	if !verify {
		return
	}
	delivered := mailer.Delivered()
	token := delivered[len(delivered)-1].Body
	response = serveAccessJSON(t, handler, "/v1/auth/verify-email",
		`{"token":"`+token+`"}`, "203.0.113.200:8000", "verify")
	if response.Code != http.StatusNoContent {
		t.Fatalf("verify %s = %d %s", email, response.Code, response.Body.String())
	}
}

func serveAccessJSON(
	t *testing.T,
	handler http.Handler,
	path string,
	body string,
	remoteAddr string,
	requestID string,
) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	request.RemoteAddr = remoteAddr
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Request-ID", requestID)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

func assertRateLimited(t *testing.T, response *httptest.ResponseRecorder, requestID string) {
	t.Helper()
	if response.Code != http.StatusTooManyRequests ||
		response.Body.String() != `{"error":{"code":"rateLimited","requestID":"`+requestID+`"}}` {
		t.Fatalf("rate limited response = %d %q", response.Code, response.Body.String())
	}
	if response.Header().Get("Retry-After") != "900" {
		t.Fatalf("Retry-After = %q, want 900", response.Header().Get("Retry-After"))
	}
}

type sessionIssuerDouble struct {
	mu           sync.Mutex
	issues       int
	issue        issueCall
	revokeErr    error
	revokeReason string
}

type issueCall struct {
	userID       string
	device       auth.DeviceMetadata
	recentAuthAt time.Time
}

func (s *sessionIssuerDouble) Issue(
	_ context.Context,
	userID string,
	device auth.DeviceMetadata,
	recentAuthAt time.Time,
) (auth.SessionTokens, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.issues++
	s.issue = issueCall{userID: userID, device: device, recentAuthAt: recentAuthAt}
	return auth.SessionTokens{
		AccessToken: "access", RefreshToken: "refresh",
		UserID: userID, SessionID: "session",
		AccessExpiresAt:  recentAuthAt.Add(15 * time.Minute),
		RefreshExpiresAt: recentAuthAt.Add(30 * 24 * time.Hour),
		RecentAuthAt:     recentAuthAt,
	}, nil
}

func (s *sessionIssuerDouble) lastIssue() issueCall {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.issue
}

func (s *sessionIssuerDouble) RevokeAll(_ context.Context, _ string, reason string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.revokeReason = reason
	return s.revokeErr
}

func (s *sessionIssuerDouble) issueCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.issues
}

func (s *sessionIssuerDouble) setRevokeError(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.revokeErr = err
}

func (s *sessionIssuerDouble) lastRevokeReason() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.revokeReason
}

func accessSequentialBytes(length int) []byte {
	values := make([]byte, length)
	for index := range values {
		values[index] = byte(index + 1)
	}
	return values
}
