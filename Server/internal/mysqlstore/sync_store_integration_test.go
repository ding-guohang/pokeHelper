//go:build integration

package mysqlstore_test

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	stdsync "sync"
	"testing"
	"time"

	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/internal/sync"
	"porkhelper/server/migrations"
	"porkhelper/server/test/mysqltest"
)

func TestUploadStoresEventsAndAllocatesSequences(t *testing.T) {
	db, store, owner := newSyncFixture(t)

	result, err := store.Upload(context.Background(), uploadRequest(owner, "batch-1", 2))
	if err != nil {
		t.Fatalf("upload: %v", err)
	}

	if len(result.AcceptedEventIDs) != 2 {
		t.Fatalf("accepted %d events, want 2", len(result.AcceptedEventIDs))
	}
	if result.Checkpoint != 2 {
		t.Errorf("checkpoint = %d, want 2", result.Checkpoint)
	}

	var stored int
	if err := db.QueryRow(
		"SELECT COUNT(*) FROM training_events WHERE user_id = UNHEX(REPLACE(?, '-', ''))",
		owner.userID,
	).Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 2 {
		t.Errorf("stored %d events, want 2", stored)
	}
}

// A retry after a lost response must return the original answer, not apply the
// batch a second time.
func TestReplayingTheSameKeyAndHashReturnsTheOriginalResponse(t *testing.T) {
	db, store, owner := newSyncFixture(t)
	request := uploadRequest(owner, "batch-1", 2)

	first, err := store.Upload(context.Background(), request)
	if err != nil {
		t.Fatalf("first upload: %v", err)
	}
	second, err := store.Upload(context.Background(), request)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}

	if second.Checkpoint != first.Checkpoint {
		t.Errorf("replay checkpoint = %d, want %d", second.Checkpoint, first.Checkpoint)
	}
	var stored int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 2 {
		t.Errorf("replay stored %d events, want the original 2", stored)
	}
}

// Reusing a key for different content is a client bug that must not silently
// apply under a key the client believes means something else.
func TestSameKeyWithADifferentHashIsRefusedAndRollsBack(t *testing.T) {
	db, store, owner := newSyncFixture(t)
	if _, err := store.Upload(context.Background(), uploadRequest(owner, "batch-1", 1)); err != nil {
		t.Fatalf("first upload: %v", err)
	}

	conflicting := uploadRequest(owner, "batch-1", 2)
	_, err := store.Upload(context.Background(), conflicting)

	var syncError *sync.Error
	if !errors.As(err, &syncError) || syncError.Code != sync.IdempotencyReuse {
		t.Fatalf("error = %v, want idempotencyKeyReused", err)
	}
	var stored int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 1 {
		t.Errorf("a refused batch left %d events, want the original 1", stored)
	}
}

func TestAnEventAlreadyStoredIsAcceptedWithoutDuplication(t *testing.T) {
	db, store, owner := newSyncFixture(t)
	first := uploadRequest(owner, "batch-1", 1)
	if _, err := store.Upload(context.Background(), first); err != nil {
		t.Fatalf("first upload: %v", err)
	}

	// A different key carrying the same event, as happens when an
	// acknowledgement is lost and the client rebuilds its batch.
	repeat := uploadRequest(owner, "batch-2", 1)
	result, err := store.Upload(context.Background(), repeat)
	if err != nil {
		t.Fatalf("repeat upload: %v", err)
	}

	if len(result.AcceptedEventIDs) != 1 {
		t.Errorf("accepted %d events, want 1", len(result.AcceptedEventIDs))
	}
	var stored int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 1 {
		t.Errorf("stored %d rows for one event, want 1", stored)
	}
}

func TestAMalformedOccurredAtRollsBackTheWholeBatch(t *testing.T) {
	db, store, owner := newSyncFixture(t)
	request := uploadRequest(owner, "batch-1", 2)
	request.Events[1].OccurredAt = "2026-08-07"

	if _, err := store.Upload(context.Background(), request); err == nil {
		t.Fatal("a malformed timestamp must fail the batch")
	}

	var stored int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 0 {
		t.Errorf("a failed batch left %d events, want none", stored)
	}

	var sequence uint64
	if err := db.QueryRow(
		"SELECT next_sequence FROM user_sync_sequences WHERE user_id = UNHEX(REPLACE(?, '-', ''))",
		owner.userID,
	).Scan(&sequence); err != nil {
		t.Fatalf("read sequence: %v", err)
	}
	if sequence != 0 {
		t.Errorf("a failed batch advanced the sequence to %d", sequence)
	}
}

