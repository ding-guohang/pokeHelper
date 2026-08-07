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
		return Accepted{}, err
	}
	if s.throttle != nil {
		if err := s.throttle.Consume(ctx, email.Canonical, NetworkSignal(ctx)); err != nil {
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
			if throttleErr := s.throttle.Consume(ctx, rawToken, NetworkSignal(ctx)); throttleErr != nil {
				return throttleErr
			}
		}
		return err
	}
	return nil
}

func (s *Service) randomID() (ID, error) {
	var id ID
	if _, err := io.ReadFull(s.random, id[:]); err != nil {
		return ID{}, fmt.Errorf("auth: generate id: %w", err)
	}
	return id, nil
}
