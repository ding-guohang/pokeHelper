//go:build integration

package mysqltest

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-sql-driver/mysql"

	"porkhelper/server/internal/mysqlstore"
)

func Database(t testing.TB) *sql.DB {
	t.Helper()
	if os.Getenv("POKER_COACH_ENV") != "test" {
		t.Fatal("mysqltest requires POKER_COACH_ENV=test")
	}

	baseDSN := os.Getenv("POKER_COACH_MYSQL_DSN")
	if baseDSN == "" {
		t.Fatal("mysqltest requires POKER_COACH_MYSQL_DSN")
	}
	baseConfig, err := mysql.ParseDSN(baseDSN)
	if err != nil {
		t.Fatalf("parse POKER_COACH_MYSQL_DSN: %v", err)
	}
	if baseConfig.User == "" || baseConfig.User == "root" {
		t.Fatalf("mysqltest refuses privileged MySQL user %q", baseConfig.User)
	}
	if baseConfig.Net != "tcp" || !strings.HasPrefix(baseConfig.Addr, "127.0.0.1:") {
		t.Fatalf("mysqltest requires loopback TCP DSN, got %s(%s)", baseConfig.Net, baseConfig.Addr)
	}

	expectedDatadir := os.Getenv("POKER_COACH_MYSQL_TEST_DATADIR")
	expectedServerUUID := os.Getenv("POKER_COACH_MYSQL_TEST_SERVER_UUID")
	if expectedDatadir == "" || expectedServerUUID == "" {
		t.Fatal("mysqltest requires temporary MySQL server proof")
	}

	adminConfig := baseConfig.Clone()
	adminConfig.DBName = ""
	adminDB, err := mysqlstore.Open(context.Background(), adminConfig.FormatDSN())
	if err != nil {
		t.Fatalf("open MySQL server: %v", err)
	}
	t.Cleanup(func() { _ = adminDB.Close() })

	if err := verifyTemporaryServer(adminDB, expectedDatadir, expectedServerUUID); err != nil {
		t.Fatal(err)
	}

	schemaName := "poker_coach_test_" + randomHex(t, 8)
	if _, err := adminDB.Exec("CREATE DATABASE `" + schemaName + "` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"); err != nil {
		t.Fatalf("create isolated schema: %v", err)
	}
	t.Cleanup(func() {
		expectedDatadir := os.Getenv("POKER_COACH_MYSQL_TEST_DATADIR")
		expectedServerUUID := os.Getenv("POKER_COACH_MYSQL_TEST_SERVER_UUID")
		if expectedDatadir == "" || expectedServerUUID == "" {
			t.Errorf("mysqltest refusing to drop isolated schema: temporary MySQL server proof is missing")
			return
		}
		if err := verifyTemporaryServer(adminDB, expectedDatadir, expectedServerUUID); err != nil {
			t.Errorf("mysqltest refusing to drop isolated schema: %v", err)
			return
		}
		if _, err := adminDB.Exec("DROP DATABASE `" + schemaName + "`"); err != nil {
			t.Errorf("drop isolated schema: %v", err)
		}
	})

	testConfig := baseConfig.Clone()
	testConfig.DBName = schemaName
	db, err := mysqlstore.Open(context.Background(), testConfig.FormatDSN())
	if err != nil {
		t.Fatalf("open isolated schema: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func verifyTemporaryServer(db *sql.DB, expectedDatadir, expectedServerUUID string) error {
	var actualDatadir, actualServerUUID, version string
	if err := db.QueryRow("SELECT @@datadir, @@server_uuid, VERSION()").Scan(
		&actualDatadir,
		&actualServerUUID,
		&version,
	); err != nil {
		return fmt.Errorf("mysqltest query temporary MySQL server proof: %w", err)
	}

	expectedPath, err := canonicalPath(expectedDatadir)
	if err != nil {
		return fmt.Errorf("mysqltest canonicalize expected datadir: %w", err)
	}
	actualPath, err := canonicalPath(actualDatadir)
	if err != nil {
		return fmt.Errorf("mysqltest canonicalize actual datadir: %w", err)
	}
	if actualPath != expectedPath || actualServerUUID != expectedServerUUID {
		return fmt.Errorf(
			"mysqltest temporary MySQL server proof mismatch: got datadir %q server UUID %q, want datadir %q server UUID %q",
			actualPath,
			actualServerUUID,
			expectedPath,
			expectedServerUUID,
		)
	}

	var major, minor int
	if count, err := fmt.Sscanf(version, "%d.%d", &major, &minor); err != nil || count != 2 {
		return fmt.Errorf("mysqltest parse MySQL version %q", version)
	}
	if major < 8 || (major == 8 && minor < 4) {
		return fmt.Errorf("mysqltest requires MySQL >= 8.4, got %q", version)
	}
	return nil
}

func canonicalPath(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	return filepath.Clean(resolved), nil
}

func randomHex(t testing.TB, byteCount int) string {
	t.Helper()
	value := make([]byte, byteCount)
	if _, err := rand.Read(value); err != nil {
		t.Fatalf("random schema suffix: %v", err)
	}
	return hex.EncodeToString(value)
}
