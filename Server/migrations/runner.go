package migrations

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/go-sql-driver/mysql"
)

const createMigrationsTable = `
CREATE TABLE IF NOT EXISTS schema_migrations (
    version BIGINT UNSIGNED NOT NULL,
    name VARCHAR(255) NOT NULL,
    checksum BINARY(32) NOT NULL,
    applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`

type migration struct {
	version  uint64
	name     string
	contents []byte
	checksum [sha256.Size]byte
}

func Apply(ctx context.Context, db *sql.DB) error {
	conn, err := db.Conn(ctx)
	if err != nil {
		return fmt.Errorf("get migration connection: %w", err)
	}
	defer conn.Close()

	var locked int
	if err := conn.QueryRowContext(ctx, "SELECT GET_LOCK(?, 30)", "poker_coach_schema_migrations").Scan(&locked); err != nil {
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	if locked != 1 {
		return errors.New("acquire migration lock: timed out")
	}
	defer func() {
		_, _ = conn.ExecContext(context.Background(), "SELECT RELEASE_LOCK(?)", "poker_coach_schema_migrations")
	}()

	if _, err := conn.ExecContext(ctx, createMigrationsTable); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	pending, err := loadMigrations()
	if err != nil {
		return err
	}
	for _, item := range pending {
		applied, err := migrationApplied(ctx, conn, item)
		if err != nil {
			return err
		}
		if applied {
			continue
		}
		for _, statement := range splitStatements(string(item.contents)) {
			if _, err := conn.ExecContext(ctx, statement); err != nil {
				return fmt.Errorf("apply migration %04d (%s): %w", item.version, item.name, err)
			}
		}
		if _, err := conn.ExecContext(ctx,
			"INSERT INTO schema_migrations (version, name, checksum) VALUES (?, ?, ?)",
			item.version, item.name, item.checksum[:],
		); err != nil {
			return fmt.Errorf("record migration %04d (%s): %w", item.version, item.name, err)
		}
	}
	return nil
}

func CurrentVersion(ctx context.Context, db *sql.DB) (uint64, error) {
	var version uint64
	err := db.QueryRowContext(ctx, "SELECT COALESCE(MAX(version), 0) FROM schema_migrations").Scan(&version)
	if err == nil {
		return version, nil
	}

	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) && mysqlErr.Number == 1146 {
		return 0, nil
	}
	return 0, fmt.Errorf("read schema version: %w", err)
}

func loadMigrations() ([]migration, error) {
	entries, err := fs.ReadDir(migrationFiles, ".")
	if err != nil {
		return nil, fmt.Errorf("read embedded migrations: %w", err)
	}

	items := make([]migration, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".sql" {
			continue
		}
		versionText, _, ok := strings.Cut(entry.Name(), "_")
		if !ok {
			return nil, fmt.Errorf("invalid migration filename %q", entry.Name())
		}
		version, err := strconv.ParseUint(versionText, 10, 64)
		if err != nil || version == 0 {
			return nil, fmt.Errorf("invalid migration version in %q", entry.Name())
		}
		contents, err := migrationFiles.ReadFile(entry.Name())
		if err != nil {
			return nil, fmt.Errorf("read migration %q: %w", entry.Name(), err)
		}
		items = append(items, migration{
			version:  version,
			name:     entry.Name(),
			contents: contents,
			checksum: sha256.Sum256(contents),
		})
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].version < items[j].version
	})
	for index := 1; index < len(items); index++ {
		if items[index-1].version == items[index].version {
			return nil, fmt.Errorf("duplicate migration version %d", items[index].version)
		}
	}
	return items, nil
}

func migrationApplied(ctx context.Context, conn *sql.Conn, item migration) (bool, error) {
	var storedChecksum []byte
	err := conn.QueryRowContext(ctx,
		"SELECT checksum FROM schema_migrations WHERE version = ?",
		item.version,
	).Scan(&storedChecksum)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("check migration %04d: %w", item.version, err)
	}
	if !bytes.Equal(storedChecksum, item.checksum[:]) {
		return false, fmt.Errorf("migration %04d checksum does not match applied schema", item.version)
	}
	return true, nil
}

func splitStatements(contents string) []string {
	parts := strings.Split(contents, ";")
	statements := make([]string, 0, len(parts))
	for _, part := range parts {
		if statement := strings.TrimSpace(part); statement != "" {
			statements = append(statements, statement)
		}
	}
	return statements
}
