package mysqlstore

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"porkhelper/server/internal/sync"
)

type SyncStore struct {
	db *sql.DB
}

func NewSyncStore(db *sql.DB) *SyncStore {
	return &SyncStore{db: db}
}

var (
	_ sync.UploadStore = (*SyncStore)(nil)
	_ sync.PullStore   = (*SyncStore)(nil)
)

// Upload applies a batch in one transaction, in a fixed order.
//
// The per-user sequence row is locked first, which serializes every upload for
// that account. Two concurrent uploads therefore cannot interleave sequence
// allocation, and a reader can never observe a larger sequence committed before
// a smaller one.
func (s *SyncStore) Upload(
	ctx context.Context,
	request sync.UploadRequest,
) (result sync.UploadResult, err error) {
	userID, err := sync.UUIDBytes(request.UserID)
	if err != nil {
		return sync.UploadResult{}, err
	}

	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return sync.UploadResult{}, fmt.Errorf("begin upload: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	// 1. Serialize this user's uploads.
	var nextSequence uint64
	err = tx.QueryRowContext(ctx, `
		SELECT next_sequence FROM user_sync_sequences
		WHERE user_id = ?
		FOR UPDATE`,
		userID,
	).Scan(&nextSequence)
	if errors.Is(err, sql.ErrNoRows) {
		return sync.UploadResult{}, &sync.Error{Code: sync.ValidationFailed}
	}
	if err != nil {
		return sync.UploadResult{}, fmt.Errorf("lock sync sequence: %w", err)
	}

	// 2. A replay of the same key must return the original response, and the
	// same key with different content must be refused rather than silently
	// applied under a key the client believes means something else.
	replayed, found, err := lookupIdempotentResponse(
		ctx, tx, userID, request.IdempotencyKey, request.RequestHash,
	)
	if err != nil {
		return sync.UploadResult{}, err
	}
	if found {
		if err = tx.Commit(); err != nil {
			return sync.UploadResult{}, fmt.Errorf("commit replay: %w", err)
		}
		return replayed, nil
	}

	deviceID, err := resolveDeviceID(ctx, tx, userID, request.DeviceInstallationID)
	if err != nil {
		return sync.UploadResult{}, err
	}

	// 3. Allocate sequences for events this user has not stored yet.
	accepted := make([]string, 0, len(request.Events))
	sequence := nextSequence
	for _, event := range request.Events {
		eventID, uuidErr := sync.UUIDBytes(event.ID)
		if uuidErr != nil {
			err = uuidErr
			return sync.UploadResult{}, err
		}

		var exists int
		err = tx.QueryRowContext(ctx, `
			SELECT COUNT(*) FROM training_events
			WHERE user_id = ? AND event_id = ?`,
			userID, eventID,
		).Scan(&exists)
		if err != nil {
			return sync.UploadResult{}, fmt.Errorf("check existing event: %w", err)
		}
		if exists > 0 {
			// Already stored: accepted, but it keeps its original sequence.
			accepted = append(accepted, event.ID)
			continue
		}

		occurredAt, parseErr := sync.ParseOccurredAt(event.OccurredAt)
		if parseErr != nil {
			err = parseErr
			return sync.UploadResult{}, err
		}

		payload, marshalErr := json.Marshal(event)
		if marshalErr != nil {
			err = &sync.Error{Code: sync.ValidationFailed, Err: marshalErr}
			return sync.UploadResult{}, err
		}

		sequence++
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO training_events (
				user_id, event_id, device_id, server_sequence, occurred_at, payload
			) VALUES (?, ?, ?, ?, ?, ?)`,
			userID, eventID, deviceID, sequence, occurredAt, payload,
		); err != nil {
			return sync.UploadResult{}, fmt.Errorf("insert training event: %w", err)
		}
		accepted = append(accepted, event.ID)
	}

	if sequence != nextSequence {
		if _, err = tx.ExecContext(ctx, `
			UPDATE user_sync_sequences SET next_sequence = ? WHERE user_id = ?`,
			sequence, userID,
		); err != nil {
			return sync.UploadResult{}, fmt.Errorf("advance sync sequence: %w", err)
		}
	}

	result = sync.UploadResult{AcceptedEventIDs: accepted, Checkpoint: sequence}

	// 4. Persist the response in the same transaction, so a replay after a
	// crash returns exactly what the first attempt would have returned.
	response, err := json.Marshal(result)
	if err != nil {
		return sync.UploadResult{}, fmt.Errorf("encode upload response: %w", err)
	}
	hash := request.RequestHash
	if _, err = tx.ExecContext(ctx, `
		INSERT INTO idempotency_records (user_id, idempotency_key, request_hash, response_json)
		VALUES (?, ?, ?, ?)`,
		userID, request.IdempotencyKey, hash[:], response,
	); err != nil {
		if isDuplicateKey(err) {
			// Another transaction inserted the same key first; its response is
			// authoritative.
			err = &sync.Error{Code: sync.IdempotencyReuse}
			return sync.UploadResult{}, err
		}
		return sync.UploadResult{}, fmt.Errorf("record idempotency: %w", err)
	}

	// 5. Commit.
	if err = tx.Commit(); err != nil {
		return sync.UploadResult{}, fmt.Errorf("commit upload: %w", err)
	}
	return result, nil
}

func lookupIdempotentResponse(
	ctx context.Context,
	tx *sql.Tx,
	userID []byte,
	key string,
	hash [32]byte,
) (sync.UploadResult, bool, error) {
	var storedHash []byte
	var response []byte
	err := tx.QueryRowContext(ctx, `
		SELECT request_hash, response_json FROM idempotency_records
		WHERE user_id = ? AND idempotency_key = ?`,
		userID, key,
	).Scan(&storedHash, &response)
	if errors.Is(err, sql.ErrNoRows) {
		return sync.UploadResult{}, false, nil
	}
	if err != nil {
		return sync.UploadResult{}, false, fmt.Errorf("lookup idempotency record: %w", err)
	}

	if len(storedHash) != len(hash) || string(storedHash) != string(hash[:]) {
		return sync.UploadResult{}, false, &sync.Error{Code: sync.IdempotencyReuse}
	}

	var result sync.UploadResult
	if err := json.Unmarshal(response, &result); err != nil {
		return sync.UploadResult{}, false, fmt.Errorf("decode stored response: %w", err)
	}
	return result, true, nil
}

func resolveDeviceID(
	ctx context.Context,
	tx *sql.Tx,
	userID []byte,
	installationID string,
) ([]byte, error) {
	installation, err := sync.UUIDBytes(installationID)
	if err != nil {
		return nil, err
	}
	var deviceID []byte
	err = tx.QueryRowContext(ctx, `
		SELECT id FROM devices WHERE user_id = ? AND installation_id = ?`,
		userID, installation,
	).Scan(&deviceID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, &sync.Error{Code: sync.ValidationFailed}
	}
	if err != nil {
		return nil, fmt.Errorf("resolve upload device: %w", err)
	}
	return deviceID, nil
}

// Pull returns events in server order after the caller's checkpoint.
func (s *SyncStore) Pull(
	ctx context.Context,
	userID string,
	after uint64,
	limit int,
) ([]sync.StoredEvent, error) {
	owner, err := sync.UUIDBytes(userID)
	if err != nil {
		return nil, err
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT server_sequence, payload FROM training_events
		WHERE user_id = ? AND server_sequence > ?
		ORDER BY server_sequence
		LIMIT ?`,
		owner, after, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("pull training events: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var events []sync.StoredEvent
	for rows.Next() {
		var sequence uint64
		var payload []byte
		if err := rows.Scan(&sequence, &payload); err != nil {
			return nil, fmt.Errorf("scan training event: %w", err)
		}
		var event sync.Event
		if err := json.Unmarshal(payload, &event); err != nil {
			return nil, fmt.Errorf("decode stored event: %w", err)
		}
		events = append(events, sync.StoredEvent{Event: event, ServerSequence: sequence})
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate training events: %w", err)
	}
	return events, nil
}
