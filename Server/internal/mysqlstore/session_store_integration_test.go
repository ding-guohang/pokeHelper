//go:build integration

package mysqlstore_test

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/session"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestSessionCreationPersistsOnlyTokenHashes(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)

	pair, err := manager.Issue(
		context.Background(),
		userID,
		sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone 16 Pro"),
		clock.now,
	)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	accessHash := sha256.Sum256([]byte(pair.AccessToken))
	refreshHash := sha256.Sum256([]byte(pair.RefreshToken))

	var storedAccess []byte
	if err := db.QueryRow(
		"SELECT current_access_token_hash FROM sessions WHERE id = UNHEX(REPLACE(?, '-', ''))",
		pair.SessionID,
	).Scan(&storedAccess); err != nil {
		t.Fatalf("read stored access hash: %v", err)
	}
	if string(storedAccess) != string(accessHash[:]) {
		t.Error("sessions.current_access_token_hash is not the SHA-256 of the issued token")
	}

	var storedRefreshCount int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM refresh_tokens WHERE token_hash = ?",
		refreshHash[:],
	).Scan(&storedRefreshCount); err != nil {
		t.Fatalf("read stored refresh hash: %v", err)
	}
	if storedRefreshCount != 1 {
		t.Errorf("stored %d refresh rows for the issued token, want 1", storedRefreshCount)
	}

	assertNoPlaintextTokenInDatabase(t, db, pair.AccessToken, pair.RefreshToken)
}

func TestAccessTokenAuthenticationResolvesAServerDerivedPrincipal(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)
	installationID := "6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071"

	pair, err := manager.Issue(context.Background(), userID, sessionDevice(installationID, "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	principal, err := manager.AuthenticateAccess(context.Background(), pair.AccessToken)
	if err != nil {
		t.Fatalf("authenticate access: %v", err)
	}
	if principal.UserID != userID {
		t.Errorf("principal user = %q, want %q", principal.UserID, userID)
	}
	if principal.SessionID != pair.SessionID {
		t.Errorf("principal session = %q, want %q", principal.SessionID, pair.SessionID)
	}
	if principal.DeviceID != installationID {
		t.Errorf("principal device = %q, want the installation ID %q", principal.DeviceID, installationID)
	}

	if _, err := manager.AuthenticateAccess(context.Background(), pair.RefreshToken); err == nil {
		t.Error("a refresh token must not authenticate as a bearer access token")
	}
}

func TestExpiredAndRevokedAccessTokensAreRejected(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)

	pair, err := manager.Issue(context.Background(), userID, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	clock.now = clock.now.Add(16 * time.Minute)
	if _, err := manager.AuthenticateAccess(context.Background(), pair.AccessToken); err == nil {
		t.Error("an expired access token must not authenticate")
	}

	clock.now = clock.now.Add(-16 * time.Minute)
	if err := manager.RevokeAllSessions(context.Background(), userID); err != nil {
		t.Fatalf("revoke all sessions: %v", err)
	}
	if _, err := manager.AuthenticateAccess(context.Background(), pair.AccessToken); err == nil {
		t.Error("a revoked session must not authenticate")
	}
}

func TestRefreshRotationInvalidatesTheOldTokenAndReplayRevokesTheWholeFamily(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)

	original, err := manager.Issue(context.Background(), userID, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	clock.now = clock.now.Add(time.Minute)
	rotated, err := manager.Refresh(context.Background(), original.RefreshToken)
	if err != nil {
		t.Fatalf("rotate refresh token: %v", err)
	}
	if rotated.RefreshToken == original.RefreshToken {
		t.Fatal("rotation returned the same refresh token")
	}
	if rotated.SessionID != original.SessionID {
		t.Errorf("rotation moved to session %q, want %q", rotated.SessionID, original.SessionID)
	}

	// The rotated access token works and the superseded one does not.
	if _, err := manager.AuthenticateAccess(context.Background(), rotated.AccessToken); err != nil {
		t.Errorf("rotated access token must authenticate: %v", err)
	}
	if _, err := manager.AuthenticateAccess(context.Background(), original.AccessToken); err == nil {
		t.Error("the superseded access token must stop authenticating")
	}

	// Replaying the consumed refresh token revokes the entire family.
	clock.now = clock.now.Add(time.Minute)
	if _, err := manager.Refresh(context.Background(), original.RefreshToken); err == nil {
		t.Fatal("replaying a consumed refresh token must fail")
	} else {
		assertSessionCode(t, err, session.Unauthenticated)
	}

	if _, err := manager.AuthenticateAccess(context.Background(), rotated.AccessToken); err == nil {
		t.Error("replay must revoke the access token issued by the winning rotation")
	}
	if _, err := manager.Refresh(context.Background(), rotated.RefreshToken); err == nil {
		t.Error("replay must revoke the live refresh token of the same family")
	}

	var liveSessions int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM sessions WHERE id = UNHEX(REPLACE(?, '-', '')) AND revoked_at IS NULL",
		original.SessionID,
	).Scan(&liveSessions); err != nil {
		t.Fatalf("count live sessions: %v", err)
	}
	if liveSessions != 0 {
		t.Error("the replayed session family must be fully revoked")
	}
}

