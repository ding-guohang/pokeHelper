package auth

import (
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
	ValidationFailed     ErrorCode = "validationFailed"
	ChallengeInvalid     ErrorCode = "challengeInvalid"
	AuthenticationFailed ErrorCode = "authenticationFailed"
	RateLimited          ErrorCode = "rateLimited"
)

type Error struct {
	Code       ErrorCode
	RetryAfter time.Duration
	Err        error
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

func (id ID) String() string {
	return fmt.Sprintf(
		"%08x-%04x-%04x-%04x-%012x",
		id[0:4],
		id[4:6],
		id[6:8],
		id[8:10],
		id[10:16],
	)
}

type DeviceMetadata struct {
	DeviceID    string `json:"deviceID"`
	DisplayName string `json:"displayName"`
	Platform    string `json:"platform"`
}

type SessionTokens struct {
	AccessToken      string    `json:"accessToken"`
	RefreshToken     string    `json:"refreshToken"`
	AccessExpiresAt  time.Time `json:"accessExpiresAt"`
	RefreshExpiresAt time.Time `json:"refreshExpiresAt"`
	UserID           string    `json:"userID"`
	SessionID        string    `json:"sessionID"`
	RecentAuthAt     time.Time `json:"recentAuthAt"`
}

type LoginInput struct {
	Email    string         `json:"email"`
	Password string         `json:"password"`
	Device   DeviceMetadata `json:"device"`
}

type LoginResult SessionTokens

type LoginCredential struct {
	UserID      ID
	PasswordPHC string
	Verified    bool
	Found       bool
}

type PasswordResetChallenge struct {
	ChallengeID ID
	TokenHash   [32]byte
	Purpose     string
	IssuedAt    time.Time
	ExpiresAt   time.Time
}

type PasswordResetDelivery struct {
	DisplayEmail string
}

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
