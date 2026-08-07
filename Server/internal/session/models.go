package session

import (
	"fmt"
	"time"
)

type ErrorCode string

const (
	ValidationFailed ErrorCode = "validationFailed"
	Unauthenticated  ErrorCode = "unauthenticated"
	NotFound         ErrorCode = "notFound"
)

type Error struct {
	Code ErrorCode
	Err  error
}

func (e *Error) Error() string {
	return fmt.Sprintf("session: %s", e.Code)
}

func (e *Error) Unwrap() error {
	return e.Err
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

// DeviceMetadata describes the calling installation. DeviceID is the
// installation-scoped identifier supplied by the client; the server maps it to
// its own device row and never treats it as an authorization claim.
type DeviceMetadata struct {
	DeviceID    string `json:"deviceID"`
	DisplayName string `json:"displayName"`
	Platform    string `json:"platform"`
	AppVersion  string `json:"appVersion"`
}

type TokenPair struct {
	AccessToken      string    `json:"accessToken"`
	RefreshToken     string    `json:"refreshToken"`
	AccessExpiresAt  time.Time `json:"accessExpiresAt"`
	RefreshExpiresAt time.Time `json:"refreshExpiresAt"`
	UserID           string    `json:"userID"`
	SessionID        string    `json:"sessionID"`
	RecentAuthAt     time.Time `json:"recentAuthAt"`
}

// Principal carries only server-derived identity. Handlers must build it from
// the bearer session and never from request bodies or query parameters.
type Principal struct {
	UserID       string
	SessionID    string
	DeviceID     string
	RecentAuthAt time.Time
}

type DeviceSession struct {
	SessionID    string    `json:"sessionID"`
	DeviceID     string    `json:"deviceID"`
	DisplayName  string    `json:"displayName"`
	Platform     string    `json:"platform"`
	AppVersion   string    `json:"appVersion"`
	CreatedAt    time.Time `json:"createdAt"`
	LastActiveAt time.Time `json:"lastActiveAt"`
	Current      bool      `json:"current"`
}

// NewSession is the complete row set a store must persist atomically. It holds
// token hashes only; plaintext tokens never leave the manager.
type NewSession struct {
	SessionID        ID
	TokenFamilyID    ID
	RefreshTokenID   ID
	UserID           string
	Device           DeviceMetadata
	AccessHash       [32]byte
	RefreshHash      [32]byte
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
	RecentAuthAt     time.Time
	Now              time.Time
}

// Rotation asks a store to consume PresentedHash and install the replacement
// hashes in the same transaction.
type Rotation struct {
	PresentedHash    [32]byte
	RefreshTokenID   ID
	AccessHash       [32]byte
	RefreshHash      [32]byte
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
	Now              time.Time
}

// RotationOutcome reports the result of a rotation attempt. Replayed means the
// presented token was already consumed or revoked, and the store has revoked
// the whole token family as a result.
type RotationOutcome struct {
	UserID       string
	SessionID    string
	RecentAuthAt time.Time
	Replayed     bool
}
