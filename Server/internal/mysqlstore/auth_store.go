package mysqlstore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"

	"porkhelper/server/internal/auth"
)

type AuthStore struct {
	db *sql.DB
}

func NewAuthStore(db *sql.DB) *AuthStore {
	return &AuthStore{db: db}
}

func (s *AuthStore) CreateRegistration(
	ctx context.Context,
	registration auth.Registration,
) (created bool, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return false, fmt.Errorf("begin registration: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.ExecContext(ctx,
		"INSERT INTO users (id) VALUES (?)",
		registration.UserID[:],
	); err != nil {
		return false, fmt.Errorf("insert user: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO auth_identities (
			id, user_id, provider, subject, canonical_email, display_email, email_verified
		) VALUES (?, ?, 'email', ?, ?, ?, FALSE)`,
		registration.IdentityID[:],
		registration.UserID[:],
		registration.Email.Canonical,
		registration.Email.Canonical,
		registration.Email.Display,
	); err != nil {
		if isOccupiedEmail(err) {
			_ = tx.Rollback()
			return false, nil
		}
		return false, fmt.Errorf("insert email identity: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO password_credentials (user_id, password_hash, password_changed_at)
		VALUES (?, ?, ?)`,
		registration.UserID[:],
		registration.PasswordPHC,
		registration.PasswordAt,
	); err != nil {
		return false, fmt.Errorf("insert password credential: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO email_challenges (
			id, user_id, token_hash, purpose, attempt_count, expires_at
		) VALUES (?, ?, ?, ?, 0, ?)`,
		registration.ChallengeID[:],
		registration.UserID[:],
		registration.ChallengeHash[:],
		registration.Purpose,
		registration.ExpiresAt,
	); err != nil {
		return false, fmt.Errorf("insert email challenge: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO user_sync_sequences (user_id, next_sequence) VALUES (?, 0)`,
		registration.UserID[:],
	); err != nil {
		return false, fmt.Errorf("insert user sync sequence: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return false, fmt.Errorf("commit registration: %w", err)
	}
	return true, nil
}

func (s *AuthStore) ConsumeEmailChallenge(
	ctx context.Context,
	tokenHash [32]byte,
	now time.Time,
) (err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin email verification: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID []byte
	var expiresAt time.Time
	var consumedAt sql.NullTime
	err = tx.QueryRowContext(ctx, `
		SELECT user_id, expires_at, consumed_at
		FROM email_challenges
		WHERE token_hash = ? AND purpose = 'verifyEmail'
		FOR UPDATE`,
		tokenHash[:],
	).Scan(&userID, &expiresAt, &consumedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return &auth.Error{Code: auth.ChallengeInvalid}
	}
	if err != nil {
		return fmt.Errorf("lock email challenge: %w", err)
	}

	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges
		SET attempt_count = attempt_count + 1
		WHERE token_hash = ?`,
		tokenHash[:],
	); err != nil {
		return fmt.Errorf("increment email challenge attempt: %w", err)
	}
	if consumedAt.Valid || !now.Before(expiresAt) {
		if err = tx.Commit(); err != nil {
			return fmt.Errorf("commit invalid email challenge attempt: %w", err)
		}
		return &auth.Error{Code: auth.ChallengeInvalid}
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges SET consumed_at = ? WHERE token_hash = ?`,
		now,
		tokenHash[:],
	); err != nil {
		return fmt.Errorf("consume email challenge: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE auth_identities
		SET email_verified = TRUE
		WHERE user_id = ? AND provider = 'email'`,
		userID,
	); err != nil {
		return fmt.Errorf("verify email identity: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit email verification: %w", err)
	}
	return nil
}

func isOccupiedEmail(err error) bool {
	var mysqlError *mysql.MySQLError
	return errors.As(err, &mysqlError) &&
		mysqlError.Number == 1062 &&
		strings.Contains(mysqlError.Message, "uq_auth_identities_provider_subject")
}
