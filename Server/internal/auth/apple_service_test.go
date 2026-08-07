package auth_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/auth"
)

const (
	appleSubject   = "001234.fedcba9876543210fedcba9876543210.1234"
	appleTokenText = "valid.apple.token"
	appleNonce     = "expected-nonce"
)

func TestAppleSignInMapsAVerifiedSubjectToAStableUser(t *testing.T) {
	fixture := newAppleServiceFixture()

	result, err := fixture.service.SignIn(context.Background(), auth.AppleSignInInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
		Device:        auth.DeviceMetadata{DeviceID: "installation-a", DisplayName: "iPhone"},
	})
	if err != nil {
		t.Fatalf("apple sign in: %v", err)
	}

	if result.UserID == "" {
		t.Error("a verified Apple sign-in must produce a session for a user")
	}
	if fixture.store.resolved.Subject != appleSubject {
		t.Errorf("resolved subject %q, want %q", fixture.store.resolved.Subject, appleSubject)
	}
	if fixture.issuer.issuedFor != result.UserID {
		t.Errorf("session issued for %q, want %q", fixture.issuer.issuedFor, result.UserID)
	}
}

func TestAppleSignInDoesNotMergeAccountsThatShareAnEmail(t *testing.T) {
	fixture := newAppleServiceFixture()
	fixture.claims.Email = "player@example.test"
	fixture.claims.EmailVerified = true

	if _, err := fixture.service.SignIn(context.Background(), auth.AppleSignInInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
		Device:        auth.DeviceMetadata{DeviceID: "installation-a"},
	}); err != nil {
		t.Fatalf("apple sign in: %v", err)
	}

	if fixture.store.lookedUpByEmail {
		t.Error("Apple sign-in must never resolve an account by email")
	}
	if fixture.store.resolved.Subject != appleSubject {
		t.Error("identity resolution must key on the Apple subject alone")
	}
}

func TestAppleSignInWithAnInvalidCredentialCreatesNothing(t *testing.T) {
	for _, reason := range []string{"signature", "audience", "expired", "nonce"} {
		fixture := newAppleServiceFixture()
		fixture.verifyErr = &appleauth.Error{Reason: reason}

		_, err := fixture.service.SignIn(context.Background(), auth.AppleSignInInput{
			IdentityToken: appleTokenText,
			Nonce:         appleNonce,
			Device:        auth.DeviceMetadata{DeviceID: "installation-a"},
		})

		assertAuthCode(t, err, auth.AuthenticationFailed)
		if fixture.store.resolveCalls != 0 {
			t.Errorf("reason %q: an invalid credential must not touch the identity store", reason)
		}
		if fixture.issuer.issueCalls != 0 {
			t.Errorf("reason %q: an invalid credential must not create a session", reason)
		}
	}
}

func TestAppleSignInRejectionDoesNotRevealWhyTheCredentialFailed(t *testing.T) {
	fixture := newAppleServiceFixture()
	fixture.verifyErr = &appleauth.Error{Reason: "audience"}

	_, err := fixture.service.SignIn(context.Background(), auth.AppleSignInInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
		Device:        auth.DeviceMetadata{DeviceID: "installation-a"},
	})

	var authError *auth.Error
	if !errors.As(err, &authError) {
		t.Fatalf("error %v is not an *auth.Error", err)
	}
	if authError.Code != auth.AuthenticationFailed {
		t.Errorf("code = %q, want %q", authError.Code, auth.AuthenticationFailed)
	}
}

func TestAppleSignInRequiresADevice(t *testing.T) {
	fixture := newAppleServiceFixture()

	_, err := fixture.service.SignIn(context.Background(), auth.AppleSignInInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	})

	assertAuthCode(t, err, auth.ValidationFailed)
	if fixture.store.resolveCalls != 0 {
		t.Error("a request without a device must not touch the identity store")
	}
}

func TestAppleLinkRequiresARecentlyAuthenticatedPrincipal(t *testing.T) {
	fixture := newAppleServiceFixture()
	principal := auth.Principal{
		UserID:       "11111111-1111-4111-8111-111111111111",
		RecentAuthAt: fixture.now.Add(-11 * time.Minute),
	}

	err := fixture.service.Link(context.Background(), principal, auth.AppleLinkInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	})

	assertAuthCode(t, err, auth.ReauthenticationRequired)
	if fixture.store.linkCalls != 0 {
		t.Error("a stale principal must not link an identity")
	}
}

func TestAppleLinkAcceptsAPrincipalInsideTheTenMinuteWindow(t *testing.T) {
	fixture := newAppleServiceFixture()
	principal := auth.Principal{
		UserID:       "11111111-1111-4111-8111-111111111111",
		RecentAuthAt: fixture.now.Add(-9 * time.Minute),
	}

	if err := fixture.service.Link(context.Background(), principal, auth.AppleLinkInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	}); err != nil {
		t.Fatalf("link apple identity: %v", err)
	}

	if fixture.store.linked.Subject != appleSubject {
		t.Errorf("linked subject %q, want %q", fixture.store.linked.Subject, appleSubject)
	}
	if fixture.store.linked.UserID.String() != principal.UserID {
		t.Errorf("linked to user %q, want the authenticated %q",
			fixture.store.linked.UserID.String(), principal.UserID)
	}
}

