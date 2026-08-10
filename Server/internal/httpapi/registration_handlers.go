package httpapi

import (
	"crypto/rand"
	"encoding/base64"
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
	mux.HandleFunc("POST /v1/auth/resend-verification", handler.resendVerification)
	return mux
}

func (h *registrationHandler) register(response http.ResponseWriter, request *http.Request) {
	requestID := h.requestID(request)
	var input auth.RegisterInput
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}
	accepted, err := h.service.Register(requestContext(request), input)
	if err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusAccepted, accepted)
}

func (h *registrationHandler) resendVerification(
	response http.ResponseWriter,
	request *http.Request,
) {
	requestID := requestID(request, h.newRequestID)
	var input struct {
		Email string `json:"email"`
	}
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}

	accepted, err := h.service.ResendVerification(requestContext(request), input.Email)
	if err != nil {
		writeAuthError(response, err, requestID)
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
	if err := h.service.VerifyEmail(requestContext(request), input.Token); err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

func (h *registrationHandler) requestID(request *http.Request) string {
	return requestID(request, h.newRequestID)
}

func randomRequestID() string {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "request-id-unavailable"
	}
	return base64.RawURLEncoding.EncodeToString(value)
}
