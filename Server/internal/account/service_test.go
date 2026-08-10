package account_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/password"
	"porkhelper/server/internal/session"
)

var now = time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC)

const (
	userID       = "11111111-1111-4111-8111-111111111111"
	sessionID    = "22222222-2222-4222-8222-222222222222"
	appleSubject = "001234.fedcba9876543210fedcba9876543210.1234"
)

func TestRecentAuthenticationWindowUsesTheServerDerivedTimestamp(t *testing.T) {
	tests := map[string]struct {
		recentAuthAt time.Time
		allowed      bool
	}{
		"just authenticated":  {now, true},
		"inside the window":   {now.Add(-9 * time.Minute), true},
		"at the boundary":     {now.Add(-account.RecentAuthWindow), true},
		"past the window":     {now.Add(-account.RecentAuthWindow - time.Second), false},
		"never authenticated": {time.Time{}, false},
		// A clock-skewed future timestamp must not widen the window.
		"in the future": {now.Add(time.Hour), false},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			err := account.RequireRecentAuthentication(
				session.Principal{UserID: userID, RecentAuthAt: test.recentAuthAt},
				now,
				account.RecentAuthWindow,
			)
			if test.allowed && err != nil {
				t.Fatalf("expected allowed, got %v", err)
			}
			if !test.allowed && err == nil {
				t.Fatal("expected rejection")
			}
		})
	}
}

func TestPasswordProofRefreshesTheWindowOnlyWhenValid(t *testing.T) {
	fixture := newFixture(t)

	at, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now.Add(-time.Hour)),
		account.ReauthenticationProof{Password: fixture.password},
	)
	if err != nil {
		t.Fatalf("reauthenticate: %v", err)
	}
	if !at.Equal(now) {
		t.Errorf("recent auth = %s, want the server clock %s", at, now)
	}
	if fixture.store.markedAt != now || fixture.store.markedSession != sessionID {
		t.Error("the proving session must be the one refreshed")
	}
}

// A wrong password must leave the window exactly where it was, or repeated
// guessing would keep a stale session eligible for deletion.
func TestAWrongPasswordDoesNotRefreshTheWindow(t *testing.T) {
	fixture := newFixture(t)

	_, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now.Add(-time.Hour)),
		account.ReauthenticationProof{Password: "not-the-password-at-all"},
	)

	assertCode(t, err, account.AuthenticationFailed)
	if fixture.store.markCalls != 0 {
		t.Error("a failed proof must not touch the session")
	}
}

func TestAppleProofRequiresTheSubjectToBeLinkedToThisAccount(t *testing.T) {
	fixture := newFixture(t)
	fixture.store.appleSubject = appleSubject

	if _, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now.Add(-time.Hour)),
		account.ReauthenticationProof{AppleIdentityToken: "token", AppleNonce: "nonce"},
	); err != nil {
		t.Fatalf("reauthenticate with a linked subject: %v", err)
	}

	// A valid Apple credential for a subject linked elsewhere proves nothing
	// about this account.
	stranger := newFixture(t)
	stranger.store.appleSubject = "001234.somebody.else.0000"
	_, err := stranger.service.Reauthenticate(
		context.Background(),
		principal(now.Add(-time.Hour)),
		account.ReauthenticationProof{AppleIdentityToken: "token", AppleNonce: "nonce"},
	)

	assertCode(t, err, account.AuthenticationFailed)
	if stranger.store.markCalls != 0 {
		t.Error("an unlinked subject must not refresh the window")
	}
}

func TestAnInvalidAppleCredentialIsRejected(t *testing.T) {
	fixture := newFixture(t)
	fixture.store.appleSubject = appleSubject
	fixture.verifyErr = &appleauth.Error{Reason: "signature"}

	_, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now),
		account.ReauthenticationProof{AppleIdentityToken: "token", AppleNonce: "nonce"},
	)

	assertCode(t, err, account.AuthenticationFailed)
}

func TestExactlyOneProofMethodIsRequired(t *testing.T) {
	fixture := newFixture(t)

	for name, proof := range map[string]account.ReauthenticationProof{
		"neither": {},
		"both":    {Password: fixture.password, AppleIdentityToken: "token"},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := fixture.service.Reauthenticate(
				context.Background(),
				principal(now),
				proof,
			)
			assertCode(t, err, account.ValidationFailed)
		})
	}
}

func TestExportAndDeleteRefuseAStalePrincipal(t *testing.T) {
	fixture := newFixture(t)
	stale := principal(now.Add(-account.RecentAuthWindow - time.Minute))

	_, exportErr := fixture.service.Export(context.Background(), stale)
	deleteErr := fixture.service.Delete(context.Background(), stale)

	assertCode(t, exportErr, account.ReauthenticationRequired)
	assertCode(t, deleteErr, account.ReauthenticationRequired)
	if fixture.store.exportCalls != 0 || fixture.store.deleteCalls != 0 {
		t.Error("a stale principal must not reach the store at all")
	}
}

func TestExportAndDeleteProceedForARecentPrincipal(t *testing.T) {
	fixture := newFixture(t)
	recent := principal(now.Add(-time.Minute))

	document, err := fixture.service.Export(context.Background(), recent)
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	if err := fixture.service.Delete(context.Background(), recent); err != nil {
		t.Fatalf("delete: %v", err)
	}

	if document.SchemaVersion != account.ExportSchemaVersion {
		t.Errorf("schema version = %d, want %d", document.SchemaVersion, account.ExportSchemaVersion)
	}
	if fixture.store.exportedUserID != userID || fixture.store.deletedUserID != userID {
		t.Error("both operations must be scoped to the bearer principal")
	}
}

