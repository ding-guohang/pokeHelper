//go:build integration

package mysqlstore_test

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

const (
	appleTestSubject     = "001234.fedcba9876543210fedcba9876543210.1234"
	appleOtherSubject    = "009876.0123456789abcdef0123456789abcdef.9876"
	appleSharedTestEmail = "shared@example.test"
)

func TestResolvingAnUnknownAppleSubjectCreatesAnIndependentUser(t *testing.T) {
	db, store := newAppleFixture(t)
	identity := appleIdentity(t, appleTestSubject, "")

	userID, err := store.ResolveAppleIdentity(context.Background(), identity)
	if err != nil {
		t.Fatalf("resolve apple identity: %v", err)
	}

	if userID != identity.UserID {
		t.Errorf("returned user %s, want the freshly created %s", userID, identity.UserID)
	}

	var sequence int64
	if err := db.QueryRow(
		"SELECT next_sequence FROM user_sync_sequences WHERE user_id = ?",
		userID[:],
	).Scan(&sequence); err != nil {
		t.Fatalf("a new Apple user must get a sync sequence row: %v", err)
	}
	if sequence != 0 {
		t.Errorf("next_sequence = %d, want 0", sequence)
	}
}

func TestResolvingAKnownAppleSubjectReturnsTheSameStableUser(t *testing.T) {
	_, store := newAppleFixture(t)

	first, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleTestSubject, ""))
	if err != nil {
		t.Fatalf("first resolve: %v", err)
	}
	second, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleTestSubject, ""))
	if err != nil {
		t.Fatalf("second resolve: %v", err)
	}

	if first != second {
		t.Errorf("subject mapped to %s then %s, want one stable user", first, second)
	}
}

// The security-critical rule: an Apple credential carrying the same email as
// an existing password account must not take that account over.
func TestAnAppleSubjectSharingAnEmailStaysASeparateAccount(t *testing.T) {
	db, store := newAppleFixture(t)
	emailUserID := createEmailAccount(t, db, appleSharedTestEmail)

	appleUserID, err := store.ResolveAppleIdentity(
		context.Background(),
		appleIdentity(t, appleTestSubject, appleSharedTestEmail),
	)
	if err != nil {
		t.Fatalf("resolve apple identity: %v", err)
	}

	if appleUserID == emailUserID {
		t.Fatal("Apple sign-in merged into the existing email account by email")
	}

	var users int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if users != 2 {
		t.Errorf("database holds %d users, want 2 independent accounts", users)
	}
}

func TestLinkingBindsAnAppleSubjectToAnExistingAccount(t *testing.T) {
	db, store := newAppleFixture(t)
	emailUserID := createEmailAccount(t, db, appleSharedTestEmail)

	identity := appleIdentity(t, appleTestSubject, appleSharedTestEmail)
	identity.UserID = emailUserID
	if err := store.LinkAppleIdentity(context.Background(), identity); err != nil {
		t.Fatalf("link apple identity: %v", err)
	}

	resolved, err := store.ResolveAppleIdentity(
		context.Background(),
		appleIdentity(t, appleTestSubject, appleSharedTestEmail),
	)
	if err != nil {
		t.Fatalf("resolve after link: %v", err)
	}
	if resolved != emailUserID {
		t.Errorf("after linking, the subject resolved to %s, want %s", resolved, emailUserID)
	}

	var users int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if users != 1 {
		t.Errorf("linking created %d users, want the original 1", users)
	}
}

func TestLinkingIsIdempotentForTheSameAccount(t *testing.T) {
	db, store := newAppleFixture(t)
	emailUserID := createEmailAccount(t, db, appleSharedTestEmail)

	identity := appleIdentity(t, appleTestSubject, "")
	identity.UserID = emailUserID
	if err := store.LinkAppleIdentity(context.Background(), identity); err != nil {
		t.Fatalf("first link: %v", err)
	}

	repeat := appleIdentity(t, appleTestSubject, "")
	repeat.UserID = emailUserID
	if err := store.LinkAppleIdentity(context.Background(), repeat); err != nil {
		t.Errorf("relinking the same subject to the same account must succeed: %v", err)
	}

	var identities int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM auth_identities WHERE provider = 'apple' AND subject = ?",
		appleTestSubject,
	).Scan(&identities); err != nil {
		t.Fatalf("count apple identities: %v", err)
	}
	if identities != 1 {
		t.Errorf("stored %d apple identity rows, want 1", identities)
	}
}

