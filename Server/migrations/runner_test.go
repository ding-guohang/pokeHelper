//go:build integration

package migrations_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"

	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestApplyMigratesAnEmptySchema(t *testing.T) {
	db := mysqltest.Database(t)
	ctx := context.Background()

	before, err := migrations.CurrentVersion(ctx, db)
	if err != nil {
		t.Fatalf("CurrentVersion() before Apply: %v", err)
	}
	if before != 0 {
		t.Fatalf("CurrentVersion() before Apply = %d, want 0", before)
	}

	if err := migrations.Apply(ctx, db); err != nil {
		t.Fatalf("Apply() error = %v", err)
	}

	after, err := migrations.CurrentVersion(ctx, db)
	if err != nil {
		t.Fatalf("CurrentVersion() after Apply: %v", err)
	}
	if after != 2 {
		t.Errorf("CurrentVersion() after Apply = %d, want 2", after)
	}
}

func TestApplyIsIdempotent(t *testing.T) {
	db := mysqltest.Database(t)
	ctx := context.Background()

	if err := migrations.Apply(ctx, db); err != nil {
		t.Fatalf("first Apply() error = %v", err)
	}
	if err := migrations.Apply(ctx, db); err != nil {
		t.Fatalf("second Apply() error = %v", err)
	}

	var count int
	if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM schema_migrations").Scan(&count); err != nil {
		t.Fatalf("count schema_migrations: %v", err)
	}
	if count != 2 {
		t.Errorf("schema_migrations count = %d, want 2", count)
	}
}

func TestInitialMigrationCreatesRequiredTables(t *testing.T) {
	db := migratedDatabase(t)

	rows, err := db.Query(`
		SELECT table_name
		FROM information_schema.tables
		WHERE table_schema = DATABASE()
		ORDER BY table_name`)
	if err != nil {
		t.Fatalf("query tables: %v", err)
	}
	defer rows.Close()

	var got []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan table: %v", err)
		}
		got = append(got, name)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate tables: %v", err)
	}

	want := []string{
		"auth_identities",
		"auth_throttles",
		"devices",
		"email_challenges",
		"idempotency_records",
		"password_credentials",
		"refresh_tokens",
		"schema_migrations",
		"sessions",
		"training_events",
		"user_sync_sequences",
		"users",
	}
	for _, name := range want {
		if !slices.Contains(got, name) {
			t.Errorf("required table %q missing; got %v", name, got)
		}
	}
}

