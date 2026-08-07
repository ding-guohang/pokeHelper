package httpapi

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"

	"porkhelper/server/internal/auth"
)

type registrationHandler struct {
	service      *auth.Service
	newRequestID func() string
}

func NewRegistrationHandler(
	service *auth.Service,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	handler := &registrationHandler{service: service, newRequestID: newRequestID}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/register", handler.register)
	mux.HandleFunc("POST /v1/auth/verify-email", handler.verifyEmail)
	return mux
}

func (h *registrationHandler) register(response http.ResponseWriter, request *http.Request) {
	requestID := h.requestID(request)
	var input auth.RegisterInput
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}
	accepted, err := h.service.Register(request.Context(), input)
	if err != nil {
		h.writeAuthError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusAccepted, accepted)
}

func (h *registrationHandler) verifyEmail(response http.ResponseWriter, request *http.Request) {
	requestID := h.requestID(request)
	var input struct {
		Token string `json:"token"`
	}
	if err := decodeJSON(request, &input); err != nil || input.Token == "" {
		writeTypedError(response, http.StatusBadRequest, string(auth.ChallengeInvalid), requestID)
		return
	}
	if err := h.service.VerifyEmail(request.Context(), input.Token); err != nil {
		h.writeAuthError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

func (h *registrationHandler) writeAuthError(
	response http.ResponseWriter,
	err error,
	requestID string,
) {
	var authError *auth.Error
	if errors.As(err, &authError) {
		switch authError.Code {
		case auth.ValidationFailed, auth.ChallengeInvalid:
			writeTypedError(response, http.StatusBadRequest, string(authError.Code), requestID)
			return
		}
	}
	writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
}

func (h *registrationHandler) requestID(request *http.Request) string {
	if requestID := request.Header.Get("X-Request-ID"); requestID != "" {
		return requestID
	}
	return h.newRequestID()
}

func randomRequestID() string {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "request-id-unavailable"
	}
	return base64.RawURLEncoding.EncodeToString(value)
}
