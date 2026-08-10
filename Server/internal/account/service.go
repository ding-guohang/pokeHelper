package account

import (
	"context"
	"errors"
	"fmt"
	"time"

	"porkhelper/server/internal/auth"

	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/password"
	"porkhelper/server/internal/session"
)

// NetworkSignal reuses the auth package's request-scoped network identity so
// both throttles see the same signal.
func NetworkSignal(ctx context.Context) string {
	return auth.NetworkSignal(ctx)
}

// AppleVerifier validates an Apple identity token against an expected nonce.
type AppleVerifier interface {
	Verify(context.Context, string, string) (appleauth.Claims, error)
}

// Throttle limits reauthentication attempts.
//
// Without one, a stolen access token can brute-force the account password at
// wire speed — turning a contained session compromise into a credential
// compromise — and each attempt costs a full Argon2 hash, so it doubles as a
// cheap denial-of-service.
type Throttle interface {
	Check(context.Context, string, string) error
	Consume(context.Context, string, string) error
	ClearAccount(context.Context, string) error
}

type Service struct {
	store    Store
	hasher   password.Hasher
	apple    AppleVerifier
	now      func() time.Time
	window   time.Duration
	throttle Throttle
}

type ServiceOption func(*Service)

func WithThrottle(throttle Throttle) ServiceOption {
	return func(service *Service) {
		service.throttle = throttle
	}
}

func NewService(
	store Store,
	hasher password.Hasher,
	apple AppleVerifier,
	now func() time.Time,
	options ...ServiceOption,
) *Service {
	if now == nil {
		now = time.Now
	}
	service := &Service{
		store:  store,
		hasher: hasher,
		apple:  apple,
		now:    now,
		window: RecentAuthWindow,
	}
	for _, option := range options {
		option(service)
	}
	return service
}

// Reauthenticate proves the account holder is present and refreshes the
// session's recent-authentication timestamp.
//
// The timestamp moves only after a valid proof. A failed attempt leaves the
// session exactly as it was, so a wrong password cannot extend the window.
func (s *Service) Reauthenticate(
	ctx context.Context,
	principal session.Principal,
	proof ReauthenticationProof,
) (time.Time, error) {
	if principal.UserID == "" || principal.SessionID == "" {
		return time.Time{}, &Error{Code: AuthenticationFailed}
	}

	method, err := proof.method()
	if err != nil {
		return time.Time{}, err
	}

	// Keyed by the user, because that is what a stolen token targets. Checked
	// before any hashing so a refused attempt costs nothing.
	if s.throttle != nil {
		if err := s.throttle.Check(ctx, principal.UserID, NetworkSignal(ctx)); err != nil {
			return time.Time{}, err
		}
	}

	switch method {
	case "password":
		if err := s.verifyPassword(ctx, principal.UserID, proof.Password); err != nil {
			return time.Time{}, s.recordFailure(ctx, principal.UserID, err)
		}
	case "apple":
		if err := s.verifyApple(ctx, principal.UserID, proof); err != nil {
			return time.Time{}, s.recordFailure(ctx, principal.UserID, err)
		}
	}

	if s.throttle != nil {
		if err := s.throttle.ClearAccount(ctx, principal.UserID); err != nil {
			return time.Time{}, err
		}
	}

	// The server's clock decides the window; nothing in the request does.
	at := s.now().UTC()
	if err := s.store.MarkRecentAuthentication(
		ctx,
		principal.UserID,
		principal.SessionID,
		at,
	); err != nil {
		return time.Time{}, fmt.Errorf("account: record reauthentication: %w", err)
	}
	return at, nil
}

// Export returns the caller's own data. It requires a recent authentication
// because it reveals the full training history in one response.
func (s *Service) Export(
	ctx context.Context,
	principal session.Principal,
) (ExportDocument, error) {
	if err := RequireRecentAuthentication(principal, s.now(), s.window); err != nil {
		return ExportDocument{}, err
	}
	document, err := s.store.Export(ctx, principal.UserID)
	if err != nil {
		return ExportDocument{}, err
	}
	document.SchemaVersion = ExportSchemaVersion
	return document, nil
}

// Delete removes the account. It requires a recent authentication and is not
// reversible.
func (s *Service) Delete(ctx context.Context, principal session.Principal) error {
	if err := RequireRecentAuthentication(principal, s.now(), s.window); err != nil {
		return err
	}
	return s.store.Delete(ctx, principal.UserID)
}

// recordFailure counts a failed proof, preferring the throttle's own error
// (which carries retry-after) when the attempt exhausted the budget.
func (s *Service) recordFailure(ctx context.Context, userID string, cause error) error {
	if s.throttle == nil {
		return cause
	}
	if err := s.throttle.Consume(ctx, userID, NetworkSignal(ctx)); err != nil {
		return err
	}
	return cause
}

func (s *Service) verifyPassword(
	ctx context.Context,
	userID string,
	candidate string,
) error {
	phc, found, err := s.store.PasswordHash(ctx, userID)
	if err != nil {
		return fmt.Errorf("account: lookup password credential: %w", err)
	}
	if !found {
		return &Error{Code: AuthenticationFailed}
	}
	valid, _, verifyErr := s.hasher.Verify(phc, candidate)
	if verifyErr != nil || !valid {
		return &Error{Code: AuthenticationFailed}
	}
	return nil
}

func (s *Service) verifyApple(
	ctx context.Context,
	userID string,
	proof ReauthenticationProof,
) error {
	if s.apple == nil {
		return errors.New("account: apple verifier is required")
	}
	claims, err := s.apple.Verify(ctx, proof.AppleIdentityToken, proof.AppleNonce)
	if err != nil {
		return &Error{Code: AuthenticationFailed, Err: err}
	}

	// A valid Apple credential proves someone owns that Apple account, not
	// that they own this one. The subject must already be linked here.
	owned, err := s.store.HasAppleSubject(ctx, userID, claims.Subject)
	if err != nil {
		return fmt.Errorf("account: check apple subject ownership: %w", err)
	}
	if !owned {
		return &Error{Code: AuthenticationFailed}
	}
	return nil
}
