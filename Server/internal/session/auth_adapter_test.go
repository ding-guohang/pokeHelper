package session_test

import (
	"bytes"
	"context"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/session"
)

func TestAuthAdapterTranslatesIssuedSessionsIntoAuthDTOs(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	adapter := session.NewAuthAdapter(manager)

	tokens, err := adapter.Issue(context.Background(), userA, auth.DeviceMetadata{
		DeviceID:    "installation-a",
		DisplayName: "iPhone",
		Platform:    "iOS",
	}, clock)
	if err != nil {
		t.Fatalf("issue through adapter: %v", err)
	}

	if tokens.UserID != userA {
		t.Errorf("user ID = %q, want %q", tokens.UserID, userA)
	}
	if tokens.AccessToken == "" || tokens.RefreshToken == "" {
		t.Error("adapter must surface both plaintext tokens exactly once")
	}
	if !tokens.RecentAuthAt.Equal(clock) {
		t.Errorf("recent auth = %s, want %s", tokens.RecentAuthAt, clock)
	}
	if store.created.Device.DisplayName != "iPhone" {
		t.Errorf("device display name = %q, want iPhone", store.created.Device.DisplayName)
	}
}

func TestAuthAdapterRevokeAllEndsEverySessionOfTheUser(t *testing.T) {
	store := newFakeStore()
	clock := time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC)
	manager := session.NewManager(store, bytes.NewReader(sequentialBytes(512)), staticClock(clock))
	adapter := session.NewAuthAdapter(manager)

	if err := adapter.RevokeAll(context.Background(), userA, "passwordReset"); err != nil {
		t.Fatalf("revoke all: %v", err)
	}

	if store.revokedUserID != userA {
		t.Errorf("revoked sessions for %q, want %q", store.revokedUserID, userA)
	}
}