func TestConsumedRefreshTokensAreRetainedSoReplayStaysDetectable(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)

	original, err := manager.Issue(context.Background(), userID, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}
	clock.now = clock.now.Add(time.Minute)
	if _, err := manager.Refresh(context.Background(), original.RefreshToken); err != nil {
		t.Fatalf("rotate refresh token: %v", err)
	}

	consumedHash := sha256.Sum256([]byte(original.RefreshToken))
	var consumedAt sql.NullTime
	if err := db.QueryRow(
		"SELECT consumed_at FROM refresh_tokens WHERE token_hash = ?",
		consumedHash[:],
	).Scan(&consumedAt); err != nil {
		t.Fatalf("the consumed refresh row must be retained, not deleted: %v", err)
	}
	if !consumedAt.Valid {
		t.Error("the rotated refresh token must be marked consumed")
	}
}

func TestConcurrentRefreshOfTheSameTokenLetsExactlyOneCallerWin(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	userID := createSessionUser(t, db)

	original, err := manager.Issue(context.Background(), userID, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	const callers = 2
	var group sync.WaitGroup
	errs := make([]error, callers)
	group.Add(callers)
	for index := range errs {
		go func() {
			defer group.Done()
			_, errs[index] = manager.Refresh(context.Background(), original.RefreshToken)
		}()
	}
	group.Wait()

	successes := 0
	for _, err := range errs {
		if err == nil {
			successes++
			continue
		}
		assertSessionCode(t, err, session.Unauthenticated)
	}
	if successes != 1 {
		t.Errorf("%d concurrent rotations succeeded, want exactly 1", successes)
	}

	var liveTokens int
	if err := db.QueryRow(`
		SELECT COUNT(*) FROM refresh_tokens
		WHERE user_id = UNHEX(REPLACE(?, '-', ''))
		  AND consumed_at IS NULL AND revoked_at IS NULL`,
		userID,
	).Scan(&liveTokens); err != nil {
		t.Fatalf("count live refresh tokens: %v", err)
	}
	if liveTokens != 0 {
		t.Errorf("%d refresh tokens stayed live after a contended replay, want 0", liveTokens)
	}
}

func TestListDevicesReturnsOnlyTheOwnersLiveSessions(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)
	stranger := createSessionUser(t, db)

	phone, err := manager.Issue(context.Background(), owner, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue phone session: %v", err)
	}
	clock.now = clock.now.Add(time.Minute)
	tablet, err := manager.Issue(context.Background(), owner, sessionDevice("7a2b3c4d-5e6f-4071-8b2c-3d4e5f607182", "iPad"), clock.now)
	if err != nil {
		t.Fatalf("issue tablet session: %v", err)
	}
	if _, err := manager.Issue(context.Background(), stranger, sessionDevice("8b3c4d5e-6f70-4182-8c3d-4e5f60718293", "Other iPhone"), clock.now); err != nil {
		t.Fatalf("issue stranger session: %v", err)
	}

	devices, err := manager.ListDevices(context.Background(), session.Principal{
		UserID:    owner,
		SessionID: tablet.SessionID,
	})
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}

	if len(devices) != 2 {
		t.Fatalf("listed %d devices, want the owner's 2", len(devices))
	}
	marked := map[string]bool{}
	for _, device := range devices {
		marked[device.SessionID] = device.Current
		if device.DisplayName == "Other iPhone" {
			t.Error("device list leaked another user's session")
		}
	}
	if !marked[tablet.SessionID] {
		t.Error("the caller's own session must be marked current")
	}
	if marked[phone.SessionID] {
		t.Error("a different session must not be marked current")
	}
}