func principal(recentAuthAt time.Time) session.Principal {
	return session.Principal{
		UserID:       userID,
		SessionID:    sessionID,
		RecentAuthAt: recentAuthAt,
	}
}

type fixture struct {
	service   *account.Service
	store     *storeDouble
	password  string
	verifyErr error
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	hasher := password.NewHasher(nil)
	secret := "a-sufficiently-long-passphrase"
	phc, err := hasher.Hash(secret)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	built := &fixture{store: &storeDouble{passwordPHC: phc}, password: secret}
	built.service = account.NewService(
		built.store,
		hasher,
		verifierDouble{fixture: built},
		func() time.Time { return now },
	)
	return built
}

type verifierDouble struct {
	fixture *fixture
}

func (v verifierDouble) Verify(
	_ context.Context,
	_ string,
	_ string,
) (appleauth.Claims, error) {
	if v.fixture.verifyErr != nil {
		return appleauth.Claims{}, v.fixture.verifyErr
	}
	return appleauth.Claims{Subject: appleSubject}, nil
}

type storeDouble struct {
	passwordPHC  string
	appleSubject string

	markCalls      int
	markedAt       time.Time
	markedSession  string
	exportCalls    int
	exportedUserID string
	deleteCalls    int
	deletedUserID  string
}

func (s *storeDouble) PasswordHash(_ context.Context, _ string) (string, bool, error) {
	if s.passwordPHC == "" {
		return "", false, nil
	}
	return s.passwordPHC, true, nil
}

func (s *storeDouble) HasAppleSubject(
	_ context.Context,
	_ string,
	subject string,
) (bool, error) {
	return s.appleSubject != "" && s.appleSubject == subject, nil
}

func (s *storeDouble) MarkRecentAuthentication(
	_ context.Context,
	_ string,
	sessionID string,
	at time.Time,
) error {
	s.markCalls++
	s.markedAt = at
	s.markedSession = sessionID
	return nil
}

func (s *storeDouble) Export(
	_ context.Context,
	userID string,
) (account.ExportDocument, error) {
	s.exportCalls++
	s.exportedUserID = userID
	return account.ExportDocument{}, nil
}

func (s *storeDouble) Delete(_ context.Context, userID string) error {
	s.deleteCalls++
	s.deletedUserID = userID
	return nil
}

func assertCode(t *testing.T, err error, want account.ErrorCode) {
	t.Helper()
	var accountError *account.Error
	if !errors.As(err, &accountError) {
		t.Fatalf("error %v is not an *account.Error", err)
	}
	if accountError.Code != want {
		t.Errorf("code = %q, want %q", accountError.Code, want)
	}
}

// A stolen access token must not become a password oracle. Without a throttle,
// reauth allows unlimited Argon2 guesses at wire speed.
func TestReauthenticationIsThrottled(t *testing.T) {
	fixture := newFixture(t)
	throttle := &throttleDouble{}
	fixture.service = account.NewService(
		fixture.store,
		password.NewHasher(nil),
		verifierDouble{fixture: fixture},
		func() time.Time { return now },
		account.WithThrottle(throttle),
	)

	_, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now),
		account.ReauthenticationProof{Password: "wrong-password-entirely"},
	)

	assertCode(t, err, account.AuthenticationFailed)
	if throttle.checks != 1 {
		t.Errorf("checked %d times, want the budget consulted before hashing", throttle.checks)
	}
	if throttle.consumed != 1 {
		t.Errorf("consumed %d attempts, want a failure to count", throttle.consumed)
	}
}

func TestAnExhaustedBudgetRefusesBeforeHashing(t *testing.T) {
	fixture := newFixture(t)
	throttle := &throttleDouble{checkErr: &account.Error{Code: account.AuthenticationFailed}}
	fixture.service = account.NewService(
		fixture.store,
		password.NewHasher(nil),
		verifierDouble{fixture: fixture},
		func() time.Time { return now },
		account.WithThrottle(throttle),
	)

	_, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now),
		account.ReauthenticationProof{Password: fixture.password},
	)

	if err == nil {
		t.Fatal("an exhausted budget must refuse the attempt")
	}
	if fixture.store.markCalls != 0 {
		t.Error("a refused attempt must not refresh the window")
	}
}

func TestASuccessfulProofClearsTheBudget(t *testing.T) {
	fixture := newFixture(t)
	throttle := &throttleDouble{}
	fixture.service = account.NewService(
		fixture.store,
		password.NewHasher(nil),
		verifierDouble{fixture: fixture},
		func() time.Time { return now },
		account.WithThrottle(throttle),
	)

	if _, err := fixture.service.Reauthenticate(
		context.Background(),
		principal(now),
		account.ReauthenticationProof{Password: fixture.password},
	); err != nil {
		t.Fatalf("reauthenticate: %v", err)
	}

	if throttle.cleared != 1 {
		t.Errorf("cleared %d times, want a success to reset the budget", throttle.cleared)
	}
	if throttle.consumed != 0 {
		t.Error("a success must not count against the budget")
	}
}

type throttleDouble struct {
	checks   int
	consumed int
	cleared  int
	checkErr error
}

func (t *throttleDouble) Check(_ context.Context, _ string, _ string) error {
	t.checks++
	return t.checkErr
}

func (t *throttleDouble) Consume(_ context.Context, _ string, _ string) error {
	t.consumed++
	return nil
}

func (t *throttleDouble) ClearAccount(_ context.Context, _ string) error {
	t.cleared++
	return nil
}
