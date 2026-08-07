package password

import (
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

const (
	minScalars = 15
	maxScalars = 128
)

type Policy struct {
	blocklist Blocklist
}

func NewPolicy(blocklist Blocklist) Policy {
	return Policy{blocklist: blocklist}
}

func (p Policy) NormalizeAndValidate(raw string) (string, error) {
	if !utf8.ValidString(raw) {
		return "", &Error{Code: Invalid}
	}
	normalized := norm.NFC.String(raw)
	length := utf8.RuneCountInString(normalized)
	if length < minScalars {
		return "", &Error{Code: TooShort}
	}
	if length > maxScalars {
		return "", &Error{Code: TooLong}
	}
	if p.blocklist.Contains(normalized) {
		return "", &Error{Code: Blocked}
	}
	return normalized, nil
}
