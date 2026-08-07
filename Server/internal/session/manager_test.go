package session_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/session"
)

func TestIssueMintsThirtyTwoByteOpaqueTokensAndPersistsOnlyHashes(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))

	pair, err := manager.Issue(context.Background(), userA, deviceMetadata("installation-a", "iPhone"), clock)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	for name, token := range map[string]string{
		"access":  pair.AccessToken,
		"refresh": pair.RefreshToken,
	} {
		raw, decodeErr := base64.RawURLEncoding.DecodeString(token)
		if decodeErr != nil {
			t.Fatalf("%s token is not base64url: %v", name, decodeErr)
		}
		if len(raw) != 32 {
			t.Errorf("%s token carries %d random bytes, want 32", name, len(raw))
		}
	}
	if pair.AccessToken == pair.RefreshToken {
		t.Error("access and refresh tokens must not be identical")
	}

	created := store.created
	if created.AccessHash != sha256.Sum256([]byte(pair.AccessToken)) {
		t.Error("stored access hash is not the SHA-256 of the issued access token")
	}
	if created.RefreshHash != sha256.Sum256([]byte(pair.RefreshToken)) {
		t.Error("stored refresh hash is not the SHA-256 of the issued refresh token")
	}
	if leaked := store.leakedPlaintext(pair.AccessToken, pair.RefreshToken); leaked != "" {
		t.Errorf("store received plaintext token material in %s", leaked)
	}
}

func TestIssueDerivesPrincipalFieldsFromTheServerNotTheClient(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))

	pair, err := manager.Issue(context.Background(), userA, deviceMetadata("installation-a", "iPhone"), clock)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	if pair.UserID != userA {
		t.Errorf("user ID = %q, want %q", pair.UserID, userA)
	}
	if pair.SessionID == "" {
		t.Error("issued pair must carry a server-generated session ID")
	}
	if !pair.RecentAuthAt.Equal(clock) {
		t.Errorf("recent auth = %s, want %s", pair.RecentAuthAt, clock)
	}
	if !pair.AccessExpiresAt.After(clock) {
		t.Error("access token must expire in the future")
	}
	if !pair.RefreshExpiresAt.After(pair.AccessExpiresAt) {
		t.Error("refresh token must outlive the access token")
	}
}

func TestRefreshRotatesBothTokensInOneAtomicStoreCall(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))

	original, err := manager.Issue(context.Background(), userA, deviceMetadata("installation-a", "iPhone"), clock)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	store.rotation = session.RotationOutcome{
		UserID:       userA,
		SessionID:    original.SessionID,
		RecentAuthAt: clock,
	}

	rotated, err := manager.Refresh(context.Background(), original.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}

	if store.rotateCalls != 1 {
		t.Errorf("rotation used %d store calls, want exactly 1 atomic call", store.rotateCalls)
	}
	if rotated.RefreshToken == original.RefreshToken {
		t.Error("refresh token was not rotated")
	}
	if rotated.AccessToken == original.AccessToken {
		t.Error("access token was not rotated")
	}
	if store.lastRotation.PresentedHash != sha256.Sum256([]byte(original.RefreshToken)) {
		t.Error("store was not asked to consume the presented refresh token hash")
	}
	if store.lastRotation.RefreshHash != sha256.Sum256([]byte(rotated.RefreshToken)) {
		t.Error("store did not receive the replacement refresh hash")
	}
	if rotated.SessionID != original.SessionID {
		t.Error("rotation must stay inside the same session")
	}
}

func TestRefreshRejectsAReplayedRefreshTokenWithoutRevealingSessionState(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	store.rotation = session.RotationOutcome{Replayed: true}

	_, err := manager.Refresh(context.Background(), "replayed-token")

	assertSessionErrorCode(t, err, session.Unauthenticated)
}