func TestInitialMigrationUsesInnoDBAndUTF8MB4(t *testing.T) {
	db := migratedDatabase(t)

	rows, err := db.Query(`
		SELECT table_name, engine, table_collation
		FROM information_schema.tables
		WHERE table_schema = DATABASE()`)
	if err != nil {
		t.Fatalf("query table options: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var tableName, engine, collation string
		if err := rows.Scan(&tableName, &engine, &collation); err != nil {
			t.Fatalf("scan table options: %v", err)
		}
		if engine != "InnoDB" {
			t.Errorf("%s engine = %q, want InnoDB", tableName, engine)
		}
		if !strings.HasPrefix(collation, "utf8mb4_") {
			t.Errorf("%s collation = %q, want utf8mb4_*", tableName, collation)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate table options: %v", err)
	}
}

func TestUserOwnedTablesCascadeFromUsers(t *testing.T) {
	db := migratedDatabase(t)

	rows, err := db.Query(`
		SELECT table_name, delete_rule
		FROM information_schema.referential_constraints
		WHERE constraint_schema = DATABASE()
		  AND referenced_table_name = 'users'`)
	if err != nil {
		t.Fatalf("query user foreign keys: %v", err)
	}
	defer rows.Close()

	got := make(map[string]string)
	for rows.Next() {
		var tableName, deleteRule string
		if err := rows.Scan(&tableName, &deleteRule); err != nil {
			t.Fatalf("scan user foreign key: %v", err)
		}
		got[tableName] = deleteRule
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate user foreign keys: %v", err)
	}

	wantTables := []string{
		"auth_identities",
		"password_credentials",
		"email_challenges",
		"devices",
		"sessions",
		"refresh_tokens",
		"user_sync_sequences",
		"training_events",
		"idempotency_records",
	}
	for _, tableName := range wantTables {
		rule, ok := got[tableName]
		if !ok {
			t.Errorf("%s has no foreign key to users", tableName)
			continue
		}
		if rule != "CASCADE" {
			t.Errorf("%s delete rule = %q, want CASCADE", tableName, rule)
		}
	}
}

func TestInitialMigrationDefinesRequiredIndexes(t *testing.T) {
	db := migratedDatabase(t)

	required := map[string][]string{
		"uq_auth_identities_provider_subject": {"provider", "subject"},
		"uq_devices_user_installation":        {"user_id", "installation_id"},
		"uq_refresh_tokens_token_hash":        {"token_hash"},
		"uq_training_events_user_event":       {"user_id", "event_id"},
		"uq_training_events_user_sequence":    {"user_id", "server_sequence"},
		"uq_idempotency_user_key":             {"user_id", "idempotency_key"},
		"idx_email_challenges_purpose_expiry": {"purpose", "expires_at"},
	}

	for indexName, wantColumns := range required {
		t.Run(indexName, func(t *testing.T) {
			tableName := tableForIndex(indexName)
			gotColumns, nonUnique := indexColumns(t, db, tableName, indexName)
			if !slices.Equal(gotColumns, wantColumns) {
				t.Errorf("columns = %v, want %v", gotColumns, wantColumns)
			}
			if strings.HasPrefix(indexName, "uq_") && nonUnique {
				t.Error("index is non-unique, want unique")
			}
		})
	}
}

func TestDeletingAUserDeletesTheCompleteOwnedGraph(t *testing.T) {
	db := migratedDatabase(t)
	ctx := context.Background()
	seedCompleteUserGraph(t, db)

	if _, err := db.ExecContext(ctx, "DELETE FROM users WHERE id = UUID_TO_BIN(?)", testUserID); err != nil {
		t.Fatalf("delete user: %v", err)
	}

	userOwnedTables := []string{
		"auth_identities",
		"password_credentials",
		"email_challenges",
		"devices",
		"sessions",
		"refresh_tokens",
		"user_sync_sequences",
		"training_events",
		"idempotency_records",
	}
	for _, tableName := range userOwnedTables {
		var count int
		query := fmt.Sprintf("SELECT COUNT(*) FROM `%s` WHERE user_id = UUID_TO_BIN(?)", tableName)
		if err := db.QueryRowContext(ctx, query, testUserID).Scan(&count); err != nil {
			t.Fatalf("count %s after user deletion: %v", tableName, err)
		}
		if count != 0 {
			t.Errorf("%s rows after user deletion = %d, want 0", tableName, count)
		}
	}
}

func TestRefreshTokenRejectsSessionOwnedByAnotherUser(t *testing.T) {
	db := migratedDatabase(t)
	ctx := context.Background()

	mustExec(t, db, `INSERT INTO users (id) VALUES (UUID_TO_BIN(?)), (UUID_TO_BIN(?))`,
		testUserID, secondUserID)
	mustExec(t, db, `
		INSERT INTO devices (id, user_id, installation_id, display_name, platform, app_version)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), 'iPhone', 'iOS', '1.0')`,
		testDeviceID, testUserID, testInstallationID)
	mustExec(t, db, `
		INSERT INTO sessions (
			id, user_id, device_id, token_family_id, current_access_token_hash,
			access_expires_at, recent_authenticated_at, last_active_at
		) VALUES (
			UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('11', 32)),
			NOW(3) + INTERVAL 15 MINUTE, NOW(3), NOW(3)
		)`,
		testSessionID, testUserID, testDeviceID, testTokenFamilyID)

	_, err := db.ExecContext(ctx, `
		INSERT INTO refresh_tokens (id, user_id, session_id, token_hash, expires_at)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('22', 32)), NOW(3) + INTERVAL 30 DAY)`,
		testRefreshID, secondUserID, testSessionID)
	var mysqlErr *mysql.MySQLError
	if !errors.As(err, &mysqlErr) || mysqlErr.Number != 1452 {
		t.Fatalf("cross-user refresh insert error = %v, want MySQL 1452", err)
	}
}

func TestUserSyncSequenceStartsAtZero(t *testing.T) {
	db := migratedDatabase(t)
	ctx := context.Background()

	mustExec(t, db, "INSERT INTO users (id) VALUES (UUID_TO_BIN(?))", testUserID)
	mustExec(t, db, "INSERT INTO user_sync_sequences (user_id) VALUES (UUID_TO_BIN(?))", testUserID)

	var got uint64
	if err := db.QueryRowContext(ctx,
		"SELECT next_sequence FROM user_sync_sequences WHERE user_id = UUID_TO_BIN(?)",
		testUserID,
	).Scan(&got); err != nil {
		t.Fatalf("read initial sync sequence: %v", err)
	}
	if got != 0 {
		t.Errorf("initial sync sequence = %d, want 0", got)
	}
}

func TestMySQLVersionMeets84Baseline(t *testing.T) {
	db := mysqltest.Database(t)

	var version string
	if err := db.QueryRow("SELECT VERSION()").Scan(&version); err != nil {
		t.Fatalf("query MySQL version: %v", err)
	}
	major, minor := mysqlVersion(t, version)
	if major < 8 || (major == 8 && minor < 4) {
		t.Fatalf("MySQL version = %q, want >= 8.4", version)
	}
}

func TestEveryUUIDColumnUsesBinary16(t *testing.T) {
	db := migratedDatabase(t)

	want := map[string]map[string]bool{
		"users":                {"id": true},
		"auth_identities":      {"id": true, "user_id": true},
		"password_credentials": {"user_id": true},
		"email_challenges":     {"id": true, "user_id": true},
		"devices":              {"id": true, "user_id": true, "installation_id": true},
		"sessions":             {"id": true, "user_id": true, "device_id": true, "token_family_id": true},
		"refresh_tokens":       {"id": true, "user_id": true, "session_id": true},
		"user_sync_sequences":  {"user_id": true},
		"training_events":      {"user_id": true, "event_id": true, "device_id": true},
		"idempotency_records":  {"user_id": true},
	}

	rows, err := db.Query(`
		SELECT table_name, column_name, data_type, character_octet_length
		FROM information_schema.columns
		WHERE table_schema = DATABASE()`)
	if err != nil {
		t.Fatalf("query UUID column types: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var tableName, columnName, dataType string
		var octetLength sql.NullInt64
		if err := rows.Scan(&tableName, &columnName, &dataType, &octetLength); err != nil {
			t.Fatalf("scan UUID column type: %v", err)
		}
		columns := want[tableName]
		if !columns[columnName] {
			continue
		}
		if dataType != "binary" || !octetLength.Valid || octetLength.Int64 != 16 {
			t.Errorf("%s.%s = %s(%v), want binary(16)", tableName, columnName, dataType, octetLength)
		}
		delete(columns, columnName)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate UUID column types: %v", err)
	}
	for tableName, columns := range want {
		for columnName := range columns {
			t.Errorf("expected UUID column %s.%s was not found", tableName, columnName)
		}
	}
}

func TestMySQLTestDatabaseRejectsMissingTemporaryServerProof(t *testing.T) {
	output, err := runDatabaseProofProbe(t, nil)
	if err == nil {
		t.Fatalf("proof probe succeeded without temporary-server proof; output:\n%s", output)
	}
	if !strings.Contains(output, "requires temporary MySQL server proof") {
		t.Fatalf("proof probe output = %q, want missing-proof error", output)
	}
}

func TestMySQLTestDatabaseRejectsMismatchedTemporaryServerProof(t *testing.T) {
	output, err := runDatabaseProofProbe(t, map[string]string{
		"POKER_COACH_MYSQL_TEST_DATADIR":     filepath.Dir(os.Getenv("POKER_COACH_MYSQL_TEST_DATADIR")),
		"POKER_COACH_MYSQL_TEST_SERVER_UUID": "00000000-0000-0000-0000-000000000000",
	})
	if err == nil {
		t.Fatalf("proof probe succeeded with mismatched temporary-server proof; output:\n%s", output)
	}
	if !strings.Contains(output, "temporary MySQL server proof mismatch") {
		t.Fatalf("proof probe output = %q, want proof-mismatch error", output)
	}
}

func TestMySQLTestDatabaseCleanupReprovesBeforeDrop(t *testing.T) {
	db := mysqltest.Database(t)
	output, err := runDatabaseProofProbeMode(t, "cleanup-mismatch", map[string]string{
		"POKER_COACH_MYSQL_TEST_DATADIR":     os.Getenv("POKER_COACH_MYSQL_TEST_DATADIR"),
		"POKER_COACH_MYSQL_TEST_SERVER_UUID": os.Getenv("POKER_COACH_MYSQL_TEST_SERVER_UUID"),
	})
	if err == nil {
		t.Errorf("cleanup probe succeeded after proof changed; output:\n%s", output)
	}
	if !strings.Contains(output, "refusing to drop isolated schema") {
		t.Errorf("cleanup probe output = %q, want safe cleanup failure", output)
	}

	matches := regexp.MustCompile(`MYSQLTEST_PROBE_SCHEMA=([a-z0-9_]+)`).FindStringSubmatch(output)
	if len(matches) != 2 {
		t.Fatalf("cleanup probe did not report its schema; output:\n%s", output)
	}
	var schemaCount int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = ?",
		matches[1],
	).Scan(&schemaCount); err != nil {
		t.Fatalf("query cleanup probe schema: %v", err)
	}
	if schemaCount != 1 {
		t.Errorf("cleanup probe schema count = %d, want 1 because DROP must be refused", schemaCount)
	}
}

func TestMySQLTestDatabaseProofProbe(t *testing.T) {
	mode := os.Getenv("POKER_COACH_MYSQL_PROOF_PROBE")
	if mode == "" {
		t.Skip("subprocess probe")
	}
	db := mysqltest.Database(t)
	if mode == "cleanup-mismatch" {
		var schemaName string
		if err := db.QueryRow("SELECT DATABASE()").Scan(&schemaName); err != nil {
			t.Fatalf("query cleanup probe schema: %v", err)
		}
		fmt.Printf("MYSQLTEST_PROBE_SCHEMA=%s\n", schemaName)
		if err := os.Setenv(
			"POKER_COACH_MYSQL_TEST_SERVER_UUID",
			"00000000-0000-0000-0000-000000000000",
		); err != nil {
			t.Fatalf("change cleanup proof: %v", err)
		}
	}
}

func TestApplyUpgradesOriginalVersionOneWithoutDataLoss(t *testing.T) {
	db := mysqltest.Database(t)
	ctx := context.Background()
	installOriginalVersionOne(t, db)
	seedCompleteUserGraph(t, db)
	mustExec(t, db, "INSERT INTO users (id) VALUES (UUID_TO_BIN(?))", secondUserID)
	invalidRefreshID := "00000000-0000-0000-0000-000000000602"
	mustExec(t, db, `
		INSERT INTO refresh_tokens (id, user_id, session_id, token_hash, expires_at)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('77', 32)), NOW(3) + INTERVAL 30 DAY)`,
		invalidRefreshID, secondUserID, testSessionID)

	if err := migrations.Apply(ctx, db); err != nil {
		t.Fatalf("Apply() original version 1 upgrade: %v", err)
	}
	version, err := migrations.CurrentVersion(ctx, db)
	if err != nil {
		t.Fatalf("CurrentVersion() after upgrade: %v", err)
	}
	if version != 2 {
		t.Fatalf("CurrentVersion() after upgrade = %d, want 2", version)
	}

	for tableName, wantCount := range map[string]int{
		"users":               2,
		"devices":             1,
		"sessions":            1,
		"refresh_tokens":      1,
		"user_sync_sequences": 1,
		"training_events":     1,
	} {
		var gotCount int
		query := fmt.Sprintf("SELECT COUNT(*) FROM `%s`", tableName)
		if err := db.QueryRowContext(ctx, query).Scan(&gotCount); err != nil {
			t.Fatalf("count %s after upgrade: %v", tableName, err)
		}
		if gotCount != wantCount {
			t.Errorf("%s count after upgrade = %d, want %d", tableName, gotCount, wantCount)
		}
	}

	for name, id := range map[string]string{
		"valid":   testRefreshID,
		"invalid": invalidRefreshID,
	} {
		var count int
		if err := db.QueryRowContext(ctx,
			"SELECT COUNT(*) FROM refresh_tokens WHERE id = UUID_TO_BIN(?)",
			id,
		).Scan(&count); err != nil {
			t.Fatalf("count %s refresh after upgrade: %v", name, err)
		}
		want := 1
		if name == "invalid" {
			want = 0
		}
		if count != want {
			t.Errorf("%s refresh count after upgrade = %d, want %d", name, count, want)
		}
	}

	_, err = db.ExecContext(ctx, `
		INSERT INTO refresh_tokens (id, user_id, session_id, token_hash, expires_at)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('88', 32)), NOW(3) + INTERVAL 30 DAY)`,
		"00000000-0000-0000-0000-000000000603", secondUserID, testSessionID)
	var mysqlErr *mysql.MySQLError
	if !errors.As(err, &mysqlErr) || mysqlErr.Number != 1452 {
		t.Errorf("cross-user refresh after upgrade error = %v, want MySQL 1452", err)
	}

	thirdUserID := "00000000-0000-0000-0000-000000000103"
	mustExec(t, db, "INSERT INTO users (id) VALUES (UUID_TO_BIN(?))", thirdUserID)
	mustExec(t, db, "INSERT INTO user_sync_sequences (user_id) VALUES (UUID_TO_BIN(?))", thirdUserID)
	var sequence uint64
	if err := db.QueryRowContext(ctx,
		"SELECT next_sequence FROM user_sync_sequences WHERE user_id = UUID_TO_BIN(?)",
		thirdUserID,
	).Scan(&sequence); err != nil {
		t.Fatalf("read sequence default after upgrade: %v", err)
	}
	if sequence != 0 {
		t.Errorf("sequence default after upgrade = %d, want 0", sequence)
	}

	if _, err := db.ExecContext(ctx, "DELETE FROM users WHERE id = UUID_TO_BIN(?)", testUserID); err != nil {
		t.Errorf("delete upgraded user graph: %v", err)
	}
}

func TestApplyResumesAfterCommittedDDLIsInterrupted(t *testing.T) {
	db := mysqltest.Database(t)
	installOriginalVersionOne(t, db)
	seedCompleteUserGraph(t, db)

	blocker, err := db.Conn(context.Background())
	if err != nil {
		t.Fatalf("get metadata-lock connection: %v", err)
	}
	defer blocker.Close()
	if _, err := blocker.ExecContext(context.Background(), "LOCK TABLES sessions READ"); err != nil {
		t.Fatalf("lock sessions table: %v", err)
	}
	locked := true
	defer func() {
		if locked {
			_, _ = blocker.ExecContext(context.Background(), "UNLOCK TABLES")
		}
	}()

	applyCtx, cancelApply := context.WithCancel(context.Background())
	applyResult := make(chan error, 1)
	go func() {
		applyResult <- migrations.Apply(applyCtx, db)
	}()

	state, nextStatement, checksum, err := waitForMigrationProgress(db, 2, 5*time.Second)
	if err != nil {
		cancelApply()
		_, _ = blocker.ExecContext(context.Background(), "UNLOCK TABLES")
		locked = false
		<-applyResult
		t.Fatalf("wait for committed migration statement: %v", err)
	}
	if state != "applying" || nextStatement != 2 {
		t.Errorf("migration progress = %s/%d, want applying/2", state, nextStatement)
	}

	var deleteRule string
	if err := db.QueryRow(`
		SELECT delete_rule
		FROM information_schema.referential_constraints
		WHERE constraint_schema = DATABASE()
		  AND constraint_name = 'fk_training_events_device'`).Scan(&deleteRule); err != nil {
		t.Fatalf("query committed training-events FK: %v", err)
	}
	if deleteRule != "CASCADE" {
		t.Errorf("training-events FK after checkpoint 2 = %q, want CASCADE", deleteRule)
	}

	cancelApply()
	var interruptedErr error
	select {
	case interruptedErr = <-applyResult:
	case <-time.After(5 * time.Second):
		t.Fatal("Apply did not stop after context cancellation")
	}
	if interruptedErr == nil {
		t.Fatal("interrupted Apply returned nil")
	}
	if _, err := blocker.ExecContext(context.Background(), "UNLOCK TABLES"); err != nil {
		t.Fatalf("unlock sessions table: %v", err)
	}
	locked = false

	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("resume Apply: %v", err)
	}
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("repeat resumed Apply: %v", err)
	}

	var finalState string
	var finalNextStatement int
	var finalChecksum []byte
	if err := db.QueryRow(`
		SELECT state, next_statement, checksum
		FROM schema_migrations
		WHERE version = 2`).Scan(&finalState, &finalNextStatement, &finalChecksum); err != nil {
		t.Fatalf("read completed migration progress: %v", err)
	}
	if finalState != "applied" || finalNextStatement != 7 {
		t.Errorf("completed migration progress = %s/%d, want applied/7", finalState, finalNextStatement)
	}
	if !bytes.Equal(finalChecksum, checksum) {
		t.Errorf("migration checksum changed across retry: before %x, after %x", checksum, finalChecksum)
	}

	for tableName, wantCount := range map[string]int{
		"users":           1,
		"devices":         1,
		"sessions":        1,
		"refresh_tokens":  1,
		"training_events": 1,
	} {
		var gotCount int
		query := fmt.Sprintf("SELECT COUNT(*) FROM `%s`", tableName)
		if err := db.QueryRow(query).Scan(&gotCount); err != nil {
			t.Fatalf("count %s after resumed migration: %v", tableName, err)
		}
		if gotCount != wantCount {
			t.Errorf("%s count after resumed migration = %d, want %d", tableName, gotCount, wantCount)
		}
	}
}

