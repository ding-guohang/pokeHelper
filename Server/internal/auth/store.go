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
	CreatePasswordResetChallenge(
		context.Context,
		string,
		PasswordResetChallenge,
	) (PasswordResetDelivery, bool, error)
	ReplacePassword(
		context.Context,
		[32]byte,
		string,
		time.Time,
		func(context.Context, string) error,
	) error
	ThrottleStore
}
