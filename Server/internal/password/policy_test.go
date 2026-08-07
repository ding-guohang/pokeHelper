package password

import (
	"errors"
	"strings"
	"testing"
)

func TestPolicyCountsNormalizedUnicodeScalars(t *testing.T) {
	t.Parallel()

	policy := NewPolicy(Blocklist{})
	tests := []struct {
		name string
		raw  string
		want string
		code ErrorCode
	}{
		{name: "fourteen", raw: strings.Repeat("界", 14), code: TooShort},
		{name: "fifteen", raw: strings.Repeat("界", 15), want: strings.Repeat("界", 15)},
		{name: "one hundred twenty eight", raw: strings.Repeat("🙂", 128), want: strings.Repeat("🙂", 128)},
		{name: "one hundred twenty nine", raw: strings.Repeat("🙂", 129), code: TooLong},
		{name: "combining sequence normalizes before counting", raw: strings.Repeat("e\u0301", 15), want: strings.Repeat("é", 15)},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := policy.NormalizeAndValidate(tt.raw)
			if tt.code == "" {
				if err != nil {
					t.Fatalf("NormalizeAndValidate() error = %v", err)
				}
				if got != tt.want {
					t.Fatalf("NormalizeAndValidate() = %q, want %q", got, tt.want)
				}
				return
			}
			var policyError *Error
			if !errors.As(err, &policyError) || policyError.Code != tt.code {
				t.Fatalf("NormalizeAndValidate() error = %v, want code %q", err, tt.code)
			}
		})
	}
}

func TestPolicyAllowsAllCharacterClassesAndSpaces(t *testing.T) {
	t.Parallel()

	raw := "lower UPPER 123 !@ 中文"
	got, err := NewPolicy(Blocklist{}).NormalizeAndValidate(raw)
	if err != nil {
		t.Fatalf("NormalizeAndValidate() error = %v", err)
	}
	if got != raw {
		t.Fatalf("NormalizeAndValidate() = %q, want %q", got, raw)
	}
}

func TestPolicyRejectsNormalizedCaseFoldedBlocklistEntry(t *testing.T) {
	t.Parallel()

	blocklist, err := ParseBlocklist(strings.NewReader("Pássword Password\n"))
	if err != nil {
		t.Fatalf("ParseBlocklist() error = %v", err)
	}
	policy := NewPolicy(blocklist)

	_, err = policy.NormalizeAndValidate("pa\u0301SSWORD password")
	var policyError *Error
	if !errors.As(err, &policyError) || policyError.Code != Blocked {
		t.Fatalf("NormalizeAndValidate() error = %v, want code %q", err, Blocked)
	}
}
