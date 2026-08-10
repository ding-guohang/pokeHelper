package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/appleauth"
	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/config"
	"porkhelper/server/internal/httpapi"
	"porkhelper/server/internal/mail"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/password"
	"porkhelper/server/internal/session"
	"porkhelper/server/internal/sync"
	"porkhelper/server/migrations"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server exited", "error", err)
		os.Exit(1)
	}
}

func run() error {
	settings, err := config.Load(os.LookupEnv)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := mysqlstore.Open(ctx, settings.MySQLDSN)
	if err != nil {
		return err
	}
	defer func() { _ = db.Close() }()

	if err := migrations.Apply(ctx, db); err != nil {
		return fmt.Errorf("apply migrations: %w", err)
	}

	handlers, err := buildHandlers(settings, db)
	if err != nil {
		return err
	}

	server := &http.Server{
		Addr:              settings.HTTPAddr,
		Handler:           httpapi.NewRouter(handlers, nil),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()

	slog.Info("serving", "addr", settings.HTTPAddr, "environment", settings.Environment)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// buildHandlers wires every feature onto one database.
//
// This is the only place that knows how the pieces fit together; each package
// keeps its own constructor so it stays testable in isolation.
func buildHandlers(settings config.Config, db *sql.DB) (httpapi.Handlers, error) {
	blocklist, err := loadBlocklist()
	if err != nil {
		return httpapi.Handlers{}, err
	}
	mailer, err := buildMailer(settings)
	if err != nil {
		return httpapi.Handlers{}, err
	}
	secret, err := throttleSecret(settings)
	if err != nil {
		return httpapi.Handlers{}, err
	}

	authStore := mysqlstore.NewAuthStore(db)
	throttle, err := auth.NewThrottle(authStore, secret, time.Now)
	if err != nil {
		return httpapi.Handlers{}, err
	}

	sessionManager := session.NewManager(
		mysqlstore.NewSessionStore(db),
		rand.Reader,
		time.Now,
	)
	issuer := session.NewAuthAdapter(sessionManager)
	hasher := password.NewHasher(rand.Reader)

	authService := auth.NewService(
		authStore,
		password.NewPolicy(blocklist),
		hasher,
		mailer,
		rand.Reader,
		time.Now,
		auth.WithThrottle(throttle),
		auth.WithSessionIssuer(issuer),
	)

	appleVerifier, err := buildAppleVerifier(settings)
	if err != nil {
		return httpapi.Handlers{}, err
	}
	appleService := auth.NewAppleService(
		appleVerifier,
		mysqlstore.NewAppleIdentityStore(db),
		issuer,
		rand.Reader,
		time.Now,
	)

	syncStore := mysqlstore.NewSyncStore(db)

	return httpapi.Handlers{
		Auth:    authService,
		Apple:   appleService,
		Account: account.NewService(mysqlstore.NewAccountStore(db), hasher, appleVerifier, time.Now),
		Upload:  sync.NewUploadService(syncStore),
		Pull:    sync.NewPullService(syncStore),
		Session: sessionManager,
	}, nil
}

func loadBlocklist() (password.Blocklist, error) {
	file, err := os.Open("resources/weak-passwords.txt")
	if err != nil {
		return password.Blocklist{}, fmt.Errorf("open password blocklist: %w", err)
	}
	defer func() { _ = file.Close() }()
	return password.ParseBlocklist(file)
}

// buildMailer refuses to fall back to logging message bodies in production:
// a verification link written to a log is a credential in a log.
func buildMailer(settings config.Config) (mail.Mailer, error) {
	if settings.Environment == config.Production {
		return mail.NewSMTPMailer(string(settings.Environment), os.LookupEnv, nil)
	}
	return mail.NewDevelopmentMailer(string(settings.Environment), &mail.DevelopmentMailbox{})
}

func buildAppleVerifier(settings config.Config) (*appleauth.Verifier, error) {
	audience, ok := os.LookupEnv("POKER_COACH_APPLE_CLIENT_ID")
	if !ok || audience == "" {
		if settings.Environment == config.Production {
			return nil, errors.New(
				"config: POKER_COACH_APPLE_CLIENT_ID is required in production",
			)
		}
		audience = "com.porkhelper.PokerCoach"
	}
	return appleauth.NewVerifier(
		appleauth.NewKeyCache(appleauth.AppleKeysEndpoint, nil, time.Now),
		"",
		audience,
		time.Now,
	), nil
}

// throttleSecret returns the HMAC key that pseudonymizes login signals.
//
// Production must supply one: a generated key would reset every rate limit on
// restart, which is exactly the window an attacker wants.
func throttleSecret(settings config.Config) ([]byte, error) {
	raw, ok := os.LookupEnv("POKER_COACH_THROTTLE_SECRET")
	if !ok || raw == "" {
		if settings.Environment == config.Production {
			return nil, errors.New(
				"config: POKER_COACH_THROTTLE_SECRET is required in production",
			)
		}
		secret := make([]byte, sha256.Size)
		if _, err := rand.Read(secret); err != nil {
			return nil, err
		}
		slog.Warn("using an ephemeral throttle secret; rate limits reset on restart")
		return secret, nil
	}
	secret, err := hex.DecodeString(raw)
	if err != nil || len(secret) != sha256.Size {
		return nil, errors.New("config: POKER_COACH_THROTTLE_SECRET must be 64 hex characters")
	}
	return secret, nil
}
