package auth

import (
	"context"
	"time"
)

const verificationPurpose = "verifyEmail"

type Store interface {
	CreateRegistration(context.Context, Registration) (bool, error)
	ConsumeEmailChallenge(context.Context, [32]byte, time.Time) error
	LookupLoginCredential(context.Context, string) (LoginCredential, error)
	UpgradePasswordCredential(context.Context, ID, string, string, time.Time) error
	// CreateVerificationChallenge re-issues an email verification challenge for
	// an account that exists but is not yet verified. Reports created=false for
	// an unknown or already-verified address so the caller stays
	// enumeration-safe.
	CreateVerificationChallenge(
		context.Context,
		string,
		PasswordResetChallenge,
	) (PasswordResetDelivery, bool, error)

	CreatePasswordResetChallenge(
		context.Context,
		string,
		PasswordResetChallenge,
	) (PasswordResetDelivery, bool, error)
	ReplacePassword(
		context.Context,
		[32]byte,
		time.Time,
		func() (string, error),
		func(context.Context, string) error,
	) error
	ThrottleStore
}
