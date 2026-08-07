package auth

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"fmt"
	"time"
)

type signalDomain string

const (
	accountSignalDomain signalDomain = "account"
	networkSignalDomain signalDomain = "network"

	throttleWindow = 15 * time.Minute
	accountLimit   = uint32(5)
	networkLimit   = uint32(25)
)

type ThrottleKeys struct {
	Account [32]byte
	Network [32]byte
}

type ThrottleLimits struct {
	Account uint32
	Network uint32
	Window  time.Duration
	Block   time.Duration
}

type ThrottleStore interface {
	CheckAuthThrottles(context.Context, ThrottleKeys, time.Time) (time.Time, error)
	ConsumeAuthThrottles(
		context.Context,
		ThrottleKeys,
		time.Time,
		ThrottleLimits,
	) (time.Time, error)
	ClearAuthAccountThrottle(context.Context, [32]byte) error
}

type Throttle struct {
	store  ThrottleStore
	secret [32]byte
	now    func() time.Time
}

func NewThrottle(
	store ThrottleStore,
	secret []byte,
	now func() time.Time,
) (*Throttle, error) {
	if store == nil {
		return nil, errors.New("auth: throttle store is required")
	}
	if len(secret) != sha256.Size {
		return nil, errors.New("auth: throttle secret must be exactly 32 bytes")
	}
	if now == nil {
		now = time.Now
	}
	throttle := &Throttle{store: store, now: now}
	copy(throttle.secret[:], secret)
	return throttle, nil
}

func (t *Throttle) Check(
	ctx context.Context,
	accountSignal string,
	networkSignal string,
) error {
	now := t.now().UTC()
	retryAt, err := t.store.CheckAuthThrottles(
		ctx,
		t.keys(accountSignal, networkSignal),
		now,
	)
	if err != nil {
		return fmt.Errorf("auth: check throttles: %w", err)
	}
	return throttleError(now, retryAt)
}

func (t *Throttle) Consume(
	ctx context.Context,
	accountSignal string,
	networkSignal string,
) error {
	now := t.now().UTC()
	retryAt, err := t.store.ConsumeAuthThrottles(
		ctx,
		t.keys(accountSignal, networkSignal),
		now,
		ThrottleLimits{
			Account: accountLimit,
			Network: networkLimit,
			Window:  throttleWindow,
			Block:   throttleWindow,
		},
	)
	if err != nil {
		return fmt.Errorf("auth: consume throttles: %w", err)
	}
	return throttleError(now, retryAt)
}

func (t *Throttle) ClearAccount(ctx context.Context, accountSignal string) error {
	if err := t.store.ClearAuthAccountThrottle(
		ctx,
		signalHash(t.secret, accountSignalDomain, accountSignal),
	); err != nil {
		return fmt.Errorf("auth: clear account throttle: %w", err)
	}
	return nil
}

func (t *Throttle) keys(accountSignal, networkSignal string) ThrottleKeys {
	return ThrottleKeys{
		Account: signalHash(t.secret, accountSignalDomain, accountSignal),
		Network: signalHash(t.secret, networkSignalDomain, networkSignal),
	}
}

func throttleError(now, retryAt time.Time) error {
	if retryAt.IsZero() || !now.Before(retryAt) {
		return nil
	}
	return &Error{Code: RateLimited, RetryAfter: retryAt.Sub(now)}
}

func signalHash(secret [32]byte, domain signalDomain, signal string) [32]byte {
	mac := hmac.New(sha256.New, secret[:])
	_, _ = mac.Write([]byte(domain))
	_, _ = mac.Write([]byte{0})
	_, _ = mac.Write([]byte(signal))
	var result [32]byte
	copy(result[:], mac.Sum(nil))
	return result
}

type networkSignalContextKey struct{}

func WithNetworkSignal(ctx context.Context, signal string) context.Context {
	return context.WithValue(ctx, networkSignalContextKey{}, signal)
}

func NetworkSignal(ctx context.Context) string {
	signal, _ := ctx.Value(networkSignalContextKey{}).(string)
	return signal
}
