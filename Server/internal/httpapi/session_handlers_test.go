package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/httpapi"
	"porkhelper/server/internal/session"
)

const (
	sessionOwnerID   = "11111111-1111-4111-8111-111111111111"
	currentSessionID = "22222222-2222-4222-8222-222222222222"
	otherSessionID   = "33333333-3333-4333-8333-333333333333"
)

func TestDeviceRoutesRejectRequestsWithoutALiveBearerToken(t *testing.T) {
	handler, store := newSessionAPI(t)
	store.authenticateErr = &session.Error{Code: session.Unauthenticated}

	for _, header := range []string{
		"",
		"Bearer",
		"Bearer ",
		"Basic dXNlcjpwYXNz",
		"token abc",
	} {
		request := httptest.NewRequest(http.MethodGet, "/v1/sessions", nil)
		if header != "" {
			request.Header.Set("Authorization", header)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)

		if response.Code != http.StatusUnauthorized {
			t.Errorf("Authorization %q produced %d, want 401", header, response.Code)
		}
		assertSessionErrorCode(t, response, string(session.Unauthenticated))
	}
}

func TestDeviceListUsesTheBearerPrincipalAndMarksTheCurrentSession(t *testing.T) {
	handler, store := newSessionAPI(t)
	store.devices = []session.DeviceSession{
		{SessionID: currentSessionID, DisplayName: "iPhone", Platform: "iOS"},
		{SessionID: otherSessionID, DisplayName: "iPad", Platform: "iPadOS"},
	}

	request := httptest.NewRequest(http.MethodGet, "/v1/sessions", nil)
	request.Header.Set("Authorization", "Bearer live-access-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", response.Code, response.Body.String())
	}
	if store.listedUserID != sessionOwnerID {
		t.Errorf("listed devices for %q, want the bearer principal %q", store.listedUserID, sessionOwnerID)
	}

	var payload struct {
		Devices []session.DeviceSession `json:"devices"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode device list: %v", err)
	}
	if len(payload.Devices) != 2 {
		t.Fatalf("returned %d devices, want 2", len(payload.Devices))
	}
	for _, device := range payload.Devices {
		if device.SessionID == currentSessionID && !device.Current {
			t.Error("the bearer's own session must be marked current")
		}
		if device.SessionID == otherSessionID && device.Current {
			t.Error("another session must not be marked current")
		}
	}
	if strings.Contains(response.Body.String(), "live-access-token") {
		t.Error("the device list must never echo credential material")
	}
}

func TestBearerSchemeIsMatchedCaseInsensitively(t *testing.T) {
	handler, _ := newSessionAPI(t)

	request := httptest.NewRequest(http.MethodGet, "/v1/sessions", nil)
	request.Header.Set("Authorization", "bearer live-access-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Errorf("status = %d, want 200 for a lowercase bearer scheme", response.Code)
	}
}

func TestRevokingADeviceScopesToTheBearerPrincipal(t *testing.T) {
	handler, store := newSessionAPI(t)

	request := httptest.NewRequest(http.MethodDelete, "/v1/sessions/"+otherSessionID, nil)
	request.Header.Set("Authorization", "Bearer live-access-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204: %s", response.Code, response.Body.String())
	}
	if store.revokedUserID != sessionOwnerID {
		t.Errorf("revocation scoped to %q, want the bearer principal %q", store.revokedUserID, sessionOwnerID)
	}
	if store.revokedSessionID != otherSessionID {
		t.Errorf("revoked %q, want %q", store.revokedSessionID, otherSessionID)
	}
}

func TestRevokingASessionTheCallerDoesNotOwnReportsNotFound(t *testing.T) {
	handler, store := newSessionAPI(t)
	store.revokeErr = &session.Error{Code: session.NotFound}

	request := httptest.NewRequest(http.MethodDelete, "/v1/sessions/44444444-4444-4444-8444-444444444444", nil)
	request.Header.Set("Authorization", "Bearer live-access-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", response.Code)
	}
	assertSessionErrorCode(t, response, string(session.NotFound))
}

func TestRefreshRotatesTokensAndRejectsAReplayWithoutDetail(t *testing.T) {
	handler, store := newSessionAPI(t)
	store.rotation = session.RotationOutcome{
		UserID:    sessionOwnerID,
		SessionID: currentSessionID,
	}

	response := postSessionJSON(t, handler, "/v1/auth/refresh", `{"refreshToken":"live-refresh"}`)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", response.Code, response.Body.String())
	}
	var pair session.TokenPair
	if err := json.Unmarshal(response.Body.Bytes(), &pair); err != nil {
		t.Fatalf("decode rotated pair: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Error("rotation must return both replacement tokens")
	}
	if pair.SessionID != currentSessionID {
		t.Errorf("session = %q, want %q", pair.SessionID, currentSessionID)
	}

	store.rotation = session.RotationOutcome{Replayed: true}
	replay := postSessionJSON(t, handler, "/v1/auth/refresh", `{"refreshToken":"live-refresh"}`)
	if replay.Code != http.StatusUnauthorized {
		t.Fatalf("replay status = %d, want 401", replay.Code)
	}
	assertSessionErrorCode(t, replay, string(session.Unauthenticated))
	if strings.Contains(strings.ToLower(replay.Body.String()), "replay") {
		t.Error("the replay response must not describe why authentication failed")
	}
}

func TestRefreshRejectsMalformedAndUnknownFieldBodies(t *testing.T) {
	handler, _ := newSessionAPI(t)

	for _, body := range []string{
		`{`,
		`{"refreshToken":"a","userID":"forged"}`,
		`{"refreshToken":1}`,
	} {
		response := postSessionJSON(t, handler, "/v1/auth/refresh", body)
		if response.Code != http.StatusBadRequest {
			t.Errorf("body %s produced %d, want 400", body, response.Code)
		}
	}
}

func TestRefreshWithAnEmptyTokenIsUnauthenticated(t *testing.T) {
	handler, _ := newSessionAPI(t)

	response := postSessionJSON(t, handler, "/v1/auth/refresh", `{"refreshToken":""}`)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", response.Code)
	}
	assertSessionErrorCode(t, response, string(session.Unauthenticated))
}

func TestLogoutRevokesByRefreshTokenAndReturnsNoContent(t *testing.T) {
	handler, store := newSessionAPI(t)

	response := postSessionJSON(t, handler, "/v1/auth/logout", `{"refreshToken":"live-refresh"}`)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204: %s", response.Code, response.Body.String())
	}
	if !store.revokedByRefresh {
		t.Error("logout must revoke through the presented refresh token")
	}
	if response.Body.Len() != 0 {
		t.Error("a 204 response must carry no body")
	}
}

func newSessionAPI(t *testing.T) (http.Handler, *sessionStoreDouble) {
	t.Helper()
	store := &sessionStoreDouble{
		principal: session.Principal{
			UserID:    sessionOwnerID,
			SessionID: currentSessionID,
		},
	}
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, nil, func() time.Time { return clock })
	return httpapi.NewSessionHandler(manager, func() string { return "test-request" }), store
}

func postSessionJSON(t *testing.T, handler http.Handler, path string, body string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

func assertSessionErrorCode(t *testing.T, response *httptest.ResponseRecorder, want string) {
	t.Helper()
	var envelope struct {
		Error struct {
			Code      string `json:"code"`
			RequestID string `json:"requestID"`
		} `json:"error"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("decode error envelope from %q: %v", response.Body.String(), err)
	}
	if envelope.Error.Code != want {
		t.Errorf("error code = %q, want %q", envelope.Error.Code, want)
	}
	if envelope.Error.RequestID == "" {
		t.Error("error responses must carry a request ID")
	}
}

