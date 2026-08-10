package httpapi

import (
	"errors"
	"net/http"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/session"
)

type accountHandler struct {
	service      *account.Service
	newRequestID func() string
}

// NewAccountHandler serves reauthentication, export, and deletion. All three
// require a bearer session; export and deletion additionally require that the
// session authenticated recently.
func NewAccountHandler(
	service *account.Service,
	manager *session.Manager,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	handler := &accountHandler{service: service, newRequestID: newRequestID}
	authenticator := NewAuthenticator(manager, newRequestID)

	mux := http.NewServeMux()
	mux.Handle("POST /v1/auth/reauth", authenticator.Require(
		http.HandlerFunc(handler.reauthenticate),
	))
	mux.Handle("GET /v1/account/export", authenticator.Require(
		http.HandlerFunc(handler.export),
	))
	mux.Handle("DELETE /v1/account", authenticator.Require(
		http.HandlerFunc(handler.delete),
	))
	return mux
}

func (h *accountHandler) reauthenticate(
	response http.ResponseWriter,
	request *http.Request,
) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	var proof account.ReauthenticationProof
	if err := decodeJSON(request, &proof); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(account.ValidationFailed), requestID)
		return
	}

	at, err := h.service.Reauthenticate(requestContext(request), principal, proof)
	if err != nil {
		writeAccountError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, struct {
		RecentAuthAt string `json:"recentAuthAt"`
	}{RecentAuthAt: at.Format("2006-01-02T15:04:05.000Z")})
}

func (h *accountHandler) export(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	document, err := h.service.Export(request.Context(), principal)
	if err != nil {
		writeAccountError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, document)
}

func (h *accountHandler) delete(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(response, http.StatusUnauthorized, string(session.Unauthenticated), requestID)
		return
	}

	if err := h.service.Delete(request.Context(), principal); err != nil {
		writeAccountError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

func writeAccountError(response http.ResponseWriter, err error, requestID string) {
	var accountError *account.Error
	if !errors.As(err, &accountError) {
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
		return
	}
	switch accountError.Code {
	case account.ValidationFailed:
		writeTypedError(response, http.StatusBadRequest, string(accountError.Code), requestID)
	case account.AuthenticationFailed, account.ReauthenticationRequired:
		writeTypedError(response, http.StatusUnauthorized, string(accountError.Code), requestID)
	default:
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
	}
}
