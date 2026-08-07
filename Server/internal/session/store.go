package session

import (
	"context"
	"time"
)

// Store persists sessions, devices, and the refresh-token history used to
// detect replay. Every method is scoped by a server-derived user ID.
type Store interface {
	// CreateSession persists the device, session, and first refresh token in
	// one transaction.
	CreateSession(context.Context, NewSession) error

	// AuthenticateAccess resolves a live access-token hash to its principal.
	AuthenticateAccess(context.Context, [32]byte, time.Time) (Principal, error)

	// RotateRefresh consumes the presented refresh hash and installs the
	// replacements atomically. A presented token that is already consumed or
	// revoked must revoke the entire token family and report Replayed.
	RotateRefresh(context.Context, Rotation) (RotationOutcome, error)

	// RevokeByRefresh revokes the session owning the presented refresh hash.
	RevokeByRefresh(context.Context, [32]byte, time.Time) error

	// ListDevices returns the live device sessions owned by the user.
	ListDevices(context.Context, string, time.Time) ([]DeviceSession, error)

	// RevokeSession revokes one session owned by the user. A session that the
	// user does not own must report NotFound rather than revoking anything.
	RevokeSession(context.Context, string, string, time.Time) error

	// RevokeAllForUser revokes every session of the user, optionally sparing
	// one session ID.
	RevokeAllForUser(context.Context, string, string, time.Time) error
}