func migratedDatabase(t *testing.T) *sql.DB {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("Apply() error = %v", err)
	}
	return db
}

func tableForIndex(indexName string) string {
	switch {
	case strings.Contains(indexName, "auth_identities"):
		return "auth_identities"
	case strings.Contains(indexName, "devices"):
		return "devices"
	case strings.Contains(indexName, "refresh_tokens"):
		return "refresh_tokens"
	case strings.Contains(indexName, "training_events"):
		return "training_events"
	case strings.Contains(indexName, "idempotency"):
		return "idempotency_records"
	case strings.Contains(indexName, "email_challenges"):
		return "email_challenges"
	default:
		panic(fmt.Sprintf("no table for index %q", indexName))
	}
}

func indexColumns(t *testing.T, db *sql.DB, tableName, indexName string) ([]string, bool) {
	t.Helper()
	rows, err := db.Query(`
		SELECT column_name, non_unique
		FROM information_schema.statistics
		WHERE table_schema = DATABASE()
		  AND table_name = ?
		  AND index_name = ?
		ORDER BY seq_in_index`, tableName, indexName)
	if err != nil {
		t.Fatalf("query index %s: %v", indexName, err)
	}
	defer rows.Close()

	var columns []string
	var nonUnique bool
	for rows.Next() {
		var column string
		if err := rows.Scan(&column, &nonUnique); err != nil {
			t.Fatalf("scan index %s: %v", indexName, err)
		}
		columns = append(columns, column)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate index %s: %v", indexName, err)
	}
	return columns, nonUnique
}

