package account

import (
	"context"
	"errors"
	"fmt"
	"time"

	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/password"
	"porkhelper/server/internal/session"
)

// AppleVerifier validates an Apple identity token against an expected nonce.
type AppleVerifier interface {
	Verify(context.Context, string, string) (appleauth.Claims, error)
}

type Service struct {
	store  Store
	hasher password.Hasher
	apple  AppleVerifier
	now    func() time.Time
	window time.Duration
}

func NewService(
	store Store,
	hasher password.Hasher,
	apple AppleVerifier,
	now func() time.Time,
) *Service {
	if now == nil {
		now = time.Now
	}
	return &Service{
		store:  store,
		hasher: hasher,
		apple:  apple,
		now:    now,
		window: RecentAuthWindow,
	}
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

	switch method {
	case "password":
		if err := s.verifyPassword(ctx, principal.UserID, proof.Password); err != nil {
			return time.Time{}, err
		}
	case "apple":
		if err := s.verifyApple(ctx, principal.UserID, proof); err != nil {
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