func TestLinkingASubjectOwnedByAnotherAccountConflicts(t *testing.T) {
	db, store := newAppleFixture(t)
	ownerID, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleTestSubject, ""))
	if err != nil {
		t.Fatalf("create apple owner: %v", err)
	}
	intruderID := createEmailAccount(t, db, "intruder@example.test")

	identity := appleIdentity(t, appleTestSubject, "")
	identity.UserID = intruderID
	err = store.LinkAppleIdentity(context.Background(), identity)

	var authError *auth.Error
	if !errors.As(err, &authError) || authError.Code != auth.IdentityConflict {
		t.Fatalf("error = %v, want an identityConflict", err)
	}

	resolved, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleTestSubject, ""))
	if err != nil {
		t.Fatalf("resolve after conflict: %v", err)
	}
	if resolved != ownerID {
		t.Error("a failed link must leave the original owner bound to the subject")
	}
}

func TestConcurrentFirstSignInCreatesExactlyOneAppleUser(t *testing.T) {
	db, store := newAppleFixture(t)

	const callers = 4
	var group sync.WaitGroup
	results := make([]auth.ID, callers)
	errs := make([]error, callers)
	group.Add(callers)
	for index := range results {
		go func() {
			defer group.Done()
			results[index], errs[index] = store.ResolveAppleIdentity(
				context.Background(),
				appleIdentity(t, appleTestSubject, ""),
			)
		}()
	}
	group.Wait()

	for index, err := range errs {
		if err != nil {
			t.Fatalf("caller %d: %v", index, err)
		}
	}
	for _, result := range results[1:] {
		if result != results[0] {
			t.Errorf("concurrent sign-in produced diverging users %s and %s", results[0], result)
		}
	}

	var identities int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM auth_identities WHERE provider = 'apple' AND subject = ?",
		appleTestSubject,
	).Scan(&identities); err != nil {
		t.Fatalf("count apple identities: %v", err)
	}
	if identities != 1 {
		t.Errorf("stored %d apple identity rows, want exactly 1", identities)
	}
}

func TestAppleSubjectsAreMatchedCaseSensitively(t *testing.T) {
	_, store := newAppleFixture(t)

	first, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleTestSubject, ""))
	if err != nil {
		t.Fatalf("resolve lowercase subject: %v", err)
	}
	second, err := store.ResolveAppleIdentity(context.Background(), appleIdentity(t, appleOtherSubject, ""))
	if err != nil {
		t.Fatalf("resolve other subject: %v", err)
	}

	if first == second {
		t.Error("distinct Apple subjects must map to distinct users")
	}
}

func newAppleFixture(t *testing.T) (*sql.DB, *mysqlstore.AppleIdentityStore) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	return db, mysqlstore.NewAppleIdentityStore(db)
}

func appleIdentity(t *testing.T, subject string, canonicalEmail string) auth.AppleIdentity {
	t.Helper()
	return auth.AppleIdentity{
		IdentityID:     randomAuthID(t),
		UserID:         randomAuthID(t),
		Subject:        subject,
		CanonicalEmail: canonicalEmail,
		EmailVerified:  canonicalEmail != "",
		Now:            time.Date(2026, 8, 7, 12, 0, 0, 0, time.UTC),
	}
}

func randomAuthID(t *testing.T) auth.ID {
	t.Helper()
	var id auth.ID
	if _, err := rand.Read(id[:]); err != nil {
		t.Fatalf("generate identifier: %v", err)
	}
	return id
}

// createEmailAccount inserts a verified password account directly, so Apple
// tests can assert against a pre-existing email identity.
func createEmailAccount(t *testing.T, db *sql.DB, canonicalEmail string) auth.ID {
	t.Helper()
	userID := randomAuthID(t)
	identityID := randomAuthID(t)

	if _, err := db.Exec("INSERT INTO users (id) VALUES (?)", userID[:]); err != nil {
		t.Fatalf("insert email user: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO auth_identities (
			id, user_id, provider, subject, canonical_email, display_email, email_verified
		) VALUES (?, ?, 'email', ?, ?, ?, TRUE)`,
		identityID[:], userID[:], canonicalEmail, canonicalEmail, canonicalEmail,
	); err != nil {
		t.Fatalf("insert email identity: %v", err)
	}
	if _, err := db.Exec(
		"INSERT INTO user_sync_sequences (user_id, next_sequence) VALUES (?, 0)",
		userID[:],
	); err != nil {
		t.Fatalf("insert sync sequence: %v", err)
	}
	return userID
}