// Sequence allocation is serialized per user. While one upload holds the
// sequence row, a second cannot allocate, so a reader can never see a larger
// sequence committed before a smaller one.
func TestConcurrentUploadsForOneUserCannotInterleaveSequences(t *testing.T) {
	db, store, owner := newSyncFixture(t)

	// Hold the sequence row exactly as an in-progress upload would.
	holder, err := db.BeginTx(context.Background(), &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
	})
	if err != nil {
		t.Fatalf("begin holder: %v", err)
	}
	var held uint64
	if err := holder.QueryRow(
		"SELECT next_sequence FROM user_sync_sequences WHERE user_id = UNHEX(REPLACE(?, '-', '')) FOR UPDATE",
		owner.userID,
	).Scan(&held); err != nil {
		t.Fatalf("hold sequence row: %v", err)
	}

	blocked := make(chan error, 1)
	go func() {
		_, err := store.Upload(context.Background(), uploadRequest(owner, "batch-2", 1))
		blocked <- err
	}()

	select {
	case err := <-blocked:
		t.Fatalf("upload proceeded while the sequence row was held: %v", err)
	case <-time.After(400 * time.Millisecond):
		// Correctly blocked.
	}

	// A third reader must not observe any event yet.
	var visible int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&visible); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if visible != 0 {
		t.Errorf("reader saw %d uncommitted events", visible)
	}

	if err := holder.Rollback(); err != nil {
		t.Fatalf("release holder: %v", err)
	}
	if err := <-blocked; err != nil {
		t.Fatalf("upload after release: %v", err)
	}

	var sequence uint64
	if err := db.QueryRow(
		"SELECT server_sequence FROM training_events LIMIT 1",
	).Scan(&sequence); err != nil {
		t.Fatalf("read sequence: %v", err)
	}
	if sequence != 1 {
		t.Errorf("first event got sequence %d, want 1", sequence)
	}
}

func TestPullReturnsEventsInServerOrderAfterTheCheckpoint(t *testing.T) {
	_, store, owner := newSyncFixture(t)
	if _, err := store.Upload(context.Background(), uploadRequest(owner, "batch-1", 3)); err != nil {
		t.Fatalf("upload: %v", err)
	}

	page, err := store.Pull(context.Background(), owner.userID, 1, 10)
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(page) != 2 {
		t.Fatalf("pulled %d events after checkpoint 1, want 2", len(page))
	}
	if page[0].ServerSequence != 2 || page[1].ServerSequence != 3 {
		t.Errorf("sequences = %d,%d want 2,3", page[0].ServerSequence, page[1].ServerSequence)
	}
}

func TestPullIsScopedToItsOwner(t *testing.T) {
	db, store, owner := newSyncFixture(t)
	stranger := createSyncUser(t, db)
	if _, err := store.Upload(context.Background(), uploadRequest(owner, "batch-1", 1)); err != nil {
		t.Fatalf("upload: %v", err)
	}

	page, err := store.Pull(context.Background(), stranger.userID, 0, 10)
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(page) != 0 {
		t.Errorf("another user's pull returned %d events", len(page))
	}
}

type syncOwner struct {
	userID         string
	installationID string
}

func newSyncFixture(t *testing.T) (*sql.DB, *mysqlstore.SyncStore, syncOwner) {
	t.Helper()
	db := mysqltest.Database(t)
	if err := migrations.Apply(context.Background(), db); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	return db, mysqlstore.NewSyncStore(db), createSyncUser(t, db)
}

