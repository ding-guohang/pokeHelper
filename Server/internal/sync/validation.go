package sync

import (
	"bytes"
	"encoding/hex"
	"strings"
)

// ValidateUpload checks everything that can be judged without touching the
// database. It never inspects the payload's localUserID or deviceID for
// authorization: ownership comes from the bearer session alone.
func ValidateUpload(command UploadCommand) error {
	if command.IdempotencyKey == "" || len(command.IdempotencyKey) > 255 {
		return &Error{Code: ValidationFailed}
	}
	if !isASCIIPrintable(command.IdempotencyKey) {
		return &Error{Code: ValidationFailed}
	}
	if command.Body.SchemaVersion != SchemaVersion {
		return &Error{Code: ValidationFailed}
	}
	if len(command.Body.Events) == 0 || len(command.Body.Events) > MaxBatchEvents {
		return &Error{Code: ValidationFailed}
	}
	if len(command.RawBody) > MaxBatchBytes {
		return &Error{Code: ValidationFailed}
	}

	// The body must already be canonical. Accepting an equivalent-but-different
	// encoding would give the same events two different hashes, and idempotent
	// replay would stop working.
	canonical, err := CanonicalBody(command.Body)
	if err != nil {
		return err
	}
	if !bytes.Equal(canonical, command.RawBody) {
		return &Error{Code: ValidationFailed}
	}

	seen := make(map[string]struct{}, len(command.Body.Events))
	for _, event := range command.Body.Events {
		if err := validateEvent(event); err != nil {
			return err
		}
		if _, duplicate := seen[event.ID]; duplicate {
			return &Error{Code: ValidationFailed}
		}
		seen[event.ID] = struct{}{}
	}
	return nil
}

func validateEvent(event Event) error {
	for _, id := range []string{event.ID, event.LocalUserID, event.DeviceID} {
		if !isLowercaseHyphenatedUUID(id) {
			return &Error{Code: ValidationFailed}
		}
	}
	if event.ScenarioID == "" || event.StrategyPackID == "" ||
		event.StrategyContentVersion == "" || event.AbilityDimension == "" {
		return &Error{Code: ValidationFailed}
	}
	if len(event.Submission) == 0 || len(event.Grade) == 0 {
		return &Error{Code: ValidationFailed}
	}
	if _, err := ParseOccurredAt(event.OccurredAt); err != nil {
		return err
	}
	return nil
}

// ValidatePullLimit clamps nothing: an out-of-range limit is a client bug and
// is rejected rather than silently reinterpreted.
func ValidatePullLimit(limit int) error {
	if limit < MinPullLimit || limit > MaxPullLimit {
		return &Error{Code: ValidationFailed}
	}
	return nil
}

func isLowercaseHyphenatedUUID(value string) bool {
	if len(value) != 36 {
		return false
	}
	for index, character := range value {
		switch index {
		case 8, 13, 18, 23:
			if character != '-' {
				return false
			}
		default:
			if !strings.ContainsRune("0123456789abcdef", character) {
				return false
			}
		}
	}
	return true
}

// UUIDBytes decodes a validated lowercase hyphenated UUID.
func UUIDBytes(value string) ([]byte, error) {
	if !isLowercaseHyphenatedUUID(value) {
		return nil, &Error{Code: ValidationFailed}
	}
	decoded, err := hex.DecodeString(strings.ReplaceAll(value, "-", ""))
	if err != nil {
		return nil, &Error{Code: ValidationFailed}
	}
	return decoded, nil
}

func isASCIIPrintable(value string) bool {
	for _, character := range value {
		if character < 0x20 || character > 0x7E {
			return false
		}
	}
	return true
}
