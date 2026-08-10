package auth

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"time"

	"porkhelper/server/internal/mail"
)

const resetPasswordPurpose = "resetPassword"

func (s *Service) RequestPasswordReset(
	ctx context.Context,
	rawEmail string,
) (Accepted, error) {
	email, err := NormalizeEmail(rawEmail)
	if err != nil {
		if s.throttle != nil {
			if throttleErr := s.throttle.ConsumeInvalidAccount(
				ctx,
				rawEmail,
				NetworkSignal(ctx),
			); throttleErr != nil {
				return Accepted{}, throttleErr
			}
		}
		return Accepted{}, err
	}
	if s.throttle != nil {
		// Counted against the signup bucket, not the login bucket: an
		// unauthenticated caller must not be able to lock the owner out.
		if err := s.throttle.ConsumeSignup(ctx, email.Canonical, NetworkSignal(ctx)); err != nil {
			return Accepted{}, err
		}
	}

	challengeID, err := s.randomID()
	if err != nil {
		return Accepted{}, err
	}
	tokenBytes := make([]byte, 32)
	if _, err := io.ReadFull(s.random, tokenBytes); err != nil {
		return Accepted{}, fmt.Errorf("auth: generate reset token: %w", err)
	}
	rawToken := base64.RawURLEncoding.EncodeToString(tokenBytes)
	tokenHash := sha256.Sum256([]byte(rawToken))
	now := s.now().UTC()
	delivery, created, err := s.store.CreatePasswordResetChallenge(
		ctx,
		email.Canonical,
		PasswordResetChallenge{
			ChallengeID: challengeID,
			TokenHash:   tokenHash,
			Purpose:     resetPasswordPurpose,
			IssuedAt:    now,
			ExpiresAt:   now.Add(time.Hour),
		},
	)
	if err != nil {
		return Accepted{}, fmt.Errorf("auth: create password reset: %w", err)
	}
	accepted := Accepted{Accepted: true}
	if !created {
		return accepted, nil
	}
	if err := s.mailer.Deliver(ctx, mail.Message{
		To:      delivery.DisplayEmail,
		Subject: "Reset your password",
		Body:    rawToken,
	}); err != nil {
		// The challenge is already committed. Keep the response enumeration-safe;
		// a later request supersedes this undelivered challenge.
		return accepted, nil
	}
	return accepted, nil
}

func (s *Service) ConfirmPasswordReset(
	ctx context.Context,
	rawToken string,
	rawPassword string,
) error {
	if s.throttle != nil {
		if err := s.throttle.CheckChallenge(ctx, rawToken, NetworkSignal(ctx)); err != nil {
			return err
		}
	}
	normalizedPassword, err := s.policy.NormalizeAndValidate(rawPassword)
	if err != nil {
		return &Error{Code: ValidationFailed}
	}
	tokenHash := sha256.Sum256([]byte(rawToken))
	err = s.store.ReplacePassword(
		ctx,
		tokenHash,
		s.now().UTC(),
		func() (string, error) {
			passwordPHC, err := s.hasher.Hash(normalizedPassword)
			if err != nil {
				return "", fmt.Errorf("auth: hash replacement password: %w", err)
			}
			return passwordPHC, nil
		},
		func(ctx context.Context, userID string) error {
			if s.sessionIssuer == nil {
				return errors.New("auth: session issuer is required")
			}
			return s.sessionIssuer.RevokeAll(ctx, userID, "passwordReset")
		},
	)
	if err != nil {
		var authError *Error
		if s.throttle != nil &&
			errors.As(err, &authError) &&
			authError.Code == ChallengeInvalid {
			if throttleErr := s.throttle.ConsumeChallenge(
				ctx,
				rawToken,
				NetworkSignal(ctx),
			); throttleErr != nil {
				return throttleErr
			}
		}
		return err
	}
	return nil
}
