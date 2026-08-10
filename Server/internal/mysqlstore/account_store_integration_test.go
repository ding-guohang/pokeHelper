//go:build integration

package mysqlstore_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/session"
	"porkhelper/server/internal/sync"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

// The table list is read from the schema rather than hard-coded, so a table
// added later that carries a user_id fails this test until deletion covers it.
func TestDeletionEmptiesEveryTableThatCanHoldTheUser(t *testing.T) {
	db, store, owner := newAccountFixture(t)
	tables := userOwnedTables(t, db)
	if len(tables) < 8 {
		t.Fatalf("discovered only %d user-owned tables, schema lookup looks wrong", len(tables))
	}

	if err := store.Delete(context.Background(), owner.userID); err != nil {
		t.Fatalf("delete account: %v", err)
	}

	for table, column := range tables {
		var remaining int
		query := "SELECT COUNT(*) FROM " + table + " WHERE " + column + " = ?"
		if err := db.QueryRow(query, owner.userIDBytes).Scan(&remaining); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if remaining != 0 {
			t.Errorf("%s still holds %d rows for the deleted account", table, remaining)
		}
	}
}

// userOwnedTables maps each table that can reference a user to the column that
// does it.
func userOwnedTables(t *testing.T, db *sql.DB) map[string]string {
	t.Helper()
	rows, err := db.Query(`
		SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE()
		  AND ((COLUMN_NAME = 'user_id') OR (TABLE_NAME = 'users' AND COLUMN_NAME = 'id'))`)
	if err != nil {
		t.Fatalf("discover user-owned tables: %v", err)
	}
	defer func() { _ = rows.Close() }()

	tables := map[string]string{}
	for rows.Next() {
		var table, column string
		if err := rows.Scan(&table, &column); err != nil {
			t.Fatalf("scan schema row: %v", err)
		}
		tables[table] = column
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate schema rows: %v", err)
	}
	return tables
}

func TestABearerSessionCannotAuthenticateAfterDeletion(t *testing.T) {
	db, store, owner := newAccountFixture(t)
	manager := session.NewManager(mysqlstore.NewSessionStore(db), nil, time.Now)

	// The session works before deletion.
	if _, err := manager.AuthenticateAccess(context.Background(), owner.accessToken); err != nil {
		t.Fatalf("session must work before deletion: %v", err)
	}

	if err := store.Delete(context.Background(), owner.userID); err != nil {
		t.Fatalf("delete account: %v", err)
	}

	if _, err := manager.AuthenticateAccess(context.Background(), owner.accessToken); err == nil {
		t.Error("the access token must stop authenticating after deletion")
	}
	if _, err := manager.Refresh(context.Background(), owner.refreshToken); err == nil {
		t.Error("the refresh token must stop working after deletion")
	}
}

func TestDeletionIsScopedToItsOwner(t *testing.T) {
	db, store, owner := newAccountFixture(t)
	bystander := newAccountOwner(t, db)

	if err := store.Delete(context.Background(), owner.userID); err != nil {
		t.Fatalf("delete account: %v", err)
	}

	var remaining int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM users WHERE id = ?", bystander.userIDBytes,
	).Scan(&remaining); err != nil {
		t.Fatalf("count bystander: %v", err)
	}
	if remaining != 1 {
		t.Error("deleting one account must not touch another")
	}
}

func TestExportCarriesTheUsersDataAndNoCredentialMaterial(t *testing.T) {
	_, store, owner := newAccountFixture(t)

	document, err := store.Export(context.Background(), owner.userID)
	if err != nil {
		t.Fatalf("export: %v", err)
	}

	if document.SchemaVersion != account.ExportSchemaVersion {
		t.Errorf("schema version = %d", document.SchemaVersion)
	}
	if document.Account.UserID != owner.userID {
		t.Errorf("export names %q, want %q", document.Account.UserID, owner.userID)
	}
	if len(document.Devices) != 1 {
		t.Errorf("exported %d devices, want 1", len(document.Devices))
	}
	if len(document.Events) != 1 {
		t.Errorf("exported %d events, want 1", len(document.Events))
	}

	// Nothing in the document may carry a secret, in any field.
	encoded, err := json.Marshal(document)
	if err != nil {
		t.Fatalf("encode export: %v", err)
	}
	serialized := string(encoded)
	for name, secret := range map[string]string{
		"password hash":      owner.passwordPHC,
		"access token":       owner.accessToken,
		"refresh token":      owner.refreshToken,
		"argon2 marker":      "$argon2id$",
		"challenge fragment": "challenge",
	} {
		if secret == "" {
			continue
		}
		if strings.Contains(serialized, secret) {
			t.Errorf("export leaked %s", name)
		}
	}
}

