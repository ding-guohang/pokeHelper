//go:build integration

package httpapi_test

import (
	"bytes"
	"context"
	"database/sql"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestRegistrationHTTPIsEnumerationSafeAndUsesTypedValidationErrors(t *testing.T) {
	handler, _, db := registrationHandler(t, time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC))

	first := serveJSON(t, handler, "/v1/auth/register",
		`{"email":" Person@Example.com ","password":"fifteen characters"}`, "")
	second := serveJSON(t, handler, "/v1/auth/register",
		`{"email":"PERSON@example.com","password":"another valid password"}`, "")
	if first.Code != http.StatusAccepted || second.Code != http.StatusAccepted {
		t.Fatalf("register statuses = %d/%d, want 202/202", first.Code, second.Code)
	}
	if first.Body.String() != `{"accepted":true}` || second.Body.String() != first.Body.String() {
		t.Fatalf("register bodies = %q/%q, want identical accepted envelope",
			first.Body.String(), second.Body.String())
	}
	var users int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if users != 1 {
		t.Errorf("users = %d, want 1", users)
	}

	invalid := serveJSON(t, handler, "/v1/auth/register",
		`{"email":"not-an-email","password":"short"}`, "request-validation")
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("invalid registration status = %d, want 400", invalid.Code)
	}
	if invalid.Body.String() !=
		`{"error":{"code":"validationFailed","requestID":"request-validation"}}` {
		t.Fatalf("invalid registration body = %q", invalid.Body.String())
	}
}

func TestVerifyEmailHTTPConsumesChallengeOnce(t *testing.T) {
	handler, mailer, _ := registrationHandler(t, time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC))
	register := serveJSON(t, handler, "/v1/auth/register",
		`{"email":"person@example.com","password":"fifteen characters"}`, "")
	if register.Code != http.StatusAccepted {
		t.Fatalf("register status = %d body %s", register.Code, register.Body.String())
	}
	token := mailer.Delivered()[0].Body
	payload := `{"token":"` + token + `"}`

	first := serveJSON(t, handler, "/v1/auth/verify-email", payload, "")
	if first.Code != http.StatusNoContent || first.Body.Len() != 0 {
		t.Fatalf("first verify response = %d %q, want 204 empty", first.Code, first.Body.String())
	}
	second := serveJSON(t, handler, "/v1/auth/verify-email", payload, "request-consumed")
	if second.Code != http.StatusBadRequest {
		t.Fatalf("second verify status = %d, want 400", second.Code)
	}
	if second.Body.String() !=
		`{"error":{"code":"challengeInvalid","requestID":"request-consumed"}}` {
		t.Fatalf("second verify body = %q", second.Body.String())
	}
}

func TestRegistrationHTTPRejectsBodiesOverJSONLimit(t *testing.T) {
	tests := []struct {
		name    string
		payload func(string) string
	}{
		{
			name: "trailing whitespace over limit",
			payload: func(base string) string {
				return base + strings.Repeat(" ", maxHTTPJSONBody-len(base)+1)
			},
		},
		{
			name: "second JSON value starts after limit",
			payload: func(base string) string {
				return base + strings.Repeat(" ", maxHTTPJSONBody-len(base)) + `{}`
			},
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			handler, _, _ := registrationHandler(t, time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC))
			base := `{"email":"body-limit@example.com","password":"fifteen characters"}`
			response := serveJSON(t, handler, "/v1/auth/register", tt.payload(base), "request-too-large")

			if response.Code != http.StatusBadRequest {
				t.Fatalf("response status = %d, want 400", response.Code)
			}
			if response.Body.String() !=
				`{"error":{"code":"validationFailed","requestID":"request-too-large"}}` {
				t.Fatalf("response body = %q", response.Body.String())
			}
		})
	}
}

func TestRegistrationHTTPAllowsSingleJSONWithWhitespaceAtLimit(t *testing.T) {
	handler, _, _ := registrationHandler(t, time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC))
	base := `{"email":"at-limit@example.com","password":"fifteen characters"}`
	payload := base + strings.Repeat(" ", maxHTTPJSONBody-len(base))

	response := serveJSON(t, handler, "/v1/auth/register", payload, "")
	if response.Code != http.StatusAccepted || response.Body.String() != `{"accepted":true}` {
		t.Fatalf("response = %d %q, want 202 accepted", response.Code, response.Body.String())
	}
}

func registrationHandler(
	t *testing.T,
	now time.Time,
) (http.Handler, *mail.MemoryMailer, *sql.DB) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	mailer := &mail.MemoryMailer{}
	service := auth.NewService(
		mysqlstore.NewAuthStore(db),
		password.NewPolicy(password.Blocklist{}),
		password.NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x73}, 64))),
		mailer,
		bytes.NewReader(httpSequentialBytes(256)),
		func() time.Time { return now },
	)
	return httpapi.NewRegistrationHandler(service, func() string { return "generated-request" }), mailer, db
}

func serveJSON(
	t *testing.T,
	handler http.Handler,
	path string,
	body string,
	requestID string,
) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, path, bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	if requestID != "" {
		request.Header.Set("X-Request-ID", requestID)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	_, _ = io.Copy(io.Discard, response.Result().Body)
	return response
}

func httpSequentialBytes(length int) []byte {
	values := make([]byte, length)
	for index := range values {
		values[index] = byte(index + 1)
	}
	return values
}

const maxHTTPJSONBody = 1 << 20
