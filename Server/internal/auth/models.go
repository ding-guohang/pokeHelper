package auth

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
	"golang.org/x/text/unicode/norm"
)

type ErrorCode string

const (
	ValidationFailed ErrorCode = "validationFailed"
	ChallengeInvalid ErrorCode = "challengeInvalid"
)

type Error struct {
	Code ErrorCode
	Err  error
}

func (e *Error) Error() string {
	return fmt.Sprintf("auth: %s", e.Code)
}

func (e *Error) Unwrap() error {
	return e.Err
}

type Email struct {
	Display   string
	Canonical string
}

type RegisterInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type Accepted struct {
	Accepted bool `json:"accepted"`
}

type ID [16]byte

type Registration struct {
	UserID        ID
	IdentityID    ID
	ChallengeID   ID
	Email         Email
	PasswordPHC   string
	PasswordAt    time.Time
	ChallengeHash [32]byte
	Purpose       string
	ExpiresAt     time.Time
}

type Store interface {
	CreateRegistration(context.Context, Registration) (bool, error)
	ConsumeEmailChallenge(context.Context, [32]byte, time.Time) error
}

func NormalizeEmail(raw string) (Email, error) {
	if !utf8.ValidString(raw) {
		return Email{}, &Error{Code: ValidationFailed}
	}
	display := norm.NFC.String(strings.TrimSpace(raw))
	if display == "" {
		return Email{}, &Error{Code: ValidationFailed}
	}
	for _, value := range display {
		if unicode.IsControl(value) || unicode.IsSpace(value) {
			return Email{}, &Error{Code: ValidationFailed}
		}
	}
	if strings.Count(display, "@") != 1 {
		return Email{}, &Error{Code: ValidationFailed}
	}
	local, domain, _ := strings.Cut(display, "@")
	if local == "" || domain == "" {
		return Email{}, &Error{Code: ValidationFailed}
	}
	canonical := norm.NFC.String(cases.Lower(language.Und).String(display))
	if len(display) > 254 || len(canonical) > 254 {
		return Email{}, &Error{Code: ValidationFailed}
	}
	return Email{Display: display, Canonical: canonical}, nil
}
