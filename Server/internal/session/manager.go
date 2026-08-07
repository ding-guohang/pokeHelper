package session

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"sync"
	"time"
)

const (
	defaultAccessTTL  = 15 * time.Minute
	defaultRefreshTTL = 30 * 24 * time.Hour
)

type Manager struct {
	store  Store
	now    func() time.Time
	random io.Reader

	// entropy serializes token minting so concurrent callers cannot interleave
	// reads of the same random source and receive overlapping tokens.
	entropy sync.Mutex

	accessTTL  time.Duration
	refreshTTL time.Duration
}

type ManagerOption func(*Manager)

func WithAccessTTL(ttl time.Duration) ManagerOption {
	return func(m *Manager) { m.accessTTL = ttl }
}

func WithRefreshTTL(ttl time.Duration) ManagerOption {
	return func(m *Manager) { m.refreshTTL = ttl }
}

func NewManager(
	store Store,
	random io.Reader,
	now func() time.Time,
	options ...ManagerOption,
) *Manager {
	if random == nil {
		random = rand.Reader
	}
	if now == nil {
		now = time.Now
	}
	manager := &Manager{
		store:      store,
		now:        now,
		random:     random,
		accessTTL:  defaultAccessTTL,
		refreshTTL: defaultRefreshTTL,
	}
	for _, option := range options {
		option(manager)
	}
	return manager
}

// Issue mints a new session for an already-authenticated user. Callers own the
// authentication decision; Issue never validates credentials.
func (m *Manager) Issue(
	ctx context.Context,
	userID string,
	device DeviceMetadata,
	now time.Time,
) (TokenPair, error) {
	if userID == "" {
		return TokenPair{}, &Error{Code: ValidationFailed}
	}
	if device.DeviceID == "" {
		return TokenPair{}, &Error{Code: ValidationFailed}
	}

	issuedAt := now.UTC()
	minted, err := m.mintPair()
	if err != nil {
		return TokenPair{}, err
	}

	created := NewSession{
		SessionID:        minted.sessionID,
		TokenFamilyID:    minted.familyID,
		RefreshTokenID:   minted.refreshTokenID,
		UserID:           userID,
		Device:           device,
		AccessHash:       minted.accessHash,
		RefreshHash:      minted.refreshHash,
		AccessExpiresAt:  issuedAt.Add(m.accessTTL),
		RefreshExpiresAt: issuedAt.Add(m.refreshTTL),
		RecentAuthAt:     issuedAt,
		Now:              issuedAt,
	}
	if err := m.store.CreateSession(ctx, created); err != nil {
		return TokenPair{}, fmt.Errorf("session: create session: %w", err)
	}

	return TokenPair{
		AccessToken:      minted.accessToken,
		RefreshToken:     minted.refreshToken,
		AccessExpiresAt:  created.AccessExpiresAt,
		RefreshExpiresAt: created.RefreshExpiresAt,
		UserID:           userID,
		SessionID:        minted.sessionID.String(),
		RecentAuthAt:     issuedAt,
	}, nil
}

// AuthenticateAccess resolves a bearer access token to its server-derived
// principal.
func (m *Manager) AuthenticateAccess(
	ctx context.Context,
	accessToken string,
) (Principal, error) {
	if accessToken == "" {
		return Principal{}, &Error{Code: Unauthenticated}
	}
	principal, err := m.store.AuthenticateAccess(ctx, hashToken(accessToken), m.now().UTC())
	if err != nil {
		return Principal{}, err
	}
	if principal.UserID == "" {
		return Principal{}, &Error{Code: Unauthenticated}
	}
	return principal, nil
}

