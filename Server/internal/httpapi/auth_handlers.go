package httpapi

import (
	"context"
	"errors"
	"net"
	"net/http"
	"strconv"
	"time"

	"porkhelper/server/internal/auth"
)

type authHandler struct {
	service      *auth.Service
	newRequestID func() string
}

func NewAuthHandler(
	service *auth.Service,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	access := &authHandler{service: service, newRequestID: newRequestID}
	registration := &registrationHandler{service: service, newRequestID: newRequestID}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/register", registration.register)
	mux.HandleFunc("POST /v1/auth/verify-email", registration.verifyEmail)
	mux.HandleFunc("POST /v1/auth/login", access.login)
	mux.HandleFunc("POST /v1/auth/password-reset/request", access.requestPasswordReset)
	mux.HandleFunc("POST /v1/auth/password-reset/confirm", access.confirmPasswordReset)
	return mux
}

func (h *authHandler) login(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	var input auth.LoginInput
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}
	result, err := h.service.Login(requestContext(request), input)
	if err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, result)
}

func (h *authHandler) requestPasswordReset(
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
	accepted, err := h.service.RequestPasswordReset(requestContext(request), input.Email)
	if err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusAccepted, accepted)
}

func (h *authHandler) confirmPasswordReset(
	response http.ResponseWriter,
	request *http.Request,
) {
	requestID := requestID(request, h.newRequestID)
	var input struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}
	if input.Token == "" {
		writeTypedError(response, http.StatusBadRequest, string(auth.ChallengeInvalid), requestID)
		return
	}
	if err := h.service.ConfirmPasswordReset(
		requestContext(request),
		input.Token,
		input.Password,
	); err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

func writeAuthError(response http.ResponseWriter, err error, requestID string) {
	var authError *auth.Error
	if !errors.As(err, &authError) {
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
		return
	}
	switch authError.Code {
	case auth.ValidationFailed, auth.ChallengeInvalid:
		writeTypedError(response, http.StatusBadRequest, string(authError.Code), requestID)
	case auth.AuthenticationFailed:
		writeTypedError(response, http.StatusUnauthorized, string(authError.Code), requestID)
	case auth.RateLimited:
		seconds := int64((authError.RetryAfter + time.Second - 1) / time.Second)
		if seconds < 1 {
			seconds = 1
		}
		response.Header().Set("Retry-After", strconv.FormatInt(seconds, 10))
		writeTypedError(response, http.StatusTooManyRequests, string(authError.Code), requestID)
	default:
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
	}
}

func requestContext(request *http.Request) context.Context {
	return auth.WithNetworkSignal(request.Context(), remoteIP(request.RemoteAddr))
}

func remoteIP(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return ""
	}
	return ip.String()
}

func requestID(request *http.Request, generate func() string) string {
	if value := request.Header.Get("X-Request-ID"); value != "" {
		return value
	}
	return generate()
}
