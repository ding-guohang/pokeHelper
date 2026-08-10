package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"time"

	"porkhelper/server/internal/mail"
	"porkhelper/server/internal/password"
)

type Service struct {
	store         Store
	policy        password.Policy
	hasher        password.Hasher
	mailer        mail.Mailer
	random        io.Reader
	now           func() time.Time
	throttle      *Throttle
	sessionIssuer SessionIssuer
}

type ServiceOption func(*Service)

func WithThrottle(throttle *Throttle) ServiceOption {
	return func(service *Service) {
		service.throttle = throttle
	}
}

func WithSessionIssuer(issuer SessionIssuer) ServiceOption {
	return func(service *Service) {
		service.sessionIssuer = issuer
	}
}

func NewService(
	store Store,
	policy password.Policy,
	hasher password.Hasher,
	mailer mail.Mailer,
	random io.Reader,
	now func() time.Time,
	options ...ServiceOption,
) *Service {
	if random == nil {
		random = rand.Reader
	}
	if now == nil {
		now = time.Now
	}
	service := &Service{
		store: store, policy: policy, hasher: hasher, mailer: mailer,
		random: random, now: now,
	}
	for _, option := range options {
		option(service)
	}
	return service
}

func (s *Service) Register(ctx context.Context, input RegisterInput) (Accepted, error) {
	email, err := NormalizeEmail(input.Email)
	if err != nil {
		if s.throttle != nil {
			if throttleErr := s.throttle.ConsumeInvalidAccount(
				ctx,
				input.Email,
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
	normalizedPassword, err := s.policy.NormalizeAndValidate(input.Password)
	if err != nil {
		return Accepted{}, &Error{Code: ValidationFailed}
	}
	passwordPHC, err := s.hasher.Hash(normalizedPassword)
	if err != nil {
		return Accepted{}, fmt.Errorf("auth: hash password: %w", err)
	}

	userID, err := s.randomID()
	if err != nil {
		return Accepted{}, err
	}
	identityID, err := s.randomID()
	if err != nil {
		return Accepted{}, err
	}
	challengeID, err := s.randomID()
	if err != nil {
		return Accepted{}, err
	}
	tokenBytes := make([]byte, 32)
	if _, err := io.ReadFull(s.random, tokenBytes); err != nil {
		return Accepted{}, fmt.Errorf("auth: generate verification token: %w", err)
	}
	rawToken := base64.RawURLEncoding.EncodeToString(tokenBytes)
	tokenHash := sha256.Sum256([]byte(rawToken))
	now := s.now().UTC()

	created, err := s.store.CreateRegistration(ctx, Registration{
		UserID:        userID,
		IdentityID:    identityID,
		ChallengeID:   challengeID,
		Email:         email,
		PasswordPHC:   passwordPHC,
		PasswordAt:    now,
		ChallengeHash: tokenHash,
		Purpose:       verificationPurpose,
		ExpiresAt:     now.Add(24 * time.Hour),
	})
	if err != nil {
		return Accepted{}, fmt.Errorf("auth: create registration: %w", err)
	}
	accepted := Accepted{Accepted: true}
	if !created {
		return accepted, nil
	}
	if err := s.mailer.Deliver(ctx, mail.Message{
		To:      email.Display,
		Subject: "Verify your email",
		Body:    rawToken,
	}); err != nil {
		return Accepted{}, fmt.Errorf("auth: deliver verification email: %w", err)
	}
	return accepted, nil
}

func (s *Service) VerifyEmail(ctx context.Context, rawToken string) error {
	tokenHash := sha256.Sum256([]byte(rawToken))
	if err := s.store.ConsumeEmailChallenge(ctx, tokenHash, s.now().UTC()); err != nil {
		if s.throttle != nil {
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

func (s *Service) randomID() (ID, error) {
	return newRandomID(s.random)
}

// ResendVerification issues a fresh verification email for an account that has
// not been verified yet.
//
// Like registration, it always reports accepted: telling the caller whether the
// address exists or is already verified would be an enumeration oracle.
func (s *Service) ResendVerification(ctx context.Context, rawEmail string) (Accepted, error) {
	accepted := Accepted{Accepted: true}

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
		return accepted, nil
	}
	if s.throttle != nil {
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
		return Accepted{}, fmt.Errorf("auth: generate verification token: %w", err)
	}
	rawToken := base64.RawURLEncoding.EncodeToString(tokenBytes)
	tokenHash := sha256.Sum256([]byte(rawToken))
	now := s.now().UTC()

	delivery, created, err := s.store.CreateVerificationChallenge(ctx, email.Canonical, PasswordResetChallenge{
		ChallengeID: challengeID,
		TokenHash:   tokenHash,
		Purpose:     verificationPurpose,
		IssuedAt:    now,
		ExpiresAt:   now.Add(24 * time.Hour),
	})
	if err != nil {
		return Accepted{}, fmt.Errorf("auth: create verification challenge: %w", err)
	}
	if !created {
		return accepted, nil
	}

	if err := s.mailer.Deliver(ctx, mail.Message{
		To:      delivery.DisplayEmail,
		Subject: "验证你的手牌教练账号",
		Body:    rawToken,
	}); err != nil {
		// Delivery failure must not change the response, or the difference
		// would itself reveal that the address exists.
		return accepted, nil
	}
	return accepted, nil
}