func TestMarkRecentAuthenticationOnlyTouchesTheCallersOwnSession(t *testing.T) {
	db, store, owner := newAccountFixture(t)
	stranger := newAccountOwner(t, db)
	at := time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC)

	// A forged session id belonging to another account must not be refreshed.
	err := store.MarkRecentAuthentication(
		context.Background(), owner.userID, stranger.sessionID, at,
	)
	if err == nil {
		t.Error("refreshing another account's session must fail")
	}

	if err := store.MarkRecentAuthentication(
		context.Background(), owner.userID, owner.sessionID, at,
	); err != nil {
		t.Fatalf("refresh own session: %v", err)
	}

	var stored time.Time
	if err := db.QueryRow(
		"SELECT recent_authenticated_at FROM sessions WHERE id = UNHEX(REPLACE(?, '-', ''))",
		owner.sessionID,
	).Scan(&stored); err != nil {
		t.Fatalf("read recent auth: %v", err)
	}
	if !stored.UTC().Equal(at) {
		t.Errorf("recent auth = %s, want %s", stored.UTC(), at)
	}
}

type accountOwner struct {
	userID       string
	userIDBytes  []byte
	sessionID    string
	accessToken  string
	refreshToken string
	passwordPHC  string
}

func newAccountFixture(t *testing.T) (*sql.DB, *mysqlstore.AccountStore, accountOwner) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	return db, mysqlstore.NewAccountStore(db), newAccountOwner(t, db)
}

// newAccountOwner builds a fully populated account: identity, password,
// challenge, device, session, refresh token, sequence, event, and idempotency
// record, so deletion has something to remove from every table.
func newAccountOwner(t *testing.T, db *sql.DB) accountOwner {
	t.Helper()
	owner := accountOwner{
		userID:      randomUUIDString(t),
		sessionID:   randomUUIDString(t),
		passwordPHC: "$argon2id$v=19$m=19456,t=2,p=1$" + randomUUIDString(t),
	}
	userBytes, err := sync.UUIDBytes(owner.userID)
	if err != nil {
		t.Fatalf("decode user id: %v", err)
	}
	owner.userIDBytes = userBytes
	installationID := randomUUIDString(t)

	manager := session.NewManager(mysqlstore.NewSessionStore(db), nil, time.Now)

	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := db.Exec(query, args...); err != nil {
			t.Fatalf("seed %q: %v", query, err)
		}
	}

	exec("INSERT INTO users (id) VALUES (?)", userBytes)
	exec(`INSERT INTO auth_identities (id, user_id, provider, subject, canonical_email, display_email, email_verified)
	      VALUES (?, ?, 'email', ?, ?, ?, TRUE)`,
		mustUUIDBytes(t), userBytes,
		owner.userID+"@example.test", owner.userID+"@example.test", owner.userID+"@example.test",
	)
	exec("INSERT INTO password_credentials (user_id, password_hash, password_changed_at) VALUES (?, ?, NOW(3))",
		userBytes, owner.passwordPHC)
	exec(`INSERT INTO email_challenges (id, user_id, token_hash, purpose, attempt_count, expires_at)
	      VALUES (?, ?, ?, 'verifyEmail', 0, NOW(3))`,
		mustUUIDBytes(t), userBytes, mustUUIDBytes(t))
	exec("INSERT INTO user_sync_sequences (user_id, next_sequence) VALUES (?, 0)", userBytes)

	pair, err := manager.Issue(
		context.Background(),
		owner.userID,
		session.DeviceMetadata{
			DeviceID:    installationID,
			DisplayName: "iPhone",
			Platform:    "iOS",
			AppVersion:  "1.0.0",
		},
		time.Now().UTC(),
	)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}
	owner.sessionID = pair.SessionID
	owner.accessToken = pair.AccessToken
	owner.refreshToken = pair.RefreshToken

	syncStore := mysqlstore.NewSyncStore(db)
	if _, err := syncStore.Upload(context.Background(), uploadRequest(
		syncOwner{userID: owner.userID, installationID: installationID},
		"seed-batch",
		1,
	)); err != nil {
		t.Fatalf("seed training event: %v", err)
	}

	return owner
}

func mustUUIDBytes(t *testing.T) []byte {
	t.Helper()
	value, err := sync.UUIDBytes(randomUUIDString(t))
	if err != nil {
		t.Fatalf("decode uuid: %v", err)
	}
	return value
}
