package mysqlstore

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/sync"
)

type AccountStore struct {
	db *sql.DB
}

func NewAccountStore(db *sql.DB) *AccountStore {
	return &AccountStore{db: db}
}

var _ account.Store = (*AccountStore)(nil)

func (s *AccountStore) PasswordHash(
	ctx context.Context,
	userID string,
) (string, bool, error) {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return "", false, err
	}
	var phc string
	err = s.db.QueryRowContext(ctx,
		"SELECT password_hash FROM password_credentials WHERE user_id = ?",
		owner,
	).Scan(&phc)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup password credential: %w", err)
	}
	return phc, true, nil
}

func (s *AccountStore) HasAppleSubject(
	ctx context.Context,
	userID string,
	subject string,
) (bool, error) {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return false, err
	}
	var count int
	if err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM auth_identities
		WHERE user_id = ? AND provider = 'apple' AND subject = ?`,
		owner, subject,
	).Scan(&count); err != nil {
		return false, fmt.Errorf("check apple subject: %w", err)
	}
	return count > 0, nil
}

func (s *AccountStore) MarkRecentAuthentication(
	ctx context.Context,
	userID string,
	sessionID string,
	at time.Time,
) error {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return err
	}
	target, err := sync.UUIDBytes(sessionID)
	if err != nil {
		return err
	}

	// Scoped by user as well as session id, so a forged session id from
	// another account cannot have its window refreshed.
	result, err := s.db.ExecContext(ctx, `
		UPDATE sessions SET recent_authenticated_at = ?
		WHERE user_id = ? AND id = ? AND revoked_at IS NULL`,
		at, owner, target,
	)
	if err != nil {
		return fmt.Errorf("record reauthentication: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect reauthentication update: %w", err)
	}
	if affected == 0 {
		return &account.Error{Code: account.AuthenticationFailed}
	}
	return nil
}

// Export gathers the caller's own data. Credential material is deliberately
// absent: no password hash, token hash, challenge hash, or throttle state.
func (s *AccountStore) Export(
	ctx context.Context,
	userID string,
) (account.ExportDocument, error) {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return account.ExportDocument{}, err
	}

	var createdAt time.Time
	if err := s.db.QueryRowContext(ctx,
		"SELECT created_at FROM users WHERE id = ?", owner,
	).Scan(&createdAt); err != nil {
		return account.ExportDocument{}, fmt.Errorf("read account: %w", err)
	}

	identities, err := s.exportIdentities(ctx, owner)
	if err != nil {
		return account.ExportDocument{}, err
	}
	devices, err := s.exportDevices(ctx, owner)
	if err != nil {
		return account.ExportDocument{}, err
	}
	events, err := s.exportEvents(ctx, owner)
	if err != nil {
		return account.ExportDocument{}, err
	}

	return account.ExportDocument{
		SchemaVersion: account.ExportSchemaVersion,
		Account: account.ExportAccount{
			UserID:     userID,
			CreatedAt:  createdAt.UTC(),
			Identities: identities,
		},
		Devices: devices,
		Events:  events,
	}, nil
}

func (s *AccountStore) exportIdentities(
	ctx context.Context,
	owner []byte,
) ([]account.ExportIdentity, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT provider, display_email, email_verified FROM auth_identities
		WHERE user_id = ? ORDER BY provider`,
		owner,
	)
	if err != nil {
		return nil, fmt.Errorf("read identities: %w", err)
	}
	defer func() { _ = rows.Close() }()

	identities := []account.ExportIdentity{}
	for rows.Next() {
		var identity account.ExportIdentity
		var email sql.NullString
		if err := rows.Scan(&identity.Provider, &email, &identity.EmailVerified); err != nil {
			return nil, fmt.Errorf("scan identity: %w", err)
		}
		identity.Email = email.String
		identities = append(identities, identity)
	}
	return identities, rows.Err()
}

func (s *AccountStore) exportDevices(
	ctx context.Context,
	owner []byte,
) ([]account.ExportDevice, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT display_name, platform, app_version, created_at, last_seen_at
		FROM devices WHERE user_id = ? ORDER BY created_at`,
		owner,
	)
	if err != nil {
		return nil, fmt.Errorf("read devices: %w", err)
	}
	defer func() { _ = rows.Close() }()

	devices := []account.ExportDevice{}
	for rows.Next() {
		var device account.ExportDevice
		var createdAt, lastSeenAt time.Time
		if err := rows.Scan(
			&device.DisplayName, &device.Platform, &device.AppVersion,
			&createdAt, &lastSeenAt,
		); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		device.CreatedAt = createdAt.UTC()
		device.LastSeenAt = lastSeenAt.UTC()
		devices = append(devices, device)
	}
	return devices, rows.Err()
}

func (s *AccountStore) exportEvents(
	ctx context.Context,
	owner []byte,
) ([]json.RawMessage, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT payload FROM training_events
		WHERE user_id = ? ORDER BY server_sequence`,
		owner,
	)
	if err != nil {
		return nil, fmt.Errorf("read events: %w", err)
	}
	defer func() { _ = rows.Close() }()

	events := []json.RawMessage{}
	for rows.Next() {
		var payload []byte
		if err := rows.Scan(&payload); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		events = append(events, json.RawMessage(payload))
	}
	return events, rows.Err()
}

// deletionOrder removes rows child-first.
//
// InnoDB does happen to cascade a plain DELETE FROM users correctly today, even
// though training_events references devices with ON DELETE RESTRICT: the
// CASCADE from users clears the events before the RESTRICT can bite. That
// resolution order across multiple foreign keys is not a guarantee to build a
// deletion guarantee on, and it hides what the transaction actually removes.
// Listing the statements makes the scope auditable and makes a future table
// with a RESTRICT fail loudly here rather than silently depend on luck.
//
// auth_throttles is deliberately absent. Its rows are keyed by an HMAC of the
// login signal, hold no credential and no readable personal data, and expire on
// their own. Clearing them here would let an attacker reset their own rate
// limit by deleting an account.
var deletionOrder = []string{
	"DELETE FROM training_events WHERE user_id = ?",
	"DELETE FROM refresh_tokens WHERE user_id = ?",
	"DELETE FROM sessions WHERE user_id = ?",
	"DELETE FROM devices WHERE user_id = ?",
	"DELETE FROM idempotency_records WHERE user_id = ?",
	"DELETE FROM user_sync_sequences WHERE user_id = ?",
	"DELETE FROM email_challenges WHERE user_id = ?",
	"DELETE FROM password_credentials WHERE user_id = ?",
	"DELETE FROM auth_identities WHERE user_id = ?",
	"DELETE FROM users WHERE id = ?",
}

func (s *AccountStore) Delete(ctx context.Context, userID string) (err error) {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return err
	}

	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin account deletion: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	for _, statement := range deletionOrder {
		if _, err = tx.ExecContext(ctx, statement, owner); err != nil {
			return fmt.Errorf("account deletion step %q: %w", statement, err)
		}
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit account deletion: %w", err)
	}
	return nil
}
