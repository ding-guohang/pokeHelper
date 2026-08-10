package account

import (
	"context"
	"time"
)

type Store interface {
	// PasswordHash returns the stored PHC string for a user, if the account
	// has a password credential at all.
	PasswordHash(context.Context, string) (string, bool, error)

	// HasAppleSubject reports whether the Apple subject belongs to this user.
	HasAppleSubject(context.Context, string, string) (bool, error)

	// MarkRecentAuthentication records a fresh proof on one session. Only the
	// session that proved presence is refreshed, so proving on a phone does
	// not silently unlock a destructive action queued on a tablet.
	MarkRecentAuthentication(context.Context, string, string, time.Time) error

	Export(context.Context, string) (ExportDocument, error)

	// Delete removes the account and everything reachable from it in one
	// transaction.
	Delete(context.Context, string) error
}
