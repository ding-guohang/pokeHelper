package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"golang.org/x/text/unicode/norm"
)

const dummyPasswordPHC = "$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

type SessionIssuer interface {
	Issue(context.Context, string, DeviceMetadata, time.Time) (SessionTokens, error)
	RevokeAll(context.Context, string, string) error
}

func (s *Service) Login(ctx context.Context, input LoginInput) (LoginResult, error) {
	email, err := NormalizeEmail(input.Email)
	if err != nil {
		if s.throttle != nil {
			if throttleErr := s.throttle.ConsumeInvalidAccount(
				ctx,
				input.Email,
				NetworkSignal(ctx),
			); throttleErr != nil {
				return LoginResult{}, throttleErr
			}
		}
		return LoginResult{}, &Error{Code: AuthenticationFailed}
	}
	if s.throttle != nil {
		if err := s.throttle.Check(ctx, email.Canonical, NetworkSignal(ctx)); err != nil {
			return LoginResult{}, err
		}
	}

	credential, err := s.store.LookupLoginCredential(ctx, email.Canonical)
	if err != nil {
		return LoginResult{}, fmt.Errorf("auth: lookup login credential: %w", err)
	}
	phc := credential.PasswordPHC
	if !credential.Found {
		phc = dummyPasswordPHC
	}
	valid, needsUpgrade, verifyErr := s.hasher.Verify(phc, input.Password)
	if verifyErr != nil {
		valid = false
		needsUpgrade = false
	}
	if !credential.Found || !credential.Verified || !valid {
		if s.throttle != nil {
			if err := s.throttle.Consume(ctx, email.Canonical, NetworkSignal(ctx)); err != nil {
				return LoginResult{}, err
			}
		}
		return LoginResult{}, &Error{Code: AuthenticationFailed}
	}
	if needsUpgrade {
		upgradedPHC, err := s.hasher.Hash(norm.NFC.String(input.Password))
		if err != nil {
			return LoginResult{}, fmt.Errorf("auth: upgrade password hash: %w", err)
		}
		if err := s.store.UpgradePasswordCredential(
			ctx,
			credential.UserID,
			credential.PasswordPHC,
			upgradedPHC,
			s.now().UTC(),
		); err != nil {
			return LoginResult{}, fmt.Errorf("auth: store upgraded password hash: %w", err)
		}
	}

	if s.sessionIssuer == nil {
		return LoginResult{}, errors.New("auth: session issuer is required")
	}
	if s.throttle != nil {
		if err := s.throttle.ClearAccount(ctx, email.Canonical); err != nil {
			return LoginResult{}, err
		}
	}
	now := s.now().UTC()
	tokens, err := s.sessionIssuer.Issue(
		ctx,
		credential.UserID.String(),
		input.Device,
		now,
	)
	if err != nil {
		return LoginResult{}, fmt.Errorf("auth: issue session: %w", err)
	}
	return LoginResult(tokens), nil
}