func TestRevokingAnotherDeviceKeepsTheCurrentSessionAlive(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)

	phone, err := manager.Issue(context.Background(), owner, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue phone session: %v", err)
	}
	clock.now = clock.now.Add(time.Minute)
	tablet, err := manager.Issue(context.Background(), owner, sessionDevice("7a2b3c4d-5e6f-4071-8b2c-3d4e5f607182", "iPad"), clock.now)
	if err != nil {
		t.Fatalf("issue tablet session: %v", err)
	}

	current := session.Principal{UserID: owner, SessionID: tablet.SessionID}
	if err := manager.RevokeSession(context.Background(), current, phone.SessionID); err != nil {
		t.Fatalf("revoke phone session: %v", err)
	}

	if _, err := manager.AuthenticateAccess(context.Background(), phone.AccessToken); err == nil {
		t.Error("the revoked device must lose its access credential")
	}
	if _, err := manager.Refresh(context.Background(), phone.RefreshToken); err == nil {
		t.Error("the revoked device must lose its refresh credential")
	}
	if _, err := manager.AuthenticateAccess(context.Background(), tablet.AccessToken); err != nil {
		t.Errorf("the current session must stay valid: %v", err)
	}
}

func TestRevokingASessionOwnedByAnotherUserReportsNotFound(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)
	stranger := createSessionUser(t, db)

	victim, err := manager.Issue(context.Background(), stranger, sessionDevice("8b3c4d5e-6f70-4182-8c3d-4e5f60718293", "Victim iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue victim session: %v", err)
	}

	err = manager.RevokeSession(context.Background(), session.Principal{
		UserID:    owner,
		SessionID: "1c2d3e4f-5061-4728-8394-a5b6c7d8e9f0",
	}, victim.SessionID)

	assertSessionCode(t, err, session.NotFound)

	if _, err := manager.AuthenticateAccess(context.Background(), victim.AccessToken); err != nil {
		t.Errorf("a cross-user revocation attempt must not affect the victim: %v", err)
	}
}

func TestLogoutRevokesTheSessionAndIsIdempotent(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)

	pair, err := manager.Issue(context.Background(), owner, sessionDevice("6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071", "iPhone"), clock.now)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	if err := manager.Logout(context.Background(), pair.RefreshToken); err != nil {
		t.Fatalf("logout: %v", err)
	}
	if _, err := manager.AuthenticateAccess(context.Background(), pair.AccessToken); err == nil {
		t.Error("logout must invalidate the access token")
	}
	if err := manager.Logout(context.Background(), pair.RefreshToken); err != nil {
		t.Errorf("logout must be idempotent: %v", err)
	}
	if err := manager.Logout(context.Background(), "never-issued"); err != nil {
		t.Errorf("logging out an unknown token must not error: %v", err)
	}
}

func TestReusingAnInstallationKeepsOneDeviceRow(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)
	installationID := "6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071"

	if _, err := manager.Issue(context.Background(), owner, sessionDevice(installationID, "iPhone"), clock.now); err != nil {
		t.Fatalf("issue first session: %v", err)
	}
	clock.now = clock.now.Add(time.Hour)
	if _, err := manager.Issue(context.Background(), owner, sessionDevice(installationID, "iPhone 16 Pro"), clock.now); err != nil {
		t.Fatalf("issue second session: %v", err)
	}

	var devices int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM devices WHERE user_id = UNHEX(REPLACE(?, '-', ''))",
		owner,
	).Scan(&devices); err != nil {
		t.Fatalf("count devices: %v", err)
	}
	if devices != 1 {
		t.Errorf("the same installation produced %d device rows, want 1", devices)
	}

	var displayName string
	if err := db.QueryRow(
		"SELECT display_name FROM devices WHERE user_id = UNHEX(REPLACE(?, '-', ''))",
		owner,
	).Scan(&displayName); err != nil {
		t.Fatalf("read device display name: %v", err)
	}
	if displayName != "iPhone 16 Pro" {
		t.Errorf("device display name = %q, want the refreshed %q", displayName, "iPhone 16 Pro")
	}
}

