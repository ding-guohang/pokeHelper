package migrations

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/go-sql-driver/mysql"
)

const createMigrationsTable = `
CREATE TABLE IF NOT EXISTS schema_migrations (
    version BIGINT UNSIGNED NOT NULL,
    name VARCHAR(255) NOT NULL,
    checksum BINARY(32) NOT NULL,
    state VARCHAR(16) NOT NULL DEFAULT 'applied',
    next_statement INT UNSIGNED NOT NULL DEFAULT 0,
    applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`

type migrationProgress struct {
	exists        bool
	state         string
	nextStatement int
	checksum      []byte
}

func CurrentVersion(ctx context.Context, db *sql.DB) (uint64, error) {
	var version uint64
	err := db.QueryRowContext(ctx,
		"SELECT COALESCE(MAX(version), 0) FROM schema_migrations WHERE state = 'applied'",
	).Scan(&version)
	if err == nil {
		return version, nil
	}

	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) && mysqlErr.Number == 1146 {
		return 0, nil
	}
	if errors.As(err, &mysqlErr) && mysqlErr.Number == 1054 {
		if err := db.QueryRowContext(ctx,
			"SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
		).Scan(&version); err != nil {
			return 0, fmt.Errorf("read legacy schema version: %w", err)
		}
		return version, nil
	}
	return 0, fmt.Errorf("read schema version: %w", err)
}

func readMigrationProgress(ctx context.Context, conn *sql.Conn, item migration) (migrationProgress, error) {
	var progress migrationProgress
	err := conn.QueryRowContext(ctx,
		"SELECT state, next_statement, checksum FROM schema_migrations WHERE version = ?",
		item.version,
	).Scan(&progress.state, &progress.nextStatement, &progress.checksum)
	if errors.Is(err, sql.ErrNoRows) {
		return migrationProgress{}, nil
	}
	if err != nil {
		return migrationProgress{}, fmt.Errorf("check migration %04d: %w", item.version, err)
	}
	progress.exists = true
	if !bytes.Equal(progress.checksum, item.checksum[:]) {
		return migrationProgress{}, fmt.Errorf("migration %04d checksum does not match applied schema", item.version)
	}
	return progress, nil
}

func ensureMigrationMetadata(ctx context.Context, conn *sql.Conn) error {
	columns := []struct {
		name       string
		definition string
	}{
		{name: "state", definition: "VARCHAR(16) NOT NULL DEFAULT 'applied'"},
		{name: "next_statement", definition: "INT UNSIGNED NOT NULL DEFAULT 0"},
	}
	for _, column := range columns {
		var exists int
		if err := conn.QueryRowContext(ctx, `
			SELECT EXISTS (
				SELECT 1
				FROM information_schema.columns
				WHERE table_schema = DATABASE()
				  AND table_name = 'schema_migrations'
				  AND column_name = ?
			)`,
			column.name,
		).Scan(&exists); err != nil {
			return fmt.Errorf("check schema_migrations.%s: %w", column.name, err)
		}
		if exists == 1 {
			continue
		}
		statement := fmt.Sprintf(
			"ALTER TABLE schema_migrations ADD COLUMN `%s` %s",
			column.name,
			column.definition,
		)
		if _, err := conn.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("add schema_migrations.%s: %w", column.name, err)
		}
	}
	return nil
}

func checkpointMigration(ctx context.Context, conn *sql.Conn, version uint64, statement int) error {
	result, err := conn.ExecContext(ctx, `
		UPDATE schema_migrations
		SET next_statement = ?
		WHERE version = ? AND state = 'applying' AND next_statement = ?`,
		statement+1, version, statement,
	)
	if err != nil {
		return fmt.Errorf("checkpoint migration %04d statement %d: %w", version, statement, err)
	}
	updated, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read migration %04d checkpoint result: %w", version, err)
	}
	if updated != 1 {
		return fmt.Errorf(
			"checkpoint migration %04d statement %d updated %d rows, want 1",
			version,
			statement,
			updated,
		)
	}
	return nil
}