func createSyncUser(t *testing.T, db *sql.DB) syncOwner {
	t.Helper()
	userID := randomUUIDString(t)
	installationID := randomUUIDString(t)
	deviceID := randomUUIDString(t)

	if _, err := db.Exec(
		"INSERT INTO users (id) VALUES (UNHEX(REPLACE(?, '-', '')))", userID,
	); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := db.Exec(
		"INSERT INTO user_sync_sequences (user_id, next_sequence) VALUES (UNHEX(REPLACE(?, '-', '')), 0)",
		userID,
	); err != nil {
		t.Fatalf("insert sequence: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO devices (id, user_id, installation_id, display_name, platform, app_version)
		VALUES (UNHEX(REPLACE(?, '-', '')), UNHEX(REPLACE(?, '-', '')), UNHEX(REPLACE(?, '-', '')), 'iPhone', 'iOS', '1.0.0')`,
		deviceID, userID, installationID,
	); err != nil {
		t.Fatalf("insert device: %v", err)
	}
	return syncOwner{userID: userID, installationID: installationID}
}

func uploadRequest(owner syncOwner, key string, events int) sync.UploadRequest {
	body := sync.UploadBody{SchemaVersion: sync.SchemaVersion}
	for index := 0; index < events; index++ {
		body.Events = append(body.Events, sync.Event{
			AbilityDimension:       "bet-sizing",
			DeviceID:               owner.installationID,
			Grade:                  json.RawMessage(`{"score":100}`),
			ID:                     fmt.Sprintf("00000000-0000-4000-8000-%012d", index+1),
			LocalUserID:            "10000000-0000-4000-8000-000000000001",
			OccurredAt:             "2026-08-07T00:00:00.000Z",
			ScenarioID:             "scenario-1",
			StrategyContentVersion: "2026.08.06",
			StrategyPackID:         "cash-pack",
			Submission:             json.RawMessage(`{"confidence":"verySure"}`),
		})
	}
	canonical, _ := sync.CanonicalBody(body)
	return sync.UploadRequest{
		UserID:               owner.userID,
		DeviceInstallationID: owner.installationID,
		IdempotencyKey:       key,
		RequestHash:          sha256.Sum256(canonical),
		Events:               body.Events,
	}
}

func randomUUIDString(t *testing.T) string {
	t.Helper()
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		t.Fatalf("generate uuid: %v", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf(
		"%08x-%04x-%04x-%04x-%012x",
		value[0:4], value[4:6], value[6:8], value[8:10], value[10:16],
	)
}

// The per-user sequence lock is what makes duplicate handling safe under
// concurrency. Only a sequential test existed, which cannot distinguish
// "serialized correctly" from "got lucky".
func TestConcurrentUploadsOfTheSameEventStoreItOnce(t *testing.T) {
	db, store, owner := newSyncFixture(t)

	const callers = 4
	var group stdsync.WaitGroup
	errs := make([]error, callers)
	group.Add(callers)
	for index := range errs {
		go func() {
			defer group.Done()
			_, errs[index] = store.Upload(
				context.Background(),
				uploadRequest(owner, "shared-key", 1),
			)
		}()
	}
	group.Wait()

	for index, err := range errs {
		if err != nil {
			t.Fatalf("caller %d: %v", index, err)
		}
	}
	var stored int
	if err := db.QueryRow("SELECT COUNT(*) FROM training_events").Scan(&stored); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if stored != 1 {
		t.Errorf("stored %d rows for one event, want 1", stored)
	}
}

// Two concurrent uploads of *different* events must produce strictly
// increasing sequences with no gap and no reuse.
func TestConcurrentUploadsAllocateStrictlyIncreasingSequences(t *testing.T) {
	db, store, owner := newSyncFixture(t)

	var group stdsync.WaitGroup
	group.Add(2)
	errs := make([]error, 2)
	for index := range errs {
		go func() {
			defer group.Done()
			request := uploadRequest(owner, fmt.Sprintf("batch-%d", index), 1)
			request.Events[0].ID = fmt.Sprintf("00000000-0000-4000-8000-%012d", index+100)
			canonical, _ := sync.CanonicalBody(sync.UploadBody{
				SchemaVersion: sync.SchemaVersion,
				Events:        request.Events,
			})
			request.RequestHash = sha256.Sum256(canonical)
			_, errs[index] = store.Upload(context.Background(), request)
		}()
	}
	group.Wait()

	for index, err := range errs {
		if err != nil {
			t.Fatalf("caller %d: %v", index, err)
		}
	}

	rows, err := db.Query(`
		SELECT server_sequence FROM training_events
		WHERE user_id = UNHEX(REPLACE(?, '-', '')) ORDER BY server_sequence`,
		owner.userID,
	)
	if err != nil {
		t.Fatalf("read sequences: %v", err)
	}
	defer func() { _ = rows.Close() }()

	var sequences []uint64
	for rows.Next() {
		var sequence uint64
		if err := rows.Scan(&sequence); err != nil {
			t.Fatalf("scan sequence: %v", err)
		}
		sequences = append(sequences, sequence)
	}
	if len(sequences) != 2 {
		t.Fatalf("stored %d events, want 2", len(sequences))
	}
	if sequences[0] != 1 || sequences[1] != 2 {
		t.Errorf("sequences = %v, want 1 then 2 with no gap or reuse", sequences)
	}
}

// A replay must return the original answer in full. Comparing only the
// checkpoint would miss a response that confirmed a different set of events.
func TestAReplayReturnsTheIdenticalAcceptedSet(t *testing.T) {
	_, store, owner := newSyncFixture(t)
	request := uploadRequest(owner, "batch-1", 3)

	first, err := store.Upload(context.Background(), request)
	if err != nil {
		t.Fatalf("first upload: %v", err)
	}
	second, err := store.Upload(context.Background(), request)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}

	if len(second.AcceptedEventIDs) != len(first.AcceptedEventIDs) {
		t.Fatalf(
			"replay accepted %d events, want the original %d",
			len(second.AcceptedEventIDs), len(first.AcceptedEventIDs),
		)
	}
	for index := range first.AcceptedEventIDs {
		if second.AcceptedEventIDs[index] != first.AcceptedEventIDs[index] {
			t.Errorf(
				"replay accepted %v, want the original %v",
				second.AcceptedEventIDs, first.AcceptedEventIDs,
			)
			break
		}
	}
}
