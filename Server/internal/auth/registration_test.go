package auth

import (
	"errors"
	"strings"
	"testing"
)

func TestNormalizeEmailPreservesDisplayAndCanonicalizesUnicode(t *testing.T) {
	t.Parallel()

	got, err := NormalizeEmail("  UsE\u0301r@EXAMPLE.COM  ")
	if err != nil {
		t.Fatalf("NormalizeEmail() error = %v", err)
	}
	if got.Display != "UsÉr@EXAMPLE.COM" {
		t.Errorf("display email = %q, want %q", got.Display, "UsÉr@EXAMPLE.COM")
	}
	if got.Canonical != "usér@example.com" {
		t.Errorf("canonical email = %q, want %q", got.Canonical, "usér@example.com")
	}
}

func TestNormalizeEmailRejectsInvalidAddresses(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		raw  string
	}{
		{name: "empty", raw: "  "},
		{name: "control", raw: "user\u0000@example.com"},
		{name: "interior whitespace", raw: "user name@example.com"},
		{name: "missing at", raw: "example.com"},
		{name: "two ats", raw: "user@@example.com"},
		{name: "empty local", raw: "@example.com"},
		{name: "empty domain", raw: "user@"},
		{name: "over 254 utf8 bytes", raw: strings.Repeat("界", 83) + "@x.test"},
		{name: "invalid utf8", raw: string([]byte{'u', '@', 0xff})},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := NormalizeEmail(tt.raw)
			var authError *Error
			if !errors.As(err, &authError) || authError.Code != ValidationFailed {
				t.Fatalf("NormalizeEmail() error = %v, want validationFailed", err)
			}
		})
	}
}
