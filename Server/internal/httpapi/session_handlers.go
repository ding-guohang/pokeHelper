package httpapi

import (
	"net/http"

	"porkhelper/server/internal/session"
)

type sessionHandler struct {
	manager      *session.Manager
	newRequestID func() string
}

type deviceListResponse struct {
	Devices []session.DeviceSession `json:"devices"`
}

// NewSessionHandler serves refresh, logout, and device-session management.
// Device routes sit behind bearer authentication; refresh and logout
// authenticate with the presented refresh token itself.
func NewSessionHandler(
	manager *session.Manager,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	handler := &sessionHandler{manager: manager, newRequestID: newRequestID}
	authenticator := NewAuthenticator(manager, newRequestID)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/refresh", handler.refresh)
	mux.HandleFunc("POST /v1/auth/logout", handler.logout)
	mux.Handle("GET /v1/sessions", authenticator.Require(
		http.HandlerFunc(handler.listDevices),
	))
	mux.Handle("DELETE /v1/sessions/{sessionID}", authenticator.Require(
		http.HandlerFunc(handler.revokeDevice),
	))
	return mux
}

func (h *sessionHandler) refresh(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	var input struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(session.ValidationFailed), requestID)
		return
	}

	pair, err := h.manager.Refresh(request.Context(), input.RefreshToken)
	if err != nil {
		writeSessionError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, pair)
}

func (h *sessionHandler) logout(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	var input struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(session.ValidationFailed), requestID)
		return
	}

	if err := h.manager.Logout(request.Context(), input.RefreshToken); err != nil {
		writeSessionError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

func (h *sessionHandler) listDevices(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	devices, err := h.manager.ListDevices(request.Context(), principal)
	if err != nil {
		writeSessionError(response, err, requestID)
		return
	}
	if devices == nil {
		devices = []session.DeviceSession{}
	}
	writeJSON(response, http.StatusOK, deviceListResponse{Devices: devices})
}

func (h *sessionHandler) revokeDevice(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	if err := h.manager.RevokeSession(
		request.Context(),
		principal,
		request.PathValue("sessionID"),
	); err != nil {
		writeSessionError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}
