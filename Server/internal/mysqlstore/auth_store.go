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

func (s *AuthStore) LookupLoginCredential(
	ctx context.Context,
	canonicalEmail string,
) (auth.LoginCredential, error) {
	var userID []byte
	var credential auth.LoginCredential
	err := s.db.QueryRowContext(ctx, `
		SELECT i.user_id, i.email_verified, p.password_hash
		FROM auth_identities AS i
		INNER JOIN password_credentials AS p ON p.user_id = i.user_id
		WHERE i.provider = 'email' AND i.subject = ?`,
		canonicalEmail,
	).Scan(&userID, &credential.Verified, &credential.PasswordPHC)
	if errors.Is(err, sql.ErrNoRows) {
		return auth.LoginCredential{}, nil
	}
	if err != nil {
		return auth.LoginCredential{}, fmt.Errorf("lookup login credential: %w", err)
	}
	credential.UserID, err = authID(userID)
	if err != nil {
		return auth.LoginCredential{}, err
	}
	credential.Found = true
	return credential, nil
}

func (s *AuthStore) UpgradePasswordCredential(
	ctx context.Context,
	userID auth.ID,
	oldPHC string,
	newPHC string,
	now time.Time,
) error {
	result, err := s.db.ExecContext(ctx, `
		UPDATE password_credentials
		SET password_hash = ?, password_changed_at = ?
		WHERE user_id = ? AND password_hash = ?`,
		newPHC,
		now,
		userID[:],
		oldPHC,
	)
	if err != nil {
		return fmt.Errorf("conditionally upgrade password credential: %w", err)
	}
	updated, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read password credential upgrade result: %w", err)
	}
	if updated > 1 {
		return fmt.Errorf("password credential upgrade changed %d rows, want at most 1", updated)
	}
	return nil
}

func (s *AuthStore) CreatePasswordResetChallenge(
	ctx context.Context,
	canonicalEmail string,
	challenge auth.PasswordResetChallenge,
) (delivery auth.PasswordResetDelivery, created bool, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("begin password reset request: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID []byte
	err = tx.QueryRowContext(ctx, `
		SELECT user_id, display_email
		FROM auth_identities
		WHERE provider = 'email' AND subject = ? AND email_verified = TRUE`,
		canonicalEmail,
	).Scan(&userID, &delivery.DisplayEmail)
	if errors.Is(err, sql.ErrNoRows) {
		if err = tx.Commit(); err != nil {
			return auth.PasswordResetDelivery{}, false, fmt.Errorf("commit hidden reset request: %w", err)
		}
		return auth.PasswordResetDelivery{}, false, nil
	}
	if err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("find reset identity: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges
		SET consumed_at = ?
		WHERE user_id = ?
		  AND purpose = 'resetPassword'
		  AND consumed_at IS NULL`,
		challenge.IssuedAt,
		userID,
	); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("supersede password reset challenges: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO email_challenges (
			id, user_id, token_hash, purpose, attempt_count, expires_at
		) VALUES (?, ?, ?, ?, 0, ?)`,
		challenge.ChallengeID[:],
		userID,
		challenge.TokenHash[:],
		challenge.Purpose,
		challenge.ExpiresAt,
	); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("insert password reset challenge: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("commit password reset request: %w", err)
	}
	return delivery, true, nil
}

// CreateVerificationChallenge mirrors CreatePasswordResetChallenge but targets
// accounts that are not yet verified, so a user who lost the first email can
// ask for another without revealing whether the address exists.
func (s *AuthStore) CreateVerificationChallenge(
	ctx context.Context,
	canonicalEmail string,
	challenge auth.PasswordResetChallenge,
) (delivery auth.PasswordResetDelivery, created bool, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("begin verification resend: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID []byte
	err = tx.QueryRowContext(ctx, `
		SELECT user_id, display_email
		FROM auth_identities
		WHERE provider = 'email' AND subject = ? AND email_verified = FALSE`,
		canonicalEmail,
	).Scan(&userID, &delivery.DisplayEmail)
	if errors.Is(err, sql.ErrNoRows) {
		if err = tx.Commit(); err != nil {
			return auth.PasswordResetDelivery{}, false, fmt.Errorf("commit hidden resend: %w", err)
		}
		return auth.PasswordResetDelivery{}, false, nil
	}
	if err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("find unverified identity: %w", err)
	}

	// Superseding the outstanding challenge keeps exactly one live token, so a
	// resend cannot widen the window by leaving older tokens usable.
	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges
		SET consumed_at = ?
		WHERE user_id = ?
		  AND purpose = 'verifyEmail'
		  AND consumed_at IS NULL`,
		challenge.IssuedAt,
		userID,
	); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("supersede verification challenges: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO email_challenges (
			id, user_id, token_hash, purpose, attempt_count, expires_at
		) VALUES (?, ?, ?, ?, 0, ?)`,
		challenge.ChallengeID[:],
		userID,
		challenge.TokenHash[:],
		challenge.Purpose,
		challenge.ExpiresAt,
	); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("insert verification challenge: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return auth.PasswordResetDelivery{}, false, fmt.Errorf("commit verification resend: %w", err)
	}
	return delivery, true, nil
}

