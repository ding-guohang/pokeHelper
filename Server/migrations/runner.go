package migrations

import (
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
)

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
	if err := ensureMigrationMetadata(ctx, conn); err != nil {
		return err
	}

	pending, err := loadMigrations()
	if err != nil {
		return err
	}
	for _, item := range pending {
		progress, err := readMigrationProgress(ctx, conn, item)
		if err != nil {
			return err
		}
		if progress.exists && progress.state == "applied" {
			continue
		}
		if !progress.exists {
			if _, err := conn.ExecContext(ctx, `
				INSERT INTO schema_migrations (version, name, checksum, state, next_statement)
				VALUES (?, ?, ?, 'applying', 0)`,
				item.version, item.name, item.checksum[:],
			); err != nil {
				return fmt.Errorf("start migration %04d (%s): %w", item.version, item.name, err)
			}
			progress = migrationProgress{
				exists:        true,
				state:         "applying",
				nextStatement: 0,
				checksum:      item.checksum[:],
			}
		}
		if progress.state != "applying" {
			return fmt.Errorf("migration %04d has invalid state %q", item.version, progress.state)
		}
		if err := prepareMigration(ctx, conn, item); err != nil {
			return err
		}

		statements := splitStatements(string(item.contents))
		if progress.nextStatement < 0 || progress.nextStatement > len(statements) {
			return fmt.Errorf(
				"migration %04d next statement %d exceeds statement count %d",
				item.version,
				progress.nextStatement,
				len(statements),
			)
		}
		for index := progress.nextStatement; index < len(statements); index++ {
			alreadyApplied, err := migrationStatementAlreadyApplied(ctx, conn, item, index)
			if err != nil {
				return err
			}
			if !alreadyApplied {
				if _, err := conn.ExecContext(ctx, statements[index]); err != nil {
					return fmt.Errorf(
						"apply migration %04d statement %d (%s): %w",
						item.version,
						index,
						item.name,
						err,
					)
				}
			}
			if err := checkpointMigration(ctx, conn, item.version, index); err != nil {
				return err
			}
		}
		result, err := conn.ExecContext(ctx, `
			UPDATE schema_migrations
			SET state = 'applied', next_statement = ?, applied_at = CURRENT_TIMESTAMP(3)
			WHERE version = ? AND state = 'applying'`,
			len(statements), item.version,
		)
		if err != nil {
			return fmt.Errorf("complete migration %04d (%s): %w", item.version, item.name, err)
		}
		updated, err := result.RowsAffected()
		if err != nil {
			return fmt.Errorf("read migration %04d completion result: %w", item.version, err)
		}
		if updated != 1 {
			return fmt.Errorf("complete migration %04d updated %d rows, want 1", item.version, updated)
		}
	}
	return nil
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
