//go:build integration

package mysqltest

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"os"
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

	schemaName := "poker_coach_test_" + randomHex(t, 8)
	adminConfig := baseConfig.Clone()
	adminConfig.DBName = ""
	adminDB, err := mysqlstore.Open(context.Background(), adminConfig.FormatDSN())
	if err != nil {
		t.Fatalf("open MySQL server: %v", err)
	}
	t.Cleanup(func() { _ = adminDB.Close() })

	if _, err := adminDB.Exec("CREATE DATABASE `" + schemaName + "` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"); err != nil {
		t.Fatalf("create isolated schema: %v", err)
	}
	t.Cleanup(func() {
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

func randomHex(t testing.TB, byteCount int) string {
	t.Helper()
	value := make([]byte, byteCount)
	if _, err := rand.Read(value); err != nil {
		t.Fatalf("random schema suffix: %v", err)
	}
	return hex.EncodeToString(value)
}
