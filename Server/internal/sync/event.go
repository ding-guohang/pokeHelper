package sync

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"time"
)

const (
	// SchemaVersion is the wire schema this service accepts.
	SchemaVersion = 1

	// MaxBatchEvents and MaxBatchBytes bound a single upload so one client
	// cannot force an unbounded transaction.
	MaxBatchEvents = 100
	MaxBatchBytes  = 1 << 20

	MinPullLimit = 1
	MaxPullLimit = 200
)

type ErrorCode string

const (
	ValidationFailed ErrorCode = "validationFailed"
	IdempotencyReuse ErrorCode = "idempotencyKeyReused"
)

type Error struct {
	Code ErrorCode
	Err  error
}

func (e *Error) Error() string {
	return fmt.Sprintf("sync: %s", e.Code)
}

func (e *Error) Unwrap() error {
	return e.Err
}

// Event mirrors the client's training event.
//
// Fields are declared in alphabetical order because encoding/json emits struct
// fields in declaration order, and the canonical body the client hashes uses
// sorted keys. Reordering these fields would silently break every idempotent
// retry.
type Event struct {
	AbilityDimension       string          `json:"abilityDimension"`
	DeviceID               string          `json:"deviceID"`
	Grade                  json.RawMessage `json:"grade"`
	ID                     string          `json:"id"`
	LocalUserID            string          `json:"localUserID"`
	OccurredAt             string          `json:"occurredAt"`
	ScenarioID             string          `json:"scenarioID"`
	StrategyContentVersion string          `json:"strategyContentVersion"`
	StrategyPackID         string          `json:"strategyPackID"`
	Submission             json.RawMessage `json:"submission"`
}

// UploadBody is the request shape. Field order is alphabetical for the same
// reason as Event.
type UploadBody struct {
	Events        []Event `json:"events"`
	SchemaVersion int     `json:"schemaVersion"`
}

type UploadCommand struct {
	IdempotencyKey string
	Body           UploadBody
	// RawBody is what the client actually sent. Idempotency compares hashes of
	// these bytes, so a replay is recognized only when it is byte-identical.
	RawBody []byte
}

type UploadResult struct {
	AcceptedEventIDs []string `json:"acceptedEventIDs"`
	Checkpoint       uint64   `json:"checkpoint"`
}

type EventPage struct {
	Events     []Event `json:"events"`
	Checkpoint uint64  `json:"checkpoint"`
	HasMore    bool    `json:"hasMore"`
}

// HashUploadRequest returns the canonical hash of an upload.
//
// It re-encodes rather than hashing whatever arrived, so the hash is a property
// of the request's meaning. Callers pair it with CanonicalBody to reject bodies
// that are semantically equal but not byte-canonical.
func HashUploadRequest(command UploadCommand) ([32]byte, error) {
	canonical, err := CanonicalBody(command.Body)
	if err != nil {
		return [32]byte{}, err
	}
	return sha256.Sum256(canonical), nil
}

func CanonicalBody(body UploadBody) ([]byte, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, &Error{Code: ValidationFailed, Err: err}
	}
	return encoded, nil
}

// ParseOccurredAt accepts the client's UTC RFC 3339 encoding with millisecond
// precision.
func ParseOccurredAt(value string) (time.Time, error) {
	parsed, err := time.Parse("2006-01-02T15:04:05.000Z07:00", value)
	if err != nil {
		return time.Time{}, &Error{Code: ValidationFailed, Err: err}
	}
	return parsed.UTC(), nil
}
