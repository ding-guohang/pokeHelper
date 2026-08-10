package sync

import (
	"context"
)

// UploadStore performs the whole upload in one transaction. Splitting it into
// separate calls would let a crash leave a sequence allocated with no event, or
// an idempotency record with no response.
type UploadStore interface {
	Upload(context.Context, UploadRequest) (UploadResult, error)
}

type UploadRequest struct {
	// UserID and DeviceInstallationID come from the bearer session, never from
	// the payload.
	UserID               string
	DeviceInstallationID string
	IdempotencyKey       string
	RequestHash          [32]byte
	Events               []Event
}

// StoredEvent pairs an event with its server order. The sequence is server
// state, not part of the client's event, so it is kept outside Event rather
// than leaking into the canonical upload shape.
type StoredEvent struct {
	Event          Event
	ServerSequence uint64
}

type PullStore interface {
	Pull(context.Context, string, uint64, int) ([]StoredEvent, error)
}

type UploadService struct {
	store UploadStore
}

func NewUploadService(store UploadStore) *UploadService {
	return &UploadService{store: store}
}

type PullService struct {
	store PullStore
}

func NewPullService(store PullStore) *PullService {
	return &PullService{store: store}
}
