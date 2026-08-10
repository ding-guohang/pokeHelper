package mysqlstore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/go-sql-driver/mysql"

	"porkhelper/server/internal/auth"
)

const appleProvider = "apple"

type AppleIdentityStore struct {
	db *sql.DB
}

func NewAppleIdentityStore(db *sql.DB) *AppleIdentityStore {
	return &AppleIdentityStore{db: db}
}

var _ auth.AppleStore = (*AppleIdentityStore)(nil)

// ResolveAppleIdentity maps an Apple subject to its user, creating an
// independent user the first time a subject is seen.
//
// The lookup keys on (provider, subject) only. An Apple credential that
// happens to carry the same email as an existing password account must not
// join that account; merging is possible solely through LinkAppleIdentity,
// which requires a recently authenticated principal.
func (s *AppleIdentityStore) ResolveAppleIdentity(
	ctx context.Context,
	identity auth.AppleIdentity,
) (userID auth.ID, err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return auth.ID{}, fmt.Errorf("begin apple identity resolution: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	existing, found, err := lockAppleIdentity(ctx, tx, identity.Subject)
	if err != nil {
		return auth.ID{}, err
	}
	if found {
		if err = tx.Commit(); err != nil {
			return auth.ID{}, fmt.Errorf("commit apple identity lookup: %w", err)
		}
		return existing, nil
	}

	if _, err = tx.ExecContext(ctx,
		"INSERT INTO users (id) VALUES (?)",
		identity.UserID[:],
	); err != nil {
		return auth.ID{}, fmt.Errorf("insert apple user: %w", err)
	}

	email := nullableEmail(identity.CanonicalEmail)
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO auth_identities (
			id, user_id, provider, subject, canonical_email, display_email, email_verified
		) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		identity.IdentityID[:],
		identity.UserID[:],
		appleProvider,
		identity.Subject,
		email,
		email,
		identity.EmailVerified,
	); err != nil {
		if isDuplicateKey(err) {
			// Another request created the same subject first; adopt its user
			// instead of failing, so a concurrent first sign-in is idempotent.
			_ = tx.Rollback()
			err = nil
			return s.lookupAppleUser(ctx, identity.Subject)
		}
		return auth.ID{}, fmt.Errorf("insert apple identity: %w", err)
	}

	if _, err = tx.ExecContext(ctx,
		"INSERT INTO user_sync_sequences (user_id, next_sequence) VALUES (?, 0)",
		identity.UserID[:],
	); err != nil {
		return auth.ID{}, fmt.Errorf("insert apple user sync sequence: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return auth.ID{}, fmt.Errorf("commit apple identity creation: %w", err)
	}
	return identity.UserID, nil
}

// LinkAppleIdentity binds an Apple subject to an existing account.
func (s *AppleIdentityStore) LinkAppleIdentity(
	ctx context.Context,
	identity auth.AppleIdentity,
) (err error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin apple identity link: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	existing, found, err := lockAppleIdentity(ctx, tx, identity.Subject)
	if err != nil {
		return err
	}
	if found {
		if existing == identity.UserID {
			// Already linked to this account; linking again changes nothing.
			if err = tx.Commit(); err != nil {
				return fmt.Errorf("commit idempotent apple link: %w", err)
			}
			return nil
		}
		_ = tx.Rollback()
		err = nil
		return &auth.Error{Code: auth.IdentityConflict}
	}

	email := nullableEmail(identity.CanonicalEmail)
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO auth_identities (
			id, user_id, provider, subject, canonical_email, display_email, email_verified
		) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		identity.IdentityID[:],
		identity.UserID[:],
		appleProvider,
		identity.Subject,
		email,
		email,
		identity.EmailVerified,
	); err != nil {
		if isDuplicateKey(err) {
			_ = tx.Rollback()
			err = nil
			return &auth.Error{Code: auth.IdentityConflict}
		}
		return fmt.Errorf("link apple identity: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit apple identity link: %w", err)
	}
	return nil
}

func (s *AppleIdentityStore) lookupAppleUser(
	ctx context.Context,
	subject string,
) (auth.ID, error) {
	var raw []byte
	err := s.db.QueryRowContext(ctx, `
		SELECT user_id FROM auth_identities
		WHERE provider = ? AND subject = ?`,
		appleProvider,
		subject,
	).Scan(&raw)
	if err != nil {
		return auth.ID{}, fmt.Errorf("lookup apple identity: %w", err)
	}
	return toAuthID(raw)
}

func lockAppleIdentity(
	ctx context.Context,
	tx *sql.Tx,
	subject string,
) (auth.ID, bool, error) {
	var raw []byte
	err := tx.QueryRowContext(ctx, `
		SELECT user_id FROM auth_identities
		WHERE provider = ? AND subject = ?
		FOR UPDATE`,
		appleProvider,
		subject,
	).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return auth.ID{}, false, nil
	}
	if err != nil {
		return auth.ID{}, false, fmt.Errorf("lock apple identity: %w", err)
	}
	userID, err := toAuthID(raw)
	if err != nil {
		return auth.ID{}, false, err
	}
	return userID, true, nil
}

func toAuthID(raw []byte) (auth.ID, error) {
	if len(raw) != 16 {
		return auth.ID{}, fmt.Errorf("stored identifier has %d bytes, want 16", len(raw))
	}
	var id auth.ID
	copy(id[:], raw)
	return id, nil
}

func nullableEmail(canonical string) sql.NullString {
	if canonical == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: canonical, Valid: true}
}

// isDuplicateKey reports a MySQL unique-constraint violation.
func isDuplicateKey(err error) bool {
	var mysqlError *mysql.MySQLError
	return errors.As(err, &mysqlError) && mysqlError.Number == 1062
}
