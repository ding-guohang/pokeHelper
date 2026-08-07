//go:build integration

package migrations_test

import (
	"context"
	"database/sql"
	"fmt"
	"slices"
	"strings"
	"testing"

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
	if after != 1 {
		t.Errorf("CurrentVersion() after Apply = %d, want 1", after)
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
	if count != 1 {
		t.Errorf("schema_migrations count = %d, want 1", count)
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
