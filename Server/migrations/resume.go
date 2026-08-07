package migrations

import (
	"context"
	"database/sql"
	"fmt"
)

func prepareMigration(ctx context.Context, conn *sql.Conn, item migration) error {
	if item.version != 2 {
		return nil
	}
	result, err := conn.ExecContext(ctx, `
		DELETE refresh_tokens
		FROM refresh_tokens
		INNER JOIN sessions ON sessions.id = refresh_tokens.session_id
		WHERE refresh_tokens.user_id <> sessions.user_id`)
	if err != nil {
		return fmt.Errorf("remove cross-user refresh tokens before migration 0002: %w", err)
	}
	if _, err := result.RowsAffected(); err != nil {
		return fmt.Errorf("read cross-user refresh cleanup result: %w", err)
	}
	return nil
}

func migrationStatementAlreadyApplied(
	ctx context.Context,
	conn *sql.Conn,
	item migration,
	statement int,
) (bool, error) {
	if item.version != 2 {
		return false, nil
	}
	switch statement {
	case 0:
		foreignKey, err := readForeignKey(ctx, conn, "training_events", "fk_training_events_device")
		if err != nil {
			return false, err
		}
		return !foreignKey.exists || foreignKey.deleteRule == "CASCADE", nil
	case 1:
		foreignKey, err := readForeignKey(ctx, conn, "training_events", "fk_training_events_device")
		if err != nil {
			return false, err
		}
		return foreignKey.matches(
			[]string{"user_id", "device_id"},
			"devices",
			[]string{"user_id", "id"},
			"CASCADE",
		), nil
	case 2:
		return indexMatches(
			ctx,
			conn,
			"sessions",
			"uq_sessions_user_session_id",
			[]string{"user_id", "id"},
			true,
		)
	case 3:
		foreignKey, err := readForeignKey(ctx, conn, "refresh_tokens", "fk_refresh_tokens_session")
		if err != nil {
			return false, err
		}
		return !foreignKey.exists || foreignKey.matches(
			[]string{"user_id", "session_id"},
			"sessions",
			[]string{"user_id", "id"},
			"CASCADE",
		), nil
	case 4:
		return indexMatches(
			ctx,
			conn,
			"refresh_tokens",
			"idx_refresh_tokens_user_session",
			[]string{"user_id", "session_id"},
			false,
		)
	case 5:
		foreignKey, err := readForeignKey(ctx, conn, "refresh_tokens", "fk_refresh_tokens_session")
		if err != nil {
			return false, err
		}
		return foreignKey.matches(
			[]string{"user_id", "session_id"},
			"sessions",
			[]string{"user_id", "id"},
			"CASCADE",
		), nil
	case 6:
		var defaultValue sql.NullString
		if err := conn.QueryRowContext(ctx, `
			SELECT column_default
			FROM information_schema.columns
			WHERE table_schema = DATABASE()
			  AND table_name = 'user_sync_sequences'
			  AND column_name = 'next_sequence'`).Scan(&defaultValue); err != nil {
			return false, fmt.Errorf("inspect user_sync_sequences.next_sequence default: %w", err)
		}
		return defaultValue.Valid && defaultValue.String == "0", nil
	default:
		return false, fmt.Errorf("migration 0002 has unexpected statement index %d", statement)
	}
}

type foreignKeyDefinition struct {
	exists            bool
	columns           []string
	referencedTable   string
	referencedColumns []string
	deleteRule        string
}

func (definition foreignKeyDefinition) matches(
	columns []string,
	referencedTable string,
	referencedColumns []string,
	deleteRule string,
) bool {
	return definition.exists &&
		equalStrings(definition.columns, columns) &&
		definition.referencedTable == referencedTable &&
		equalStrings(definition.referencedColumns, referencedColumns) &&
		definition.deleteRule == deleteRule
}

func readForeignKey(
	ctx context.Context,
	conn *sql.Conn,
	tableName string,
	constraintName string,
) (foreignKeyDefinition, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT
			kcu.column_name,
			kcu.referenced_table_name,
			kcu.referenced_column_name,
			rc.delete_rule
		FROM information_schema.key_column_usage AS kcu
		INNER JOIN information_schema.referential_constraints AS rc
			ON rc.constraint_schema = kcu.constraint_schema
		   AND rc.table_name = kcu.table_name
		   AND rc.constraint_name = kcu.constraint_name
		WHERE kcu.constraint_schema = DATABASE()
		  AND kcu.table_name = ?
		  AND kcu.constraint_name = ?
		ORDER BY kcu.ordinal_position`,
		tableName,
		constraintName,
	)
	if err != nil {
		return foreignKeyDefinition{}, fmt.Errorf("inspect foreign key %s.%s: %w", tableName, constraintName, err)
	}
	defer rows.Close()

	var definition foreignKeyDefinition
	for rows.Next() {
		var column, referencedTable, referencedColumn, deleteRule string
		if err := rows.Scan(&column, &referencedTable, &referencedColumn, &deleteRule); err != nil {
			return foreignKeyDefinition{}, fmt.Errorf(
				"scan foreign key %s.%s: %w",
				tableName,
				constraintName,
				err,
			)
		}
		definition.exists = true
		definition.columns = append(definition.columns, column)
		definition.referencedColumns = append(definition.referencedColumns, referencedColumn)
		definition.referencedTable = referencedTable
		definition.deleteRule = deleteRule
	}
	if err := rows.Err(); err != nil {
		return foreignKeyDefinition{}, fmt.Errorf(
			"iterate foreign key %s.%s: %w",
			tableName,
			constraintName,
			err,
		)
	}
	return definition, nil
}

func indexMatches(
	ctx context.Context,
	conn *sql.Conn,
	tableName string,
	indexName string,
	columns []string,
	unique bool,
) (bool, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT column_name, non_unique
		FROM information_schema.statistics
		WHERE table_schema = DATABASE()
		  AND table_name = ?
		  AND index_name = ?
		ORDER BY seq_in_index`,
		tableName,
		indexName,
	)
	if err != nil {
		return false, fmt.Errorf("inspect index %s.%s: %w", tableName, indexName, err)
	}
	defer rows.Close()

	var actualColumns []string
	var nonUnique bool
	for rows.Next() {
		var column string
		if err := rows.Scan(&column, &nonUnique); err != nil {
			return false, fmt.Errorf("scan index %s.%s: %w", tableName, indexName, err)
		}
		actualColumns = append(actualColumns, column)
	}
	if err := rows.Err(); err != nil {
		return false, fmt.Errorf("iterate index %s.%s: %w", tableName, indexName, err)
	}
	return equalStrings(actualColumns, columns) && nonUnique == !unique, nil
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