func TestAppleLinkRejectsAnUnauthenticatedCaller(t *testing.T) {
	fixture := newAppleServiceFixture()

	err := fixture.service.Link(context.Background(), auth.Principal{}, auth.AppleLinkInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	})

	assertAuthCode(t, err, auth.AuthenticationFailed)
	if fixture.store.linkCalls != 0 {
		t.Error("an unauthenticated caller must not link an identity")
	}
}

func TestAppleLinkRejectsAnInvalidCredentialBeforeTouchingTheStore(t *testing.T) {
	fixture := newAppleServiceFixture()
	fixture.verifyErr = &appleauth.Error{Reason: "nonce"}
	principal := auth.Principal{
		UserID:       "11111111-1111-4111-8111-111111111111",
		RecentAuthAt: fixture.now,
	}

	err := fixture.service.Link(context.Background(), principal, auth.AppleLinkInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	})

	assertAuthCode(t, err, auth.AuthenticationFailed)
	if fixture.store.linkCalls != 0 {
		t.Error("an invalid credential must not link an identity")
	}
}

func TestAppleLinkSurfacesAConflictWhenTheSubjectBelongsToAnotherUser(t *testing.T) {
	fixture := newAppleServiceFixture()
	fixture.store.linkErr = &auth.Error{Code: auth.IdentityConflict}
	principal := auth.Principal{
		UserID:       "11111111-1111-4111-8111-111111111111",
		RecentAuthAt: fixture.now,
	}

	err := fixture.service.Link(context.Background(), principal, auth.AppleLinkInput{
		IdentityToken: appleTokenText,
		Nonce:         appleNonce,
	})

	assertAuthCode(t, err, auth.IdentityConflict)
}

type appleServiceFixture struct {
	service   *auth.AppleService
	store     *appleStoreDouble
	issuer    *appleIssuerDouble
	claims    appleauth.Claims
	verifyErr error
	now       time.Time
}

func newAppleServiceFixture() *appleServiceFixture {
	now := time.Date(2026, 8, 7, 12, 0, 0, 0, time.UTC)
	fixture := &appleServiceFixture{
		store:  &appleStoreDouble{},
		issuer: &appleIssuerDouble{},
		claims: appleauth.Claims{Subject: appleSubject},
		now:    now,
	}
	fixture.service = auth.NewAppleService(
		appleVerifierDouble{fixture: fixture},
		fixture.store,
		fixture.issuer,
		nil,
		func() time.Time { return fixture.now },
	)
	return fixture
}

type appleVerifierDouble struct {
	fixture *appleServiceFixture
}

func (v appleVerifierDouble) Verify(
	_ context.Context,
	_ string,
	_ string,
) (appleauth.Claims, error) {
	if v.fixture.verifyErr != nil {
		return appleauth.Claims{}, v.fixture.verifyErr
	}
	return v.fixture.claims, nil
}

type appleStoreDouble struct {
	resolved        auth.AppleIdentity
	resolveCalls    int
	linked          auth.AppleIdentity
	linkCalls       int
	linkErr         error
	lookedUpByEmail bool
}

func (s *appleStoreDouble) ResolveAppleIdentity(
	_ context.Context,
	identity auth.AppleIdentity,
) (auth.ID, error) {
	s.resolveCalls++
	s.resolved = identity
	return identity.UserID, nil
}

func (s *appleStoreDouble) LinkAppleIdentity(
	_ context.Context,
	identity auth.AppleIdentity,
) error {
	s.linkCalls++
	if s.linkErr != nil {
		return s.linkErr
	}
	s.linked = identity
	return nil
}

type appleIssuerDouble struct {
	issuedFor  string
	issueCalls int
}

func (i *appleIssuerDouble) Issue(
	_ context.Context,
	userID string,
	_ auth.DeviceMetadata,
	now time.Time,
) (auth.SessionTokens, error) {
	i.issueCalls++
	i.issuedFor = userID
	return auth.SessionTokens{
		AccessToken:  "access",
		RefreshToken: "refresh",
		UserID:       userID,
		SessionID:    "22222222-2222-4222-8222-222222222222",
		RecentAuthAt: now,
	}, nil
}

func (i *appleIssuerDouble) RevokeAll(_ context.Context, _ string, _ string) error {
	return nil
}

func assertAuthCode(t *testing.T, err error, want auth.ErrorCode) {
	t.Helper()
	var authError *auth.Error
	if !errors.As(err, &authError) {
		t.Fatalf("error %v is not an *auth.Error", err)
	}
	if authError.Code != want {
		t.Errorf("error code = %q, want %q", authError.Code, want)
	}
}
