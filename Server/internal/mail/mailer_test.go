package mail

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
)

func TestMemoryAndDevelopmentMailersKeepCredentialsOutOfLogs(t *testing.T) {
	message := Message{
		To:      "secret@example.com",
		Subject: "Verify your email",
		Body:    "raw-token-that-must-not-be-logged",
	}
	var logs bytes.Buffer
	original := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, nil)))
	t.Cleanup(func() { slog.SetDefault(original) })

	memory := &MemoryMailer{}
	if err := memory.Deliver(context.Background(), message); err != nil {
		t.Fatalf("MemoryMailer.Deliver() error = %v", err)
	}
	delivered := memory.Delivered()
	if len(delivered) != 1 || delivered[0] != message {
		t.Fatalf("MemoryMailer.Delivered() = %#v, want message", delivered)
	}

	mailbox := &DevelopmentMailbox{}
	development, err := NewDevelopmentMailer("development", mailbox)
	if err != nil {
		t.Fatalf("NewDevelopmentMailer(development) error = %v", err)
	}
	if err := development.Deliver(context.Background(), message); err != nil {
		t.Fatalf("DevelopmentMailer.Deliver() error = %v", err)
	}
	if got := mailbox.Messages(); len(got) != 1 || got[0] != message {
		t.Fatalf("DevelopmentMailbox.Messages() = %#v, want message", got)
	}

	for _, secret := range []string{message.To, message.Body} {
		if strings.Contains(logs.String(), secret) {
			t.Fatalf("logs contain secret %q: %s", secret, logs.String())
		}
	}
}

func TestDevelopmentMailerRejectsNonDevelopmentEnvironment(t *testing.T) {
	t.Parallel()

	_, err := NewDevelopmentMailer("production", &DevelopmentMailbox{})
	var configError *ConfigurationError
	if !errors.As(err, &configError) || configError.Code != ConfigurationInvalid {
		t.Fatalf("NewDevelopmentMailer(production) error = %v, want configurationInvalid", err)
	}
}

func TestSMTPMailerFailsClosedOnMissingOrInvalidProductionConfiguration(t *testing.T) {
	t.Parallel()

	required := []string{
		"POKER_COACH_SMTP_HOST",
		"POKER_COACH_SMTP_PORT",
		"POKER_COACH_SMTP_USERNAME",
		"POKER_COACH_SMTP_PASSWORD",
		"POKER_COACH_SMTP_SENDER",
		"POKER_COACH_SMTP_TLS_MODE",
	}
	complete := map[string]string{
		"POKER_COACH_SMTP_HOST":     "smtp.example.com",
		"POKER_COACH_SMTP_PORT":     "587",
		"POKER_COACH_SMTP_USERNAME": "mailer",
		"POKER_COACH_SMTP_PASSWORD": "smtp-secret",
		"POKER_COACH_SMTP_SENDER":   "noreply@example.com",
		"POKER_COACH_SMTP_TLS_MODE": "starttls",
	}
	for _, missing := range required {
		missing := missing
		t.Run("missing "+missing, func(t *testing.T) {
			values := cloneValues(complete)
			delete(values, missing)
			_, err := NewSMTPMailer("production", mapLookup(values), nil)
			var configError *ConfigurationError
			if !errors.As(err, &configError) || configError.Code != ConfigurationInvalid {
				t.Fatalf("NewSMTPMailer() error = %v, want configurationInvalid", err)
			}
		})
	}

	invalidMode := cloneValues(complete)
	invalidMode["POKER_COACH_SMTP_TLS_MODE"] = "plaintext"
	_, err := NewSMTPMailer("production", mapLookup(invalidMode), nil)
	var configError *ConfigurationError
	if !errors.As(err, &configError) || configError.Code != ConfigurationInvalid {
		t.Fatalf("NewSMTPMailer(invalid TLS mode) error = %v, want configurationInvalid", err)
	}
}

func TestSMTPMailerPassesConfiguredEnvelopeToExternalTransport(t *testing.T) {
	t.Parallel()

	values := map[string]string{
		"POKER_COACH_SMTP_HOST":     "smtp.example.com",
		"POKER_COACH_SMTP_PORT":     "465",
		"POKER_COACH_SMTP_USERNAME": "mailer",
		"POKER_COACH_SMTP_PASSWORD": "smtp-secret",
		"POKER_COACH_SMTP_SENDER":   "noreply@example.com",
		"POKER_COACH_SMTP_TLS_MODE": "tls",
	}
	transport := &recordingTransport{}
	mailer, err := NewSMTPMailer("production", mapLookup(values), transport)
	if err != nil {
		t.Fatalf("NewSMTPMailer() error = %v", err)
	}
	message := Message{To: "person@example.com", Subject: "Verify", Body: "token"}
	if err := mailer.Deliver(context.Background(), message); err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}

	if transport.config.Host != "smtp.example.com" ||
		transport.config.Port != 465 ||
		transport.config.Username != "mailer" ||
		transport.config.Password != "smtp-secret" ||
		transport.config.Sender != "noreply@example.com" ||
		transport.config.TLSMode != TLS {
		t.Fatalf("transport config = %#v, want configured TLS envelope", transport.config)
	}
	if transport.message != message {
		t.Fatalf("transport message = %#v, want %#v", transport.message, message)
	}
}

type recordingTransport struct {
	config  SMTPConfig
	message Message
}

func (t *recordingTransport) Send(_ context.Context, config SMTPConfig, message Message) error {
	t.config = config
	t.message = message
	return nil
}

func mapLookup(values map[string]string) func(string) (string, bool) {
	return func(name string) (string, bool) {
		value, ok := values[name]
		return value, ok
	}
}

func cloneValues(values map[string]string) map[string]string {
	clone := make(map[string]string, len(values))
	for key, value := range values {
		clone[key] = value
	}
	return clone
}