func TestConcurrentRefreshLetsExactlyOneCallerWin(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(1024)), staticClock(clock))

	original, err := manager.Issue(context.Background(), userA, deviceMetadata("installation-a", "iPhone"), clock)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	store.consumeOnce(original.RefreshToken, session.RotationOutcome{
		UserID:       userA,
		SessionID:    original.SessionID,
		RecentAuthAt: clock,
	})

	var group sync.WaitGroup
	results := make([]error, 2)
	group.Add(2)
	for index := range results {
		go func() {
			defer group.Done()
			_, results[index] = manager.Refresh(context.Background(), original.RefreshToken)
		}()
	}
	group.Wait()

	successes := 0
	for _, err := range results {
		if err == nil {
			successes++
			continue
		}
		assertSessionErrorCode(t, err, session.Unauthenticated)
	}
	if successes != 1 {
		t.Errorf("%d concurrent refreshes succeeded, want exactly 1", successes)
	}
}

func TestListDevicesScopesToThePrincipalAndMarksTheCurrentDevice(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	store.devices = map[string][]session.DeviceSession{
		userA: {
			{SessionID: "session-a1", DisplayName: "iPhone", Platform: "iOS", LastActiveAt: clock},
			{SessionID: "session-a2", DisplayName: "iPad", Platform: "iPadOS", LastActiveAt: clock},
		},
		userB: {
			{SessionID: "session-b1", DisplayName: "Other iPhone", Platform: "iOS", LastActiveAt: clock},
		},
	}

	devices, err := manager.ListDevices(context.Background(), session.Principal{
		UserID:    userA,
		SessionID: "session-a2",
	})
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}

	if store.listedUserID != userA {
		t.Errorf("store was queried for user %q, want %q", store.listedUserID, userA)
	}
	if len(devices) != 2 {
		t.Fatalf("returned %d devices, want the 2 owned by the principal", len(devices))
	}
	current := map[string]bool{}
	for _, device := range devices {
		current[device.SessionID] = device.Current
	}
	if !current["session-a2"] {
		t.Error("the principal's own session must be marked as the current device")
	}
	if current["session-a1"] {
		t.Error("a different session of the same user must not be marked current")
	}
}

func TestRevokeSessionUsesThePrincipalUserIDAndKeepsTheCurrentSessionAlive(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))

	principal := session.Principal{UserID: userA, SessionID: "session-a2"}
	if err := manager.RevokeSession(context.Background(), principal, "session-a1"); err != nil {
		t.Fatalf("revoke session: %v", err)
	}

	if store.revokedUserID != userA {
		t.Errorf("revocation scoped to user %q, want the authenticated %q", store.revokedUserID, userA)
	}
	if store.revokedSessionID != "session-a1" {
		t.Errorf("revoked session %q, want session-a1", store.revokedSessionID)
	}
	if store.revokedSessionID == principal.SessionID {
		t.Error("revoking another device must not revoke the current session")
	}
}

func TestRevokeSessionRefusesToTargetAnotherUsersSession(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	store.revokeErr = &session.Error{Code: session.NotFound}

	err := manager.RevokeSession(context.Background(), session.Principal{
		UserID:    userA,
		SessionID: "session-a2",
	}, "session-b1")

	assertSessionErrorCode(t, err, session.NotFound)
}

func TestAuthenticateAccessRejectsAnEmptyOrUnknownBearerToken(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	store.authenticateErr = &session.Error{Code: session.Unauthenticated}

	if _, err := manager.AuthenticateAccess(context.Background(), ""); err == nil {
		t.Error("an empty bearer token must not authenticate")
	} else {
		assertSessionErrorCode(t, err, session.Unauthenticated)
	}

	if _, err := manager.AuthenticateAccess(context.Background(), "unknown"); err == nil {
		t.Error("an unknown bearer token must not authenticate")
	} else {
		assertSessionErrorCode(t, err, session.Unauthenticated)
	}
}

func TestLogoutRevokesByThePresentedRefreshTokenHash(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))

	if err := manager.Logout(context.Background(), "refresh-token-value"); err != nil {
		t.Fatalf("logout: %v", err)
	}

	if store.revokedRefreshHash != sha256.Sum256([]byte("refresh-token-value")) {
		t.Error("logout must revoke by the SHA-256 of the presented refresh token")
	}
}

