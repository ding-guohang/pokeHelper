package session

import (
	"context"
	"time"

	"porkhelper/server/internal/auth"
)

// AuthAdapter exposes the manager through the auth package's SessionIssuer
// port. It exists so the auth use cases stay independent of this package's
// DTOs: auth speaks auth.DeviceMetadata and auth.SessionTokens, and only this
// file knows how those map onto sessions.
type AuthAdapter struct {
	manager *Manager
}

var _ auth.SessionIssuer = (*AuthAdapter)(nil)

func NewAuthAdapter(manager *Manager) *AuthAdapter {
	return &AuthAdapter{manager: manager}
}

func (a *AuthAdapter) Issue(
	ctx context.Context,
	userID string,
	device auth.DeviceMetadata,
	now time.Time,
) (auth.SessionTokens, error) {
	pair, err := a.manager.Issue(ctx, userID, DeviceMetadata{
		DeviceID:    device.DeviceID,
		DisplayName: device.DisplayName,
		Platform:    device.Platform,
		AppVersion:  device.AppVersion,
	}, now)
	if err != nil {
		return auth.SessionTokens{}, err
	}
	return auth.SessionTokens{
		AccessToken:      pair.AccessToken,
		RefreshToken:     pair.RefreshToken,
		AccessExpiresAt:  pair.AccessExpiresAt,
		RefreshExpiresAt: pair.RefreshExpiresAt,
		UserID:           pair.UserID,
		SessionID:        pair.SessionID,
		RecentAuthAt:     pair.RecentAuthAt,
	}, nil
}

// RevokeAll ends every session of the user. The reason is an auth-side audit
// label; sessions carry no reason column, so it is not persisted here.
func (a *AuthAdapter) RevokeAll(ctx context.Context, userID string, _ string) error {
	return a.manager.RevokeAllSessions(ctx, userID)
}
