//go:build integration

package mysqlstore_test

import (
	"bytes"
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestThrottleTransactionsDoNotLoseSimultaneousAccountOrNetworkAttempts(t *testing.T) {
	tests := []struct {
		name        string
		workers     int
		accountFor  func(int) string
		networkFor  func(int) string
		wantAccount uint64
		wantNetwork uint64
	}{
		{
			name:        "account bucket sixth attempt",
			workers:     6,
			accountFor:  func(int) string { return "same@example.com" },
			networkFor:  func(index int) string { return "192.0.2." + string(rune('a'+index)) },
			wantAccount: 6,
			wantNetwork: 1,
		},
		{
			name:        "network bucket twenty-sixth attempt",
			workers:     26,
			accountFor:  func(index int) string { return "user-" + string(rune('a'+index)) + "@example.com" },
			networkFor:  func(int) string { return "198.51.100.20" },
			wantAccount: 1,
			wantNetwork: 26,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			db := mysqltest.Database(t)
			if err := migrations.Apply(context.Background(), db); err != nil {
				t.Fatalf("apply migrations: %v", err)
			}
			now := time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC)
			throttle, err := auth.NewThrottle(
				mysqlstore.NewAuthStore(db),
				bytes.Repeat([]byte{0x33}, 32),
				func() time.Time { return now },
			)
			if err != nil {
				t.Fatalf("NewThrottle() error = %v", err)
			}

			// GIVEN simultaneous authentication attempts sharing one bucket
			start := make(chan struct{})
			results := make(chan error, tt.workers)
			var ready sync.WaitGroup
			ready.Add(tt.workers)
			for index := 0; index < tt.workers; index++ {
				index := index
				go func() {
					ready.Done()
					<-start

					// WHEN every attempt consumes both quotas transactionally
					results <- throttle.Consume(
						context.Background(),
						tt.accountFor(index),
						tt.networkFor(index),
					)
				}()
			}
			ready.Wait()
			close(start)

			rateLimited := 0
			for index := 0; index < tt.workers; index++ {
				err := <-results
				var authError *auth.Error
				if errors.As(err, &authError) && authError.Code == auth.RateLimited {
					rateLimited++
				} else if err != nil {
					t.Errorf("Consume() error = %v", err)
				}
			}

			// THEN no increments are lost and exactly the boundary attempt is rate limited
			if rateLimited != 1 {
				t.Fatalf("rate limited attempts = %d, want 1", rateLimited)
			}
			var maxAccount, maxNetwork uint64
			zero := make([]byte, 32)
			if err := db.QueryRow(`
				SELECT COALESCE(MAX(failure_count), 0)
				FROM auth_throttles
				WHERE network_signal_hash = ?`, zero,
			).Scan(&maxAccount); err != nil {
				t.Fatalf("read account throttle = %v", err)
			}
			if err := db.QueryRow(`
				SELECT COALESCE(MAX(failure_count), 0)
				FROM auth_throttles
				WHERE identity_signal_hash = ?`, zero,
			).Scan(&maxNetwork); err != nil {
				t.Fatalf("read network throttle = %v", err)
			}
			if maxAccount != tt.wantAccount || maxNetwork != tt.wantNetwork {
				t.Fatalf("max failure counts = account %d network %d, want %d/%d",
					maxAccount, maxNetwork, tt.wantAccount, tt.wantNetwork)
			}
		})
	}
}

func TestThrottleRequiresExactlyThirtyTwoSecretBytes(t *testing.T) {
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	store := mysqlstore.NewAuthStore(db)

	// GIVEN HMAC secrets whose lengths are not 32 bytes
	for _, length := range []int{0, 31, 33} {
		// WHEN throttle construction validates the injected secret
		_, err := auth.NewThrottle(store, make([]byte, length), nil)

		// THEN configuration fails closed
		if err == nil {
			t.Fatalf("NewThrottle(secret length %d) error = nil", length)
		}
	}
}