func (s *AuthStore) ReplacePassword(
	ctx context.Context,
	tokenHash [32]byte,
	now time.Time,
	hashPassword func() (string, error),
	revoke func(context.Context, string) error,
) (err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin password reset confirmation: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userIDBytes []byte
	var expiresAt time.Time
	var consumedAt sql.NullTime
	err = tx.QueryRowContext(ctx, `
		SELECT user_id, expires_at, consumed_at
		FROM email_challenges
		WHERE token_hash = ? AND purpose = 'resetPassword'
		FOR UPDATE`,
		tokenHash[:],
	).Scan(&userIDBytes, &expiresAt, &consumedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return &auth.Error{Code: auth.ChallengeInvalid}
	}
	if err != nil {
		return fmt.Errorf("lock password reset challenge: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges
		SET attempt_count = attempt_count + 1
		WHERE token_hash = ?`,
		tokenHash[:],
	); err != nil {
		return fmt.Errorf("increment password reset attempt: %w", err)
	}
	if consumedAt.Valid || !now.Before(expiresAt) {
		if err = tx.Commit(); err != nil {
			return fmt.Errorf("commit invalid password reset attempt: %w", err)
		}
		return &auth.Error{Code: auth.ChallengeInvalid}
	}

	userID, err := authID(userIDBytes)
	if err != nil {
		return err
	}
	passwordPHC, err := hashPassword()
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE password_credentials
		SET password_hash = ?, password_changed_at = ?
		WHERE user_id = ?`,
		passwordPHC,
		now,
		userIDBytes,
	); err != nil {
		return fmt.Errorf("replace password credential: %w", err)
	}
	if _, err = tx.ExecContext(ctx, `
		UPDATE email_challenges
		SET consumed_at = ?
		WHERE token_hash = ?`,
		now,
		tokenHash[:],
	); err != nil {
		return fmt.Errorf("consume password reset challenge: %w", err)
	}
	if err = revoke(ctx, userID.String()); err != nil {
		return fmt.Errorf("revoke sessions after password reset: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit password reset confirmation: %w", err)
	}
	return nil
}

func (s *AuthStore) CheckAuthThrottles(
	ctx context.Context,
	keys auth.ThrottleKeys,
	now time.Time,
) (time.Time, error) {
	zero := [32]byte{}
	pairs := [][2][32]byte{
		{keys.Account, zero},
		{zero, keys.Network},
	}
	var retryAt time.Time
	for _, pair := range pairs {
		var stored sql.NullTime
		err := s.db.QueryRowContext(ctx, `
			SELECT retry_after
			FROM auth_throttles
			WHERE identity_signal_hash = ? AND network_signal_hash = ?`,
			pair[0][:],
			pair[1][:],
		).Scan(&stored)
		if errors.Is(err, sql.ErrNoRows) {
			continue
		}
		if err != nil {
			return time.Time{}, fmt.Errorf("check auth throttle: %w", err)
		}
		if stored.Valid && now.Before(stored.Time) && stored.Time.After(retryAt) {
			retryAt = stored.Time
		}
	}
	return retryAt, nil
}

func (s *AuthStore) ConsumeAuthThrottles(
	ctx context.Context,
	keys auth.ThrottleKeys,
	now time.Time,
	limits auth.ThrottleLimits,
) (retryAt time.Time, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return time.Time{}, fmt.Errorf("begin auth throttle: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	zero := [32]byte{}
	buckets := []struct {
		identity [32]byte
		network  [32]byte
		limit    uint32
	}{
		{identity: keys.Account, network: zero, limit: limits.Account},
		{identity: zero, network: keys.Network, limit: limits.Network},
	}
	for _, bucket := range buckets {
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO auth_throttles (
				identity_signal_hash,
				network_signal_hash,
				window_started_at,
				failure_count
			) VALUES (?, ?, ?, 0)
			ON DUPLICATE KEY UPDATE updated_at = updated_at`,
			bucket.identity[:],
			bucket.network[:],
			now,
		); err != nil {
			return time.Time{}, fmt.Errorf("ensure auth throttle: %w", err)
		}

		var windowStartedAt time.Time
		var failureCount uint32
		var storedRetry sql.NullTime
		if err = tx.QueryRowContext(ctx, `
			SELECT window_started_at, failure_count, retry_after
			FROM auth_throttles
			WHERE identity_signal_hash = ? AND network_signal_hash = ?
			FOR UPDATE`,
			bucket.identity[:],
			bucket.network[:],
		).Scan(&windowStartedAt, &failureCount, &storedRetry); err != nil {
			return time.Time{}, fmt.Errorf("lock auth throttle: %w", err)
		}

		if storedRetry.Valid && now.Before(storedRetry.Time) {
			if storedRetry.Time.After(retryAt) {
				retryAt = storedRetry.Time
			}
			continue
		}

		cutoff := now.Add(-limits.Window)
		if _, err = tx.ExecContext(ctx, `
			DELETE FROM auth_throttle_attempts
			WHERE identity_signal_hash = ?
			  AND network_signal_hash = ?
			  AND attempted_at <= ?`,
			bucket.identity[:],
			bucket.network[:],
			cutoff,
		); err != nil {
			return time.Time{}, fmt.Errorf("delete expired auth throttle attempts: %w", err)
		}

		var recentCount uint64
		var earliest sql.NullTime
		if err = tx.QueryRowContext(ctx, `
			SELECT COALESCE(SUM(attempt_count), 0), MIN(attempted_at)
			FROM auth_throttle_attempts
			WHERE identity_signal_hash = ? AND network_signal_hash = ?`,
			bucket.identity[:],
			bucket.network[:],
		).Scan(&recentCount, &earliest); err != nil {
			return time.Time{}, fmt.Errorf("count recent auth throttle attempts: %w", err)
		}
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO auth_throttle_attempts (
				identity_signal_hash,
				network_signal_hash,
				attempted_at,
				attempt_count
			) VALUES (?, ?, ?, 1)
			ON DUPLICATE KEY UPDATE attempt_count = attempt_count + 1`,
			bucket.identity[:],
			bucket.network[:],
			now,
		); err != nil {
			return time.Time{}, fmt.Errorf("insert auth throttle attempt: %w", err)
		}
		recentCount++
		failureCount = uint32(recentCount)
		windowStartedAt = now
		if earliest.Valid {
			windowStartedAt = earliest.Time
		}
		var nextRetry any
		if failureCount > bucket.limit {
			blockedUntil := now.Add(limits.Block)
			nextRetry = blockedUntil
			if blockedUntil.After(retryAt) {
				retryAt = blockedUntil
			}
		}
		if _, err = tx.ExecContext(ctx, `
			UPDATE auth_throttles
			SET window_started_at = ?, failure_count = ?, retry_after = ?
			WHERE identity_signal_hash = ? AND network_signal_hash = ?`,
			windowStartedAt,
			failureCount,
			nextRetry,
			bucket.identity[:],
			bucket.network[:],
		); err != nil {
			return time.Time{}, fmt.Errorf("update auth throttle: %w", err)
		}
	}
	if err = tx.Commit(); err != nil {
		return time.Time{}, fmt.Errorf("commit auth throttle: %w", err)
	}
	return retryAt, nil
}

func (s *AuthStore) ClearAuthAccountThrottle(
	ctx context.Context,
	accountHash [32]byte,
) error {
	zero := [32]byte{}
	if _, err := s.db.ExecContext(ctx, `
		DELETE FROM auth_throttles
		WHERE identity_signal_hash = ? AND network_signal_hash = ?`,
		accountHash[:],
		zero[:],
	); err != nil {
		return fmt.Errorf("clear account throttle: %w", err)
	}
	return nil
}

func authID(raw []byte) (auth.ID, error) {
	if len(raw) != len(auth.ID{}) {
		return auth.ID{}, fmt.Errorf("auth store: invalid binary user ID length %d", len(raw))
	}
	var id auth.ID
	copy(id[:], raw)
	return id, nil
}

func isOccupiedEmail(err error) bool {
	var mysqlError *mysql.MySQLError
	return errors.As(err, &mysqlError) &&
		mysqlError.Number == 1062 &&
		strings.Contains(mysqlError.Message, "uq_auth_identities_provider_subject")
}