func newSessionFixture(t *testing.T) (*sql.DB, *session.Manager, *mutableClock) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	clock := &mutableClock{now: time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC)}
	manager := session.NewManager(mysqlstore.NewSessionStore(db), nil, clock.Now)
	return db, manager, clock
}

func createSessionUser(t *testing.T, db *sql.DB) string {
	t.Helper()
	var id string
	if err := db.QueryRow("SELECT UUID()").Scan(&id); err != nil {
		t.Fatalf("generate user id: %v", err)
	}
	if _, err := db.Exec(
		"INSERT INTO users (id) VALUES (UNHEX(REPLACE(?, '-', '')))",
		id,
	); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	return id
}

func sessionDevice(installationID string, displayName string) session.DeviceMetadata {
	return session.DeviceMetadata{
		DeviceID:    installationID,
		DisplayName: displayName,
		Platform:    "iOS",
		AppVersion:  "1.0.0",
	}
}

func assertSessionCode(t *testing.T, err error, want session.ErrorCode) {
	t.Helper()
	var sessionError *session.Error
	if !errors.As(err, &sessionError) {
		t.Fatalf("error %v is not a *session.Error", err)
	}
	if sessionError.Code != want {
		t.Errorf("error code = %q, want %q", sessionError.Code, want)
	}
}

// assertNoPlaintextTokenInDatabase scans every text column that could plausibly
// hold leaked credential material.
func assertNoPlaintextTokenInDatabase(t *testing.T, db *sql.DB, tokens ...string) {
	t.Helper()
	rows, err := db.Query(`
		SELECT display_name, platform, app_version FROM devices`)
	if err != nil {
		t.Fatalf("scan devices for plaintext: %v", err)
	}
	defer func() { _ = rows.Close() }()

	for rows.Next() {
		var displayName, platform, appVersion string
		if err := rows.Scan(&displayName, &platform, &appVersion); err != nil {
			t.Fatalf("scan device row: %v", err)
		}
		for _, token := range tokens {
			for _, field := range []string{displayName, platform, appVersion} {
				if strings.Contains(field, token) {
					t.Errorf("device row stores plaintext token material %q", field)
				}
			}
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate device rows: %v", err)
	}
}

// The device list is what the user reads to decide which session to revoke, so
// its fields have to carry real values. The existing test only asserted that
// another user's device was absent, which a blank row would also satisfy.
func TestTheDeviceListReportsTheDetailsTheClientSupplied(t *testing.T) {
	db, manager, clock := newSessionFixture(t)
	owner := createSessionUser(t, db)
	installationID := "6f1a2b3c-4d5e-4f60-8a1b-2c3d4e5f6071"

	pair, err := manager.Issue(
		context.Background(),
		owner,
		session.DeviceMetadata{
			DeviceID:    installationID,
			DisplayName: "Wenzheng 的 iPad",
			Platform:    "iPadOS",
			AppVersion:  "1.4.2",
		},
		clock.now,
	)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	devices, err := manager.ListDevices(context.Background(), session.Principal{
		UserID:    owner,
		SessionID: pair.SessionID,
	})
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}

	device := devices[0]
	if device.DisplayName != "Wenzheng 的 iPad" {
		t.Errorf("displayName = %q", device.DisplayName)
	}
	if device.Platform != "iPadOS" {
		t.Errorf("platform = %q", device.Platform)
	}
	if device.AppVersion != "1.4.2" {
		t.Errorf("appVersion = %q, want the value the client sent", device.AppVersion)
	}
	if device.DeviceID != installationID {
		t.Errorf("deviceID = %q, want the installation ID", device.DeviceID)
	}
	if device.LastActiveAt.IsZero() || device.CreatedAt.IsZero() {
		t.Error("the list must carry real timestamps")
	}
	if !device.Current {
		t.Error("the caller's own session must be marked current")
	}
}