type sessionStoreDouble struct {
	mutex sync.Mutex

	principal       session.Principal
	authenticateErr error

	devices      []session.DeviceSession
	listedUserID string

	rotation session.RotationOutcome

	revokedUserID    string
	revokedSessionID string
	revokedByRefresh bool
	revokeErr        error
}

func (s *sessionStoreDouble) CreateSession(_ context.Context, _ session.NewSession) error {
	return nil
}

func (s *sessionStoreDouble) AuthenticateAccess(
	_ context.Context,
	_ [32]byte,
	_ time.Time,
) (session.Principal, error) {
	if s.authenticateErr != nil {
		return session.Principal{}, s.authenticateErr
	}
	return s.principal, nil
}

func (s *sessionStoreDouble) RotateRefresh(
	_ context.Context,
	_ session.Rotation,
) (session.RotationOutcome, error) {
	return s.rotation, nil
}

func (s *sessionStoreDouble) RevokeByRefresh(_ context.Context, _ [32]byte, _ time.Time) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.revokedByRefresh = true
	return nil
}

func (s *sessionStoreDouble) ListDevices(
	_ context.Context,
	userID string,
	_ time.Time,
) ([]session.DeviceSession, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.listedUserID = userID
	return s.devices, nil
}

func (s *sessionStoreDouble) RevokeSession(
	_ context.Context,
	userID string,
	sessionID string,
	_ time.Time,
) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if s.revokeErr != nil {
		return s.revokeErr
	}
	s.revokedUserID = userID
	s.revokedSessionID = sessionID
	return nil
}

func (s *sessionStoreDouble) RevokeAllForUser(
	_ context.Context,
	userID string,
	_ string,
	_ time.Time,
) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.revokedUserID = userID
	return nil
}