const (
	testUserID         = "00000000-0000-0000-0000-000000000101"
	secondUserID       = "00000000-0000-0000-0000-000000000102"
	testIdentityID     = "00000000-0000-0000-0000-000000000201"
	testChallengeID    = "00000000-0000-0000-0000-000000000301"
	testDeviceID       = "00000000-0000-0000-0000-000000000401"
	testInstallationID = "00000000-0000-0000-0000-000000000402"
	testSessionID      = "00000000-0000-0000-0000-000000000501"
	testTokenFamilyID  = "00000000-0000-0000-0000-000000000502"
	testRefreshID      = "00000000-0000-0000-0000-000000000601"
	testEventID        = "00000000-0000-0000-0000-000000000701"
)

func seedCompleteUserGraph(t *testing.T, db *sql.DB) {
	t.Helper()
	mustExec(t, db, "INSERT INTO users (id) VALUES (UUID_TO_BIN(?))", testUserID)
	mustExec(t, db, `
		INSERT INTO auth_identities (id, user_id, provider, subject)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), 'email', 'user@example.test')`,
		testIdentityID, testUserID)
	mustExec(t, db, `
		INSERT INTO password_credentials (user_id, password_hash, password_changed_at)
		VALUES (UUID_TO_BIN(?), '$argon2id$test', NOW(3))`,
		testUserID)
	mustExec(t, db, `
		INSERT INTO email_challenges (id, user_id, token_hash, purpose, expires_at)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('33', 32)), 'verifyEmail', NOW(3) + INTERVAL 10 MINUTE)`,
		testChallengeID, testUserID)
	mustExec(t, db, `
		INSERT INTO devices (id, user_id, installation_id, display_name, platform, app_version)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), 'iPhone', 'iOS', '1.0')`,
		testDeviceID, testUserID, testInstallationID)
	mustExec(t, db, `
		INSERT INTO sessions (
			id, user_id, device_id, token_family_id, current_access_token_hash,
			access_expires_at, recent_authenticated_at, last_active_at
		) VALUES (
			UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('44', 32)),
			NOW(3) + INTERVAL 15 MINUTE, NOW(3), NOW(3)
		)`,
		testSessionID, testUserID, testDeviceID, testTokenFamilyID)
	mustExec(t, db, `
		INSERT INTO refresh_tokens (id, user_id, session_id, token_hash, expires_at)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), UNHEX(REPEAT('55', 32)), NOW(3) + INTERVAL 30 DAY)`,
		testRefreshID, testUserID, testSessionID)
	mustExec(t, db, "INSERT INTO user_sync_sequences (user_id) VALUES (UUID_TO_BIN(?))", testUserID)
	mustExec(t, db, `
		INSERT INTO training_events (user_id, event_id, device_id, server_sequence, occurred_at, payload)
		VALUES (UUID_TO_BIN(?), UUID_TO_BIN(?), UUID_TO_BIN(?), 1, NOW(3), JSON_OBJECT('schemaVersion', 1))`,
		testUserID, testEventID, testDeviceID)
	mustExec(t, db, `
		INSERT INTO idempotency_records (user_id, idempotency_key, request_hash, response_json)
		VALUES (UUID_TO_BIN(?), 'account-delete-test', UNHEX(REPEAT('66', 32)), JSON_OBJECT('ok', true))`,
		testUserID)
}

