//go:build integration

package mysqlstore_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"log/slog"
	"strings"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/mail"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/password"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestRegistrationIsAtomicEnumerationSafeAndStoresOnlyCredentialHashes(t *testing.T) {
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	now := time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC)
	clock := &mutableClock{now: now}
	mailer := &mail.MemoryMailer{}
	service := auth.NewService(
		mysqlstore.NewAuthStore(db),
		password.NewPolicy(password.Blocklist{}),
		password.NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x41}, 64))),
		mailer,
		bytes.NewReader(sequentialBytes(256)),
		clock.Now,
	)

	var logs bytes.Buffer
	originalLogger := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, nil)))
	t.Cleanup(func() { slog.SetDefault(originalLogger) })

	input := auth.RegisterInput{
		Email:    "  UsE\u0301r@EXAMPLE.COM  ",
		Password: "a valid password with spaces",
	}
	first, err := service.Register(context.Background(), input)
	if err != nil {
		t.Fatalf("Register(new) error = %v", err)
	}
	second, err := service.Register(context.Background(), auth.RegisterInput{
		Email:    "USÉR@example.com",
		Password: "another valid password",
	})
	if err != nil {
		t.Fatalf("Register(existing) error = %v", err)
	}
	if first != (auth.Accepted{Accepted: true}) || second != first {
		t.Fatalf("Register() envelopes = %#v / %#v, want identical accepted", first, second)
	}

	for tableName, want := range map[string]int{
		"users": 1, "auth_identities": 1, "password_credentials": 1,
		"email_challenges": 1, "user_sync_sequences": 1,
	} {
		var got int
		if err := db.QueryRow("SELECT COUNT(*) FROM `" + tableName + "`").Scan(&got); err != nil {
			t.Fatalf("count %s: %v", tableName, err)
		}
		if got != want {
			t.Errorf("%s count = %d, want %d", tableName, got, want)
		}
	}

	var provider, subject, canonical, display string
	var verified bool
	if err := db.QueryRow(`
		SELECT provider, subject, canonical_email, display_email, email_verified
		FROM auth_identities`,
	).Scan(&provider, &subject, &canonical, &display, &verified); err != nil {
		t.Fatalf("read identity: %v", err)
	}
	if provider != "email" || subject != "usér@example.com" ||
		canonical != subject || display != "UsÉr@EXAMPLE.COM" || verified {
		t.Errorf("identity = %q/%q/%q/%q verified=%v", provider, subject, canonical, display, verified)
	}

	var phc string
	if err := db.QueryRow("SELECT password_hash FROM password_credentials").Scan(&phc); err != nil {
		t.Fatalf("read password credential: %v", err)
	}
	if !strings.HasPrefix(phc, "$argon2id$v=19$m=19456,t=2,p=1$") ||
		strings.Contains(phc, input.Password) {
		t.Errorf("stored password credential is not the required PHC")
	}

	delivered := mailer.Delivered()
	if len(delivered) != 1 {
		t.Fatalf("delivered messages = %d, want 1", len(delivered))
	}
	rawToken := delivered[0].Body
	if strings.Contains(rawToken, "=") {
		t.Errorf("verification token %q contains base64 padding", rawToken)
	}
	tokenBytes, err := base64.RawURLEncoding.DecodeString(rawToken)
	if err != nil || len(tokenBytes) != 32 {
		t.Fatalf("verification token decodes to %d bytes, err %v; want 32", len(tokenBytes), err)
	}
	tokenHash := sha256.Sum256([]byte(rawToken))

	var storedHash []byte
	var purpose string
	var expires time.Time
	var attempts uint64
	var consumed *time.Time
	if err := db.QueryRow(`
		SELECT token_hash, purpose, expires_at, attempt_count, consumed_at
		FROM email_challenges`,
	).Scan(&storedHash, &purpose, &expires, &attempts, &consumed); err != nil {
		t.Fatalf("read challenge: %v", err)
	}
	if !bytes.Equal(storedHash, tokenHash[:]) || bytes.Equal(storedHash, []byte(rawToken)) {
		t.Errorf("stored challenge is not exactly SHA-256(raw token)")
	}
	if purpose != "verifyEmail" || !expires.Equal(now.Add(24*time.Hour)) ||
		attempts != 0 || consumed != nil {
		t.Errorf("challenge metadata = %q expiry %s attempts %d consumed %v",
			purpose, expires, attempts, consumed)
	}
	var nextSequence uint64
	if err := db.QueryRow("SELECT next_sequence FROM user_sync_sequences").Scan(&nextSequence); err != nil {
		t.Fatalf("read sync sequence: %v", err)
	}
	if nextSequence != 0 {
		t.Errorf("next_sequence = %d, want 0", nextSequence)
	}

	for _, secret := range []string{canonical, input.Password, rawToken, phc} {
		if strings.Contains(logs.String(), secret) {
			t.Errorf("logs contain credential %q: %s", secret, logs.String())
		}
	}
}