const (
	userA = "11111111-1111-4111-8111-111111111111"
	userB = "22222222-2222-4222-8222-222222222222"
)

func deviceMetadata(installationID string, displayName string) session.DeviceMetadata {
	return session.DeviceMetadata{
		DeviceID:    installationID,
		DisplayName: displayName,
		Platform:    "iOS",
		AppVersion:  "1.0.0",
	}
}

func staticClock(at time.Time) func() time.Time {
	return func() time.Time { return at }
}

func sequentialBytes(count int) []byte {
	values := make([]byte, count)
	for index := range values {
		values[index] = byte(index % 251)
	}
	return values
}

func assertSessionErrorCode(t *testing.T, err error, want session.ErrorCode) {
	t.Helper()
	var sessionError *session.Error
	if !errors.As(err, &sessionError) {
		t.Fatalf("error %v is not a *session.Error", err)
	}
	if sessionError.Code != want {
		t.Errorf("error code = %q, want %q", sessionError.Code, want)
	}
}

type fakeStore struct {
	mutex sync.Mutex

	created      session.NewSession
	lastRotation session.Rotation
	rotateCalls  int
	rotation     session.RotationOutcome
	consumable   map[string]session.RotationOutcome

	devices      map[string][]session.DeviceSession
	listedUserID string

	revokedUserID      string
	revokedSessionID   string
	revokedRefreshHash [32]byte
	revokeErr          error
	authenticateErr    error
}

func newFakeStore() *fakeStore {
	return &fakeStore{devices: map[string][]session.DeviceSession{}}
}

// consumeOnce lets exactly one rotation of the token succeed; later attempts
// observe the consumed row and report a replay, mirroring the MySQL store.
func (s *fakeStore) consumeOnce(token string, outcome session.RotationOutcome) {
	hash := hashOf(token)
	s.consumable = map[string]session.RotationOutcome{
		string(hash[:]): outcome,
	}
}

func (s *fakeStore) CreateSession(_ context.Context, created session.NewSession) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.created = created
	return nil
}

func (s *fakeStore) AuthenticateAccess(
	_ context.Context,
	_ [32]byte,
	_ time.Time,
) (session.Principal, error) {
	if s.authenticateErr != nil {
		return session.Principal{}, s.authenticateErr
	}
	return session.Principal{UserID: userA, SessionID: "session-a2"}, nil
}

func (s *fakeStore) RotateRefresh(
	_ context.Context,
	rotation session.Rotation,
) (session.RotationOutcome, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.rotateCalls++
	s.lastRotation = rotation
	if s.consumable != nil {
		key := string(rotation.PresentedHash[:])
		outcome, available := s.consumable[key]
		if !available {
			return session.RotationOutcome{Replayed: true}, nil
		}
		delete(s.consumable, key)
		return outcome, nil
	}
	return s.rotation, nil
}

func (s *fakeStore) RevokeByRefresh(_ context.Context, refreshHash [32]byte, _ time.Time) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.revokedRefreshHash = refreshHash
	return nil
}

func (s *fakeStore) ListDevices(
	_ context.Context,
	userID string,
	_ time.Time,
) ([]session.DeviceSession, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.listedUserID = userID
	return s.devices[userID], nil
}

func (s *fakeStore) RevokeSession(
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

func (s *fakeStore) RevokeAllForUser(
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

// leakedPlaintext reports the field name holding raw token material, if any.
func (s *fakeStore) leakedPlaintext(tokens ...string) string {
	for _, token := range tokens {
		if token == "" {
			continue
		}
		if strings.Contains(s.created.UserID, token) ||
			strings.Contains(s.created.Device.DeviceID, token) ||
			strings.Contains(s.created.Device.DisplayName, token) {
			return "NewSession"
		}
	}
	return ""
}

func hashOf(token string) [32]byte {
	return sha256.Sum256([]byte(token))
}