func mustExec(t *testing.T, db *sql.DB, query string, args ...any) {
	t.Helper()
	if _, err := db.Exec(query, args...); err != nil {
		t.Fatalf("exec fixture query: %v\n%s", err, query)
	}
}

func mysqlVersion(t *testing.T, version string) (int, int) {
	t.Helper()
	matches := regexp.MustCompile(`^([0-9]+)\.([0-9]+)`).FindStringSubmatch(version)
	if len(matches) != 3 {
		t.Fatalf("parse MySQL version %q", version)
	}
	major, err := strconv.Atoi(matches[1])
	if err != nil {
		t.Fatalf("parse MySQL major version %q: %v", version, err)
	}
	minor, err := strconv.Atoi(matches[2])
	if err != nil {
		t.Fatalf("parse MySQL minor version %q: %v", version, err)
	}
	return major, minor
}

func runDatabaseProofProbe(t *testing.T, overrides map[string]string) (string, error) {
	return runDatabaseProofProbeMode(t, "verify", overrides)
}

func runDatabaseProofProbeMode(t *testing.T, mode string, overrides map[string]string) (string, error) {
	t.Helper()
	command := exec.Command(
		os.Args[0],
		"-test.run=^TestMySQLTestDatabaseProofProbe$",
		"-test.count=1",
		"-test.v",
	)
	command.Env = append(filteredEnvironment(
		os.Environ(),
		"POKER_COACH_MYSQL_TEST_DATADIR",
		"POKER_COACH_MYSQL_TEST_SERVER_UUID",
	), "POKER_COACH_MYSQL_PROOF_PROBE="+mode)
	for key, value := range overrides {
		command.Env = append(command.Env, key+"="+value)
	}
	output, err := command.CombinedOutput()
	return string(output), err
}