// Refresh rotates both tokens. The presented refresh token is consumed and its
// replacements installed in a single store transaction, so a replay of an
// already-rotated token is detected rather than silently re-issued.
func (m *Manager) Refresh(ctx context.Context, refreshToken string) (TokenPair, error) {
	if refreshToken == "" {
		return TokenPair{}, &Error{Code: Unauthenticated}
	}

	rotatedAt := m.now().UTC()
	minted, err := m.mintPair()
	if err != nil {
		return TokenPair{}, err
	}

	outcome, err := m.store.RotateRefresh(ctx, Rotation{
		PresentedHash:    hashToken(refreshToken),
		RefreshTokenID:   minted.refreshTokenID,
		AccessHash:       minted.accessHash,
		RefreshHash:      minted.refreshHash,
		AccessExpiresAt:  rotatedAt.Add(m.accessTTL),
		RefreshExpiresAt: rotatedAt.Add(m.refreshTTL),
		Now:              rotatedAt,
	})
	if err != nil {
		return TokenPair{}, err
	}
	if outcome.Replayed || outcome.SessionID == "" {
		return TokenPair{}, &Error{Code: Unauthenticated}
	}

	return TokenPair{
		AccessToken:      minted.accessToken,
		RefreshToken:     minted.refreshToken,
		AccessExpiresAt:  rotatedAt.Add(m.accessTTL),
		RefreshExpiresAt: rotatedAt.Add(m.refreshTTL),
		UserID:           outcome.UserID,
		SessionID:        outcome.SessionID,
		RecentAuthAt:     outcome.RecentAuthAt,
	}, nil
}

// Logout revokes the session owning the presented refresh token.
func (m *Manager) Logout(ctx context.Context, refreshToken string) error {
	if refreshToken == "" {
		return &Error{Code: Unauthenticated}
	}
	return m.store.RevokeByRefresh(ctx, hashToken(refreshToken), m.now().UTC())
}

// ListDevices returns the principal's own device sessions, marking the session
// the caller is currently using.
func (m *Manager) ListDevices(
	ctx context.Context,
	principal Principal,
) ([]DeviceSession, error) {
	if principal.UserID == "" {
		return nil, &Error{Code: Unauthenticated}
	}
	devices, err := m.store.ListDevices(ctx, principal.UserID, m.now().UTC())
	if err != nil {
		return nil, err
	}
	for index := range devices {
		devices[index].Current = devices[index].SessionID == principal.SessionID
	}
	return devices, nil
}

// RevokeSession revokes one of the principal's own sessions. Ownership is
// enforced by the store using the server-derived user ID.
func (m *Manager) RevokeSession(
	ctx context.Context,
	principal Principal,
	sessionID string,
) error {
	if principal.UserID == "" {
		return &Error{Code: Unauthenticated}
	}
	if sessionID == "" {
		return &Error{Code: ValidationFailed}
	}
	return m.store.RevokeSession(ctx, principal.UserID, sessionID, m.now().UTC())
}

// RevokeAllSessions revokes every session owned by the user. Credential
// changes such as a password reset use this to end all existing access.
func (m *Manager) RevokeAllSessions(ctx context.Context, userID string) error {
	if userID == "" {
		return &Error{Code: ValidationFailed}
	}
	return m.store.RevokeAllForUser(ctx, userID, "", m.now().UTC())
}

type mintedPair struct {
	sessionID      ID
	familyID       ID
	refreshTokenID ID
	accessToken    string
	refreshToken   string
	accessHash     [32]byte
	refreshHash    [32]byte
}

func (m *Manager) mintPair() (mintedPair, error) {
	m.entropy.Lock()
	defer m.entropy.Unlock()

	var minted mintedPair
	var err error
	if minted.sessionID, err = newID(m.random); err != nil {
		return mintedPair{}, err
	}
	if minted.familyID, err = newID(m.random); err != nil {
		return mintedPair{}, err
	}
	if minted.refreshTokenID, err = newID(m.random); err != nil {
		return mintedPair{}, err
	}
	if minted.accessToken, minted.accessHash, err = mintToken(m.random); err != nil {
		return mintedPair{}, err
	}
	if minted.refreshToken, minted.refreshHash, err = mintToken(m.random); err != nil {
		return mintedPair{}, err
	}
	return minted, nil
}
