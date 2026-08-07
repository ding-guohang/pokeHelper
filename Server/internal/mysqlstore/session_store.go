package mysqlstore

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"porkhelper/server/internal/session"
)

// consumedTokenRetention is the window during which consumed and revoked
// refresh tokens must stay readable so a replay can still be recognized. This
// store never deletes token history; any future purge must respect this bound.
const consumedTokenRetention = 90 * 24 * time.Hour

const (
	maxDisplayNameLength = 255
	maxPlatformLength    = 32
	maxAppVersionLength  = 64
)

type SessionStore struct {
	db *sql.DB
}

func NewSessionStore(db *sql.DB) *SessionStore {
	return &SessionStore{db: db}
}

var _ session.Store = (*SessionStore)(nil)

// ConsumedTokenRetention reports how long consumed refresh tokens are kept.
func (s *SessionStore) ConsumedTokenRetention() time.Duration {
	return consumedTokenRetention
}

func (s *SessionStore) CreateSession(
	ctx context.Context,
	created session.NewSession,
) (err error) {
	userID, err := parseUUID(created.UserID)
	if err != nil {
		return err
	}
	installationID, err := parseUUID(created.Device.DeviceID)
	if err != nil {
		return err
	}
	if err := validateDeviceStrings(created.Device); err != nil {
		return err
	}

	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin create session: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	deviceID, err := upsertDevice(ctx, tx, userID, installationID, created)
	if err != nil {
		return err
	}

	if _, err = tx.ExecContext(ctx, `
		INSERT INTO sessions (
			id, user_id, device_id, token_family_id, current_access_token_hash,
			access_expires_at, recent_authenticated_at, last_active_at, created_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		created.SessionID[:],
		userID,
		deviceID,
		created.TokenFamilyID[:],
		created.AccessHash[:],
		created.AccessExpiresAt,
		created.RecentAuthAt,
		created.Now,
		created.Now,
	); err != nil {
		return fmt.Errorf("insert session: %w", err)
	}

	if _, err = tx.ExecContext(ctx, `
		INSERT INTO refresh_tokens (
			id, user_id, session_id, token_hash, expires_at, created_at
		) VALUES (?, ?, ?, ?, ?, ?)`,
		created.RefreshTokenID[:],
		userID,
		created.SessionID[:],
		created.RefreshHash[:],
		created.RefreshExpiresAt,
		created.Now,
	); err != nil {
		return fmt.Errorf("insert refresh token: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit create session: %w", err)
	}
	return nil
}

func upsertDevice(
	ctx context.Context,
	tx *sql.Tx,
	userID []byte,
	installationID []byte,
	created session.NewSession,
) ([]byte, error) {
	var deviceID []byte
	err := tx.QueryRowContext(ctx, `
		SELECT id FROM devices
		WHERE user_id = ? AND installation_id = ?
		FOR UPDATE`,
		userID,
		installationID,
	).Scan(&deviceID)
	switch {
	case err == nil:
		if _, err := tx.ExecContext(ctx, `
			UPDATE devices
			SET display_name = ?, platform = ?, app_version = ?,
			    last_seen_at = ?, revoked_at = NULL
			WHERE id = ?`,
			created.Device.DisplayName,
			created.Device.Platform,
			created.Device.AppVersion,
			created.Now,
			deviceID,
		); err != nil {
			return nil, fmt.Errorf("update device: %w", err)
		}
		return deviceID, nil
	case errors.Is(err, sql.ErrNoRows):
		fresh, err := randomUUID()
		if err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO devices (
				id, user_id, installation_id, display_name, platform,
				app_version, created_at, last_seen_at
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			fresh,
			userID,
			installationID,
			created.Device.DisplayName,
			created.Device.Platform,
			created.Device.AppVersion,
			created.Now,
			created.Now,
		); err != nil {
			return nil, fmt.Errorf("insert device: %w", err)
		}
		return fresh, nil
	default:
		return nil, fmt.Errorf("lookup device: %w", err)
	}
}

func (s *SessionStore) AuthenticateAccess(
	ctx context.Context,
	accessHash [32]byte,
	now time.Time,
) (session.Principal, error) {
	var (
		userID       []byte
		sessionID    []byte
		deviceID     []byte
		recentAuthAt time.Time
	)
	err := s.db.QueryRowContext(ctx, `
		SELECT s.user_id, s.id, d.installation_id, s.recent_authenticated_at
		FROM sessions s
		JOIN devices d ON d.user_id = s.user_id AND d.id = s.device_id
		WHERE s.current_access_token_hash = ?
		  AND s.revoked_at IS NULL
		  AND s.access_expires_at > ?`,
		accessHash[:],
		now,
	).Scan(&userID, &sessionID, &deviceID, &recentAuthAt)
	if errors.Is(err, sql.ErrNoRows) {
		return session.Principal{}, &session.Error{Code: session.Unauthenticated}
	}
	if err != nil {
		return session.Principal{}, fmt.Errorf("authenticate access token: %w", err)
	}

	if _, err := s.db.ExecContext(ctx, `
		UPDATE sessions SET last_active_at = ? WHERE id = ?`,
		now,
		sessionID,
	); err != nil {
		return session.Principal{}, fmt.Errorf("touch session activity: %w", err)
	}

	return session.Principal{
		UserID:       formatUUID(userID),
		SessionID:    formatUUID(sessionID),
		DeviceID:     formatUUID(deviceID),
		RecentAuthAt: recentAuthAt.UTC(),
	}, nil
}

// RotateRefresh consumes the presented refresh token and installs its
// replacements in one row-locked transaction. Presenting a token that was
// already consumed or revoked is a replay: the whole session family is revoked
// and no new tokens are issued.
func (s *SessionStore) RotateRefresh(
	ctx context.Context,
	rotation session.Rotation,
) (outcome session.RotationOutcome, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return session.RotationOutcome{}, fmt.Errorf("begin refresh rotation: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var (
		tokenID        []byte
		userID         []byte
		sessionID      []byte
		consumedAt     sql.NullTime
		tokenRevokedAt sql.NullTime
		expiresAt      time.Time
		sessionRevoked sql.NullTime
		recentAuthAt   time.Time
	)
	err = tx.QueryRowContext(ctx, `
		SELECT rt.id, rt.user_id, rt.session_id, rt.consumed_at, rt.revoked_at,
		       rt.expires_at, s.revoked_at, s.recent_authenticated_at
		FROM refresh_tokens rt
		JOIN sessions s ON s.user_id = rt.user_id AND s.id = rt.session_id
		WHERE rt.token_hash = ?
		FOR UPDATE`,
		rotation.PresentedHash[:],
	).Scan(
		&tokenID, &userID, &sessionID, &consumedAt, &tokenRevokedAt,
		&expiresAt, &sessionRevoked, &recentAuthAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		err = nil
		if commitErr := tx.Commit(); commitErr != nil {
			return session.RotationOutcome{}, fmt.Errorf("commit unknown refresh: %w", commitErr)
		}
		return session.RotationOutcome{}, nil
	}
	if err != nil {
		return session.RotationOutcome{}, fmt.Errorf("lock refresh token: %w", err)
	}

	if consumedAt.Valid || tokenRevokedAt.Valid {
		if err = revokeSessionFamily(ctx, tx, userID, sessionID, rotation.Now); err != nil {
			return session.RotationOutcome{}, err
		}
		if err = tx.Commit(); err != nil {
			return session.RotationOutcome{}, fmt.Errorf("commit replay revocation: %w", err)
		}
		return session.RotationOutcome{Replayed: true}, nil
	}

	if sessionRevoked.Valid || !expiresAt.After(rotation.Now) {
		if err = tx.Commit(); err != nil {
			return session.RotationOutcome{}, fmt.Errorf("commit expired refresh: %w", err)
		}
		return session.RotationOutcome{}, nil
	}

	result, err := tx.ExecContext(ctx, `
		UPDATE refresh_tokens SET consumed_at = ?
		WHERE id = ? AND consumed_at IS NULL AND revoked_at IS NULL`,
		rotation.Now,
		tokenID,
	)
	if err != nil {
		return session.RotationOutcome{}, fmt.Errorf("consume refresh token: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return session.RotationOutcome{}, fmt.Errorf("inspect consumed refresh token: %w", err)
	}
	if affected != 1 {
		// Another transaction consumed the same row first; treat as a replay.
		if err = revokeSessionFamily(ctx, tx, userID, sessionID, rotation.Now); err != nil {
			return session.RotationOutcome{}, err
		}
		if err = tx.Commit(); err != nil {
			return session.RotationOutcome{}, fmt.Errorf("commit contended revocation: %w", err)
		}
		return session.RotationOutcome{Replayed: true}, nil
	}

	if _, err = tx.ExecContext(ctx, `
		INSERT INTO refresh_tokens (
			id, user_id, session_id, token_hash, expires_at, created_at
		) VALUES (?, ?, ?, ?, ?, ?)`,
		rotation.RefreshTokenID[:],
		userID,
		sessionID,
		rotation.RefreshHash[:],
		rotation.RefreshExpiresAt,
		rotation.Now,
	); err != nil {
		return session.RotationOutcome{}, fmt.Errorf("insert rotated refresh token: %w", err)
	}

	if _, err = tx.ExecContext(ctx, `
		UPDATE sessions
		SET current_access_token_hash = ?, access_expires_at = ?, last_active_at = ?
		WHERE id = ?`,
		rotation.AccessHash[:],
		rotation.AccessExpiresAt,
		rotation.Now,
		sessionID,
	); err != nil {
		return session.RotationOutcome{}, fmt.Errorf("install rotated access token: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return session.RotationOutcome{}, fmt.Errorf("commit refresh rotation: %w", err)
	}

	return session.RotationOutcome{
		UserID:       formatUUID(userID),
		SessionID:    formatUUID(sessionID),
		RecentAuthAt: recentAuthAt.UTC(),
	}, nil
}

func (s *SessionStore) RevokeByRefresh(
	ctx context.Context,
	refreshHash [32]byte,
	now time.Time,
) (err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin refresh revocation: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID, sessionID []byte
	err = tx.QueryRowContext(ctx, `
		SELECT user_id, session_id FROM refresh_tokens
		WHERE token_hash = ?
		FOR UPDATE`,
		refreshHash[:],
	).Scan(&userID, &sessionID)
	if errors.Is(err, sql.ErrNoRows) {
		// Logout is idempotent: an unknown or already-purged token is done.
		err = nil
		if commitErr := tx.Commit(); commitErr != nil {
			return fmt.Errorf("commit unknown refresh revocation: %w", commitErr)
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("lock refresh token for revocation: %w", err)
	}

	if err = revokeSessionFamily(ctx, tx, userID, sessionID, now); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit refresh revocation: %w", err)
	}
	return nil
}

func (s *SessionStore) ListDevices(
	ctx context.Context,
	userID string,
	now time.Time,
) ([]session.DeviceSession, error) {
	ownerID, err := parseUUID(userID)
	if err != nil {
		return nil, err
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT s.id, d.installation_id, d.display_name, d.platform,
		       d.app_version, s.created_at, s.last_active_at
		FROM sessions s
		JOIN devices d ON d.user_id = s.user_id AND d.id = s.device_id
		WHERE s.user_id = ?
		  AND s.revoked_at IS NULL
		  AND EXISTS (
		      SELECT 1 FROM refresh_tokens rt
		      WHERE rt.user_id = s.user_id
		        AND rt.session_id = s.id
		        AND rt.consumed_at IS NULL
		        AND rt.revoked_at IS NULL
		        AND rt.expires_at > ?
		  )
		ORDER BY s.last_active_at DESC, s.id ASC`,
		ownerID,
		now,
	)
	if err != nil {
		return nil, fmt.Errorf("list device sessions: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var devices []session.DeviceSession
	for rows.Next() {
		var (
			sessionID    []byte
			deviceID     []byte
			device       session.DeviceSession
			createdAt    time.Time
			lastActiveAt time.Time
		)
		if err := rows.Scan(
			&sessionID, &deviceID, &device.DisplayName, &device.Platform,
			&device.AppVersion, &createdAt, &lastActiveAt,
		); err != nil {
			return nil, fmt.Errorf("scan device session: %w", err)
		}
		device.SessionID = formatUUID(sessionID)
		device.DeviceID = formatUUID(deviceID)
		device.CreatedAt = createdAt.UTC()
		device.LastActiveAt = lastActiveAt.UTC()
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate device sessions: %w", err)
	}
	return devices, nil
}

func (s *SessionStore) RevokeSession(
	ctx context.Context,
	userID string,
	sessionID string,
	now time.Time,
) (err error) {
	ownerID, err := parseUUID(userID)
	if err != nil {
		return err
	}
	target, err := parseUUID(sessionID)
	if err != nil {
		return &session.Error{Code: session.NotFound}
	}

	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin session revocation: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var revokedAt sql.NullTime
	err = tx.QueryRowContext(ctx, `
		SELECT revoked_at FROM sessions
		WHERE user_id = ? AND id = ?
		FOR UPDATE`,
		ownerID,
		target,
	).Scan(&revokedAt)
	if errors.Is(err, sql.ErrNoRows) {
		// A session owned by somebody else is indistinguishable from one that
		// does not exist.
		_ = tx.Rollback()
		err = nil
		return &session.Error{Code: session.NotFound}
	}
	if err != nil {
		return fmt.Errorf("lock session for revocation: %w", err)
	}

	if err = revokeSessionFamily(ctx, tx, ownerID, target, now); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit session revocation: %w", err)
	}
	return nil
}

func (s *SessionStore) RevokeAllForUser(
	ctx context.Context,
	userID string,
	exceptSessionID string,
	now time.Time,
) (err error) {
	ownerID, err := parseUUID(userID)
	if err != nil {
		return err
	}

	var spared []byte
	if exceptSessionID != "" {
		if spared, err = parseUUID(exceptSessionID); err != nil {
			return err
		}
	}

	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin bulk revocation: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	sessionClause := "user_id = ? AND revoked_at IS NULL"
	tokenClause := "user_id = ? AND revoked_at IS NULL AND consumed_at IS NULL"
	arguments := []any{now, ownerID}
	if spared != nil {
		sessionClause += " AND id <> ?"
		tokenClause += " AND session_id <> ?"
		arguments = append(arguments, spared)
	}

	if _, err = tx.ExecContext(ctx,
		"UPDATE sessions SET revoked_at = ? WHERE "+sessionClause,
		arguments...,
	); err != nil {
		return fmt.Errorf("revoke user sessions: %w", err)
	}
	if _, err = tx.ExecContext(ctx,
		"UPDATE refresh_tokens SET revoked_at = ? WHERE "+tokenClause,
		arguments...,
	); err != nil {
		return fmt.Errorf("revoke user refresh tokens: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit bulk revocation: %w", err)
	}
	return nil
}

// revokeSessionFamily revokes a session and every refresh token in its family.
// Consumed rows keep their history so a later replay is still detectable.
func revokeSessionFamily(
	ctx context.Context,
	tx *sql.Tx,
	userID []byte,
	sessionID []byte,
	now time.Time,
) error {
	if _, err := tx.ExecContext(ctx, `
		UPDATE sessions SET revoked_at = ?
		WHERE user_id = ? AND id = ? AND revoked_at IS NULL`,
		now,
		userID,
		sessionID,
	); err != nil {
		return fmt.Errorf("revoke session: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE refresh_tokens SET revoked_at = ?
		WHERE user_id = ? AND session_id = ? AND revoked_at IS NULL`,
		now,
		userID,
		sessionID,
	); err != nil {
		return fmt.Errorf("revoke session refresh tokens: %w", err)
	}
	return nil
}

func validateDeviceStrings(device session.DeviceMetadata) error {
	if len(device.DisplayName) > maxDisplayNameLength ||
		len(device.Platform) > maxPlatformLength ||
		len(device.AppVersion) > maxAppVersionLength {
		return &session.Error{Code: session.ValidationFailed}
	}
	return nil
}

func randomUUID() ([]byte, error) {
	value := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, value); err != nil {
		return nil, fmt.Errorf("draw device identifier: %w", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return value, nil
}

func parseUUID(value string) ([]byte, error) {
	compact := strings.ReplaceAll(value, "-", "")
	if len(compact) != 32 {
		return nil, &session.Error{Code: session.ValidationFailed}
	}
	decoded, err := hex.DecodeString(compact)
	if err != nil {
		return nil, &session.Error{Code: session.ValidationFailed}
	}
	return decoded, nil
}

func formatUUID(value []byte) string {
	if len(value) != 16 {
		return ""
	}
	return fmt.Sprintf(
		"%08x-%04x-%04x-%04x-%012x",
		value[0:4], value[4:6], value[6:8], value[8:10], value[10:16],
	)
}
