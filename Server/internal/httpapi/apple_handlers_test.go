package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/httpapi"
	"porkhelper/server/internal/session"
)

const appleHTTPSubject = "001234.fedcba9876543210fedcba9876543210.1234"

func TestAppleSignInReturnsASessionForAVerifiedCredential(t *testing.T) {
	handler, fixture := newAppleAPI(t)

	response := postSessionJSON(t, handler, "/v1/auth/apple",
		`{"identityToken":"token","nonce":"n","device":{"deviceID":"installation-a","displayName":"iPhone","platform":"iOS"}}`)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", response.Code, response.Body.String())
	}
	var result auth.LoginResult
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode login result: %v", err)
	}
	if result.AccessToken == "" || result.RefreshToken == "" {
		t.Error("a verified Apple sign-in must return both tokens")
	}
	if fixture.store.resolvedSubject != appleHTTPSubject {
		t.Errorf("resolved subject %q, want %q", fixture.store.resolvedSubject, appleHTTPSubject)
	}
}

func TestAppleSignInReturnsGenericUnauthorizedForAnyVerificationFailure(t *testing.T) {
	for _, reason := range []string{"signature", "audience", "expired", "nonce", "issuer"} {
		handler, fixture := newAppleAPI(t)
		fixture.verifyErr = &appleauth.Error{Reason: reason}

		response := postSessionJSON(t, handler, "/v1/auth/apple",
			`{"identityToken":"token","nonce":"n","device":{"deviceID":"installation-a"}}`)

		if response.Code != http.StatusUnauthorized {
			t.Errorf("reason %q produced %d, want 401", reason, response.Code)
		}
		assertSessionErrorCode(t, response, string(auth.AuthenticationFailed))
		if strings.Contains(response.Body.String(), reason) {
			t.Errorf("the response leaked the rejection reason %q", reason)
		}
	}
}

func TestAppleLinkRequiresABearerSession(t *testing.T) {
	handler, _ := newAppleAPI(t)

	request := httptest.NewRequest(http.MethodPost, "/v1/auth/apple/link",
		strings.NewReader(`{"identityToken":"token","nonce":"n"}`))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", response.Code)
	}
}

func TestAppleLinkUsesTheBearerPrincipalNotTheRequestBody(t *testing.T) {
	handler, fixture := newAppleAPI(t)

	response := postAppleLink(t, handler, `{"identityToken":"token","nonce":"n"}`)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204: %s", response.Code, response.Body.String())
	}
	if fixture.store.linkedUserID != sessionOwnerID {
		t.Errorf("linked to %q, want the bearer principal %q",
			fixture.store.linkedUserID, sessionOwnerID)
	}
}

func TestAppleLinkRejectsAForgedUserIDInTheBody(t *testing.T) {
	handler, _ := newAppleAPI(t)

	response := postAppleLink(t, handler,
		`{"identityToken":"token","nonce":"n","userID":"99999999-9999-4999-8999-999999999999"}`)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 for an unknown body field", response.Code)
	}
}

func TestAppleLinkWithAStalePrincipalDemandsReauthentication(t *testing.T) {
	handler, fixture := newAppleAPI(t)
	fixture.recentAuthAt = fixture.now.Add(-11 * time.Minute)

	response := postAppleLink(t, handler, `{"identityToken":"token","nonce":"n"}`)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", response.Code)
	}
	assertSessionErrorCode(t, response, string(auth.ReauthenticationRequired))
}

func TestAppleLinkReportsAConflictWhenTheSubjectBelongsElsewhere(t *testing.T) {
	handler, fixture := newAppleAPI(t)
	fixture.store.linkErr = &auth.Error{Code: auth.IdentityConflict}

	response := postAppleLink(t, handler, `{"identityToken":"token","nonce":"n"}`)

	if response.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", response.Code)
	}
	assertSessionErrorCode(t, response, string(auth.IdentityConflict))
}

type appleAPIFixture struct {
	store        *appleHTTPStore
	verifyErr    error
	now          time.Time
	recentAuthAt time.Time
}

func newAppleAPI(t *testing.T) (http.Handler, *appleAPIFixture) {
	t.Helper()
	now := time.Date(2026, 8, 7, 12, 0, 0, 0, time.UTC)
	fixture := &appleAPIFixture{
		store:        &appleHTTPStore{},
		now:          now,
		recentAuthAt: now,
	}

	sessionStore := &sessionStoreDouble{}
	manager := session.NewManager(sessionStore, nil, func() time.Time { return fixture.now })
	sessionStore.principal = session.Principal{
		UserID:    sessionOwnerID,
		SessionID: currentSessionID,
	}
	// The principal's recent-auth time is what gates linking, so it is
	// resolved lazily from the fixture on each authentication.
	sessionStore.principalHook = func() session.Principal {
		return session.Principal{
			UserID:       sessionOwnerID,
			SessionID:    currentSessionID,
			RecentAuthAt: fixture.recentAuthAt,
		}
	}

	service := auth.NewAppleService(
		appleHTTPVerifier{fixture: fixture},
		fixture.store,
		session.NewAuthAdapter(manager),
		nil,
		func() time.Time { return fixture.now },
	)
	return httpapi.NewAppleHandler(service, manager, func() string { return "test-request" }), fixture
}

func postAppleLink(t *testing.T, handler http.Handler, body string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/apple/link", strings.NewReader(body))
	request.Header.Set("Authorization", "Bearer live-access-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

type appleHTTPVerifier struct {
	fixture *appleAPIFixture
}

func (v appleHTTPVerifier) Verify(
	_ context.Context,
	_ string,
	_ string,
) (appleauth.Claims, error) {
	if v.fixture.verifyErr != nil {
		return appleauth.Claims{}, v.fixture.verifyErr
	}
	return appleauth.Claims{Subject: appleHTTPSubject}, nil
}

type appleHTTPStore struct {
	resolvedSubject string
	linkedUserID    string
	linkErr         error
}

func (s *appleHTTPStore) ResolveAppleIdentity(
	_ context.Context,
	identity auth.AppleIdentity,
) (auth.ID, error) {
	s.resolvedSubject = identity.Subject
	return identity.UserID, nil
}

func (s *appleHTTPStore) LinkAppleIdentity(
	_ context.Context,
	identity auth.AppleIdentity,
) error {
	if s.linkErr != nil {
		return s.linkErr
	}
	s.linkedUserID = identity.UserID.String()
	return nil
}
