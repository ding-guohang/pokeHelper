package account

import (
	"encoding/json"
	"fmt"
	"time"

	"porkhelper/server/internal/session"
)

// RecentAuthWindow is how long a completed authentication keeps a session
// eligible for destructive or data-revealing operations.
const RecentAuthWindow = 10 * time.Minute

// ExportSchemaVersion versions the export document so a future format change
// is recognizable in files users already downloaded.
const ExportSchemaVersion = 1

type ErrorCode string

const (
	ValidationFailed         ErrorCode = "validationFailed"
	AuthenticationFailed     ErrorCode = "authenticationFailed"
	ReauthenticationRequired ErrorCode = "reauthenticationRequired"
)

type Error struct {
	Code ErrorCode
	Err  error
}

func (e *Error) Error() string {
	return fmt.Sprintf("account: %s", e.Code)
}

func (e *Error) Unwrap() error {
	return e.Err
}

// ReauthenticationProof is how a caller proves they are still present. Exactly
// one method must be supplied.
type ReauthenticationProof struct {
	Password           string `json:"password"`
	AppleIdentityToken string `json:"appleIdentityToken"`
	AppleNonce         string `json:"appleNonce"`
}

func (p ReauthenticationProof) method() (string, error) {
	hasPassword := p.Password != ""
	hasApple := p.AppleIdentityToken != ""
	switch {
	case hasPassword && !hasApple:
		return "password", nil
	case hasApple && !hasPassword:
		return "apple", nil
	default:
		return "", &Error{Code: ValidationFailed}
	}
}

// ExportDocument is the structured copy of a user's own data.
//
// It carries no password hash, refresh or access token hash, challenge hash, or
// throttle state. Those are credential material: including them would turn a
// convenience feature into a way to exfiltrate secrets.
type ExportDocument struct {
	SchemaVersion int               `json:"schemaVersion"`
	Account       ExportAccount     `json:"account"`
	Devices       []ExportDevice    `json:"devices"`
	Events        []json.RawMessage `json:"events"`
}

type ExportAccount struct {
	UserID     string           `json:"userID"`
	CreatedAt  time.Time        `json:"createdAt"`
	Identities []ExportIdentity `json:"identities"`
}

type ExportIdentity struct {
	Provider      string `json:"provider"`
	Email         string `json:"email,omitempty"`
	EmailVerified bool   `json:"emailVerified"`
}

type ExportDevice struct {
	DisplayName string    `json:"displayName"`
	Platform    string    `json:"platform"`
	AppVersion  string    `json:"appVersion"`
	CreatedAt   time.Time `json:"createdAt"`
	LastSeenAt  time.Time `json:"lastSeenAt"`
}

// RequireRecentAuthentication gates operations that reveal or destroy data.
//
// The window is measured against the server-derived RecentAuthAt on the bearer
// session. A client cannot widen it, because nothing in the request
// contributes to this decision.
func RequireRecentAuthentication(
	principal session.Principal,
	now time.Time,
	window time.Duration,
) error {
	if principal.UserID == "" {
		return &Error{Code: AuthenticationFailed}
	}
	if principal.RecentAuthAt.IsZero() {
		return &Error{Code: ReauthenticationRequired}
	}
	elapsed := now.UTC().Sub(principal.RecentAuthAt.UTC())
	if elapsed < 0 || elapsed > window {
		return &Error{Code: ReauthenticationRequired}
	}
	return nil
}