func TestVerificationChallengeIsSingleUseAndExpiredChallengesFail(t *testing.T) {
	tests := []struct {
		name       string
		advance    time.Duration
		firstValid bool
	}{
		{name: "single use", firstValid: true},
		{name: "expired", advance: 24*time.Hour + time.Millisecond},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			db := mysqltest.Database(t)
			if err := migrations.Apply(context.Background(), db); err != nil {
				t.Fatalf("apply migrations: %v", err)
			}
			clock := &mutableClock{now: time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC)}
			mailer := &mail.MemoryMailer{}
			service := auth.NewService(
				mysqlstore.NewAuthStore(db),
				password.NewPolicy(password.Blocklist{}),
				password.NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x31}, 16))),
				mailer,
				bytes.NewReader(bytes.Repeat([]byte{0x62}, 128)),
				clock.Now,
			)
			if _, err := service.Register(context.Background(), auth.RegisterInput{
				Email: "person@example.com", Password: "fifteen characters",
			}); err != nil {
				t.Fatalf("Register() error = %v", err)
			}
			rawToken := mailer.Delivered()[0].Body
			clock.now = clock.now.Add(tt.advance)

			firstErr := service.VerifyEmail(context.Background(), rawToken)
			if tt.firstValid {
				if firstErr != nil {
					t.Fatalf("first VerifyEmail() error = %v", firstErr)
				}
				secondErr := service.VerifyEmail(context.Background(), rawToken)
				assertChallengeInvalid(t, secondErr)
			} else {
				assertChallengeInvalid(t, firstErr)
			}

			var verified bool
			var attempts uint64
			var consumed *time.Time
			if err := db.QueryRow(`
				SELECT i.email_verified, c.attempt_count, c.consumed_at
				FROM auth_identities AS i
				INNER JOIN email_challenges AS c ON c.user_id = i.user_id`,
			).Scan(&verified, &attempts, &consumed); err != nil {
				t.Fatalf("read verification state: %v", err)
			}
			wantAttempts := uint64(1)
			if tt.firstValid {
				wantAttempts = 2
			}
			if verified != tt.firstValid || attempts != wantAttempts ||
				(tt.firstValid && consumed == nil) || (!tt.firstValid && consumed != nil) {
				t.Errorf("verification state = verified %v attempts %d consumed %v",
					verified, attempts, consumed)
			}
		})
	}
}

func TestRegistrationRollsBackEveryRowWhenFinalInsertFails(t *testing.T) {
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	if _, err := db.Exec(`
		ALTER TABLE user_sync_sequences
		ADD CONSTRAINT reject_registration_sync_sequence CHECK (next_sequence <> 0) ENFORCED`); err != nil {
		t.Fatalf("create failure-injection check: %v", err)
	}
	service := auth.NewService(
		mysqlstore.NewAuthStore(db),
		password.NewPolicy(password.Blocklist{}),
		password.NewHasher(bytes.NewReader(bytes.Repeat([]byte{0x21}, 16))),
		&mail.MemoryMailer{},
		bytes.NewReader(sequentialBytes(128)),
		func() time.Time { return time.Date(2026, 8, 7, 3, 4, 5, 0, time.UTC) },
	)

	if _, err := service.Register(context.Background(), auth.RegisterInput{
		Email: "rollback@example.com", Password: "fifteen characters",
	}); err == nil {
		t.Fatal("Register() error = nil, want injected final insert failure")
	}
	for _, tableName := range []string{
		"users", "auth_identities", "password_credentials",
		"email_challenges", "user_sync_sequences",
	} {
		var count int
		if err := db.QueryRow("SELECT COUNT(*) FROM `" + tableName + "`").Scan(&count); err != nil {
			t.Fatalf("count %s: %v", tableName, err)
		}
		if count != 0 {
			t.Errorf("%s count after rollback = %d, want 0", tableName, count)
		}
	}
}

func assertChallengeInvalid(t *testing.T, err error) {
	t.Helper()
	var authError *auth.Error
	if !errors.As(err, &authError) || authError.Code != auth.ChallengeInvalid {
		t.Fatalf("error = %v, want challengeInvalid", err)
	}
}

type mutableClock struct {
	now time.Time
}

func (c *mutableClock) Now() time.Time {
	return c.now
}

func sequentialBytes(length int) []byte {
	values := make([]byte, length)
	for index := range values {
		values[index] = byte(index)
	}
	return values
}