func installOriginalVersionOne(t *testing.T, db *sql.DB) {
	t.Helper()
	const originalChecksum = "757b0e6e59e6d58979530268cbda204d133ead45d6f58c1d369017a4574220ad"
	contents, err := os.ReadFile("testdata/0001_m1b_initial_9569ffc.sql")
	if err != nil {
		t.Fatalf("read original version 1 fixture: %v", err)
	}
	checksum := sha256.Sum256(contents)
	if got := hex.EncodeToString(checksum[:]); got != originalChecksum {
		t.Fatalf("original version 1 fixture checksum = %s, want %s", got, originalChecksum)
	}

	mustExec(t, db, `
		CREATE TABLE schema_migrations (
			version BIGINT UNSIGNED NOT NULL,
			name VARCHAR(255) NOT NULL,
			checksum BINARY(32) NOT NULL,
			applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
			PRIMARY KEY (version)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`)
	for _, statement := range strings.Split(string(contents), ";") {
		if statement = strings.TrimSpace(statement); statement != "" {
			mustExec(t, db, statement)
		}
	}
	mustExec(t, db, `
		INSERT INTO schema_migrations (version, name, checksum)
		VALUES (1, '0001_m1b_initial.sql', UNHEX(?))`,
		originalChecksum)
}

func waitForMigrationProgress(db *sql.DB, minimumNext int, timeout time.Duration) (string, int, []byte, error) {
	deadline := time.Now().Add(timeout)
	for {
		var state string
		var nextStatement int
		var checksum []byte
		err := db.QueryRow(`
			SELECT state, next_statement, checksum
			FROM schema_migrations
			WHERE version = 2`).Scan(&state, &nextStatement, &checksum)
		var mysqlErr *mysql.MySQLError
		switch {
		case err == nil && nextStatement >= minimumNext:
			return state, nextStatement, checksum, nil
		case errors.As(err, &mysqlErr) && mysqlErr.Number == 1054:
			// Apply may still be extending a legacy schema_migrations table.
			time.Sleep(10 * time.Millisecond)
		case err != nil && !errors.Is(err, sql.ErrNoRows):
			return "", 0, nil, err
		case time.Now().After(deadline):
			return "", 0, nil, fmt.Errorf("timed out waiting for next_statement >= %d", minimumNext)
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}
}

func filteredEnvironment(environment []string, keys ...string) []string {
	filtered := make([]string, 0, len(environment))
	for _, item := range environment {
		remove := false
		for _, key := range keys {
			if strings.HasPrefix(item, key+"=") {
				remove = true
				break
			}
		}
		if !remove {
			filtered = append(filtered, item)
		}
	}
	return filtered
}
