package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"time"

	"porkhelper/server/internal/appleauth"
)

// RecentAuthWindow is how long a completed authentication keeps a principal
// eligible for sensitive operations such as linking a new identity.
const RecentAuthWindow = 10 * time.Minute

const appleProvider = "apple"

// Principal is the auth package's own view of an authenticated caller.
//
// It deliberately does not reuse session.Principal: the session package
// already imports auth to implement SessionIssuer, so importing session here
// would create a cycle. The HTTP layer owns the conversion, the same way it
// already does for DeviceMetadata and SessionTokens.
type Principal struct {
	UserID       string
	SessionID    string
	RecentAuthAt time.Time
}

type AppleSignInInput struct {
	IdentityToken string         `json:"identityToken"`
	Nonce         string         `json:"nonce"`
	Device        DeviceMetadata `json:"device"`
}

type AppleLinkInput struct {
	IdentityToken string `json:"identityToken"`
	Nonce         string `json:"nonce"`
}

// AppleVerifier validates an Apple identity token against an expected nonce.
type AppleVerifier interface {
	Verify(context.Context, string, string) (appleauth.Claims, error)
}

// AppleIdentity is the record a store persists for one Apple subject.
// CanonicalEmail is stored for later export only; it is never used to find or
// merge an account.
type AppleIdentity struct {
	IdentityID     ID
	UserID         ID
	Subject        string
	CanonicalEmail string
	EmailVerified  bool
	Now            time.Time
}

type AppleStore interface {
	// ResolveAppleIdentity returns the user bound to the Apple subject,
	// creating an independent user when the subject is unknown. Implementations
	// must key on the subject alone and must never match on email.
	ResolveAppleIdentity(context.Context, AppleIdentity) (ID, error)

	// LinkAppleIdentity binds an Apple subject to an existing user. A subject
	// already bound to a different user must fail with IdentityConflict.
	LinkAppleIdentity(context.Context, AppleIdentity) error
}

type AppleService struct {
	verifier      AppleVerifier
	store         AppleStore
	sessionIssuer SessionIssuer
	random        io.Reader
	now           func() time.Time
}

func NewAppleService(
	verifier AppleVerifier,
	store AppleStore,
	sessionIssuer SessionIssuer,
	random io.Reader,
	now func() time.Time,
) *AppleService {
	if random == nil {
		random = rand.Reader
	}
	if now == nil {
		now = time.Now
	}
	return &AppleService{
		verifier:      verifier,
		store:         store,
		sessionIssuer: sessionIssuer,
		random:        random,
		now:           now,
	}
}

// SignIn authenticates an Apple credential and maps its subject to a stable
// user. A credential that fails verification creates no user, no identity, and
// no session.
func (s *AppleService) SignIn(
	ctx context.Context,
	input AppleSignInInput,
) (LoginResult, error) {
	if input.Device.DeviceID == "" {
		return LoginResult{}, &Error{Code: ValidationFailed}
	}

	claims, err := s.verify(ctx, input.IdentityToken, input.Nonce)
	if err != nil {
		return LoginResult{}, err
	}

	identity, err := s.newIdentity(claims)
	if err != nil {
		return LoginResult{}, err
	}

	userID, err := s.store.ResolveAppleIdentity(ctx, identity)
	if err != nil {
		return LoginResult{}, err
	}

	if s.sessionIssuer == nil {
		return LoginResult{}, errors.New("auth: session issuer is required")
	}
	tokens, err := s.sessionIssuer.Issue(ctx, userID.String(), input.Device, s.now().UTC())
	if err != nil {
		return LoginResult{}, fmt.Errorf("auth: issue apple session: %w", err)
	}
	return LoginResult(tokens), nil
}

// Link binds an Apple identity to the caller's existing account. Because this
// is how an email account and an Apple account become one user, it requires a
// recent authentication rather than merely a live session.
func (s *AppleService) Link(
	ctx context.Context,
	principal Principal,
	input AppleLinkInput,
) error {
	if principal.UserID == "" {
		return &Error{Code: AuthenticationFailed}
	}
	if !s.withinRecentAuthWindow(principal) {
		return &Error{Code: ReauthenticationRequired}
	}

	claims, err := s.verify(ctx, input.IdentityToken, input.Nonce)
	if err != nil {
		return err
	}

	identity, err := s.newIdentity(claims)
	if err != nil {
		return err
	}
	if identity.UserID, err = parseID(principal.UserID); err != nil {
		return err
	}

	return s.store.LinkAppleIdentity(ctx, identity)
}

func (s *AppleService) withinRecentAuthWindow(principal Principal) bool {
	if principal.RecentAuthAt.IsZero() {
		return false
	}
	elapsed := s.now().UTC().Sub(principal.RecentAuthAt.UTC())
	return elapsed >= 0 && elapsed <= RecentAuthWindow
}

// verify collapses every appleauth rejection into one generic failure so the
// response cannot be used to probe which check failed.
func (s *AppleService) verify(
	ctx context.Context,
	identityToken string,
	nonce string,
) (appleauth.Claims, error) {
	if s.verifier == nil {
		return appleauth.Claims{}, errors.New("auth: apple verifier is required")
	}
	claims, err := s.verifier.Verify(ctx, identityToken, nonce)
	if err != nil {
		var appleError *appleauth.Error
		if errors.As(err, &appleError) {
			return appleauth.Claims{}, &Error{Code: AuthenticationFailed, Err: err}
		}
		return appleauth.Claims{}, fmt.Errorf("auth: verify apple credential: %w", err)
	}
	if claims.Subject == "" {
		return appleauth.Claims{}, &Error{Code: AuthenticationFailed}
	}
	return claims, nil
}

func (s *AppleService) newIdentity(claims appleauth.Claims) (AppleIdentity, error) {
	identityID, err := newRandomID(s.random)
	if err != nil {
		return AppleIdentity{}, err
	}
	userID, err := newRandomID(s.random)
	if err != nil {
		return AppleIdentity{}, err
	}

	canonicalEmail := ""
	if claims.Email != "" {
		email, err := NormalizeEmail(claims.Email)
		if err == nil {
			canonicalEmail = email.Canonical
		}
	}

	return AppleIdentity{
		IdentityID:     identityID,
		UserID:         userID,
		Subject:        claims.Subject,
		CanonicalEmail: canonicalEmail,
		EmailVerified:  claims.EmailVerified,
		Now:            s.now().UTC(),
	}, nil
}
