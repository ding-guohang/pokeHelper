package httpapi

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"porkhelper/server/internal/session"
	"porkhelper/server/internal/sync"
)

type syncHandler struct {
	upload       *sync.UploadService
	pull         *sync.PullService
	newRequestID func() string
}

// NewSyncHandler serves event upload and pull. Both routes sit behind bearer
// authentication, and ownership comes from the session rather than anything in
// the request.
func NewSyncHandler(
	upload *sync.UploadService,
	pull *sync.PullService,
	manager *session.Manager,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	handler := &syncHandler{upload: upload, pull: pull, newRequestID: newRequestID}
	authenticator := NewAuthenticator(manager, newRequestID)

	mux := http.NewServeMux()
	mux.Handle("POST /v1/sync/events", authenticator.Require(
		http.HandlerFunc(handler.uploadEvents),
	))
	mux.Handle("GET /v1/sync/events", authenticator.Require(
		http.HandlerFunc(handler.pullEvents),
	))
	return mux
}

func (h *syncHandler) uploadEvents(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	// The raw bytes matter: idempotency compares hashes of exactly what the
	// client sent, so the body is read once and reused rather than re-encoded.
	raw, err := io.ReadAll(io.LimitReader(request.Body, sync.MaxBatchBytes+1))
	if err != nil || len(raw) > sync.MaxBatchBytes {
		writeTypedError(response, http.StatusBadRequest, string(sync.ValidationFailed), requestID)
		return
	}

	var body sync.UploadBody
	if err := decodeJSONBytes(raw, &body); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(sync.ValidationFailed), requestID)
		return
	}

	result, err := h.upload.Upload(
		request.Context(),
		sync.Principal{
			UserID:               principal.UserID,
			DeviceInstallationID: principal.DeviceID,
		},
		sync.UploadCommand{
			IdempotencyKey: request.Header.Get("Idempotency-Key"),
			Body:           body,
			RawBody:        raw,
		},
	)
	if err != nil {
		writeSyncError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, result)
}

func (h *syncHandler) pullEvents(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	after, err := parseUnsigned(request.URL.Query().Get("after"), 0)
	if err != nil {
		writeTypedError(response, http.StatusBadRequest, string(sync.ValidationFailed), requestID)
		return
	}
	limit, err := parseSigned(request.URL.Query().Get("limit"), sync.MaxPullLimit)
	if err != nil {
		writeTypedError(response, http.StatusBadRequest, string(sync.ValidationFailed), requestID)
		return
	}

	page, err := h.pull.Pull(
		request.Context(),
		sync.Principal{
			UserID:               principal.UserID,
			DeviceInstallationID: principal.DeviceID,
		},
		after,
		limit,
	)
	if err != nil {
		writeSyncError(response, err, requestID)
		return
	}
	if page.Events == nil {
		page.Events = []sync.Event{}
	}
	writeJSON(response, http.StatusOK, page)
}

func writeSyncError(response http.ResponseWriter, err error, requestID string) {
	var syncError *sync.Error
	if !errors.As(err, &syncError) {
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
		return
	}
	switch syncError.Code {
	case sync.ValidationFailed:
		writeTypedError(response, http.StatusBadRequest, string(syncError.Code), requestID)
	case sync.IdempotencyReuse:
		writeTypedError(response, http.StatusConflict, string(syncError.Code), requestID)
	default:
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
	}
}

func parseUnsigned(raw string, fallback uint64) (uint64, error) {
	if raw == "" {
		return fallback, nil
	}
	return strconv.ParseUint(raw, 10, 64)
}

func parseSigned(raw string, fallback int) (int, error) {
	if raw == "" {
		return fallback, nil
	}
	return strconv.Atoi(raw)
}
