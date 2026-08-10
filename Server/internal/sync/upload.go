package sync

import (
	"context"
	"fmt"
)

// Principal is the sync package's view of an authenticated caller. Like the
// auth package, it avoids importing session so the dependency stays one-way.
type Principal struct {
	UserID               string
	DeviceInstallationID string
}

// Upload accepts a batch of events for the authenticated user.
//
// The payload's localUserID and deviceID are stored as history but never used
// to decide ownership; a client that forges them still writes only to its own
// account.
func (s *UploadService) Upload(
	ctx context.Context,
	principal Principal,
	command UploadCommand,
) (UploadResult, error) {
	if principal.UserID == "" {
		return UploadResult{}, &Error{Code: ValidationFailed}
	}
	if err := ValidateUpload(command); err != nil {
		return UploadResult{}, err
	}

	hash, err := HashUploadRequest(command)
	if err != nil {
		return UploadResult{}, err
	}

	result, err := s.store.Upload(ctx, UploadRequest{
		UserID:               principal.UserID,
		DeviceInstallationID: principal.DeviceInstallationID,
		IdempotencyKey:       command.IdempotencyKey,
		RequestHash:          hash,
		Events:               command.Body.Events,
	})
	if err != nil {
		return UploadResult{}, err
	}
	return result, nil
}

// Pull returns events after the caller's checkpoint in server order.
//
// A non-empty page reports the last returned sequence as the new checkpoint;
// an empty page returns the requested one, so an idle client never moves
// backwards or skips ahead.
func (s *PullService) Pull(
	ctx context.Context,
	principal Principal,
	after uint64,
	limit int,
) (EventPage, error) {
	if principal.UserID == "" {
		return EventPage{}, &Error{Code: ValidationFailed}
	}
	if err := ValidatePullLimit(limit); err != nil {
		return EventPage{}, err
	}

	// One extra row tells us whether another page exists without a second
	// query or a count.
	stored, err := s.store.Pull(ctx, principal.UserID, after, limit+1)
	if err != nil {
		return EventPage{}, fmt.Errorf("sync: pull events: %w", err)
	}

	hasMore := len(stored) > limit
	if hasMore {
		stored = stored[:limit]
	}

	checkpoint := after
	if len(stored) > 0 {
		checkpoint = stored[len(stored)-1].ServerSequence
	}

	events := make([]Event, 0, len(stored))
	for _, row := range stored {
		events = append(events, row.Event)
	}

	return EventPage{Events: events, Checkpoint: checkpoint, HasMore: hasMore}, nil
}
