package httpapi

import (
	"net/http"

	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/session"
)

type appleHandler struct {
	service      *auth.AppleService
	newRequestID func() string
}

// NewAppleHandler serves Sign in with Apple. Sign-in is unauthenticated;
// linking sits behind a bearer session because it merges an Apple identity
// into an existing account.
func NewAppleHandler(
	service *auth.AppleService,
	manager *session.Manager,
	newRequestID func() string,
) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	handler := &appleHandler{service: service, newRequestID: newRequestID}
	authenticator := NewAuthenticator(manager, newRequestID)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/apple", handler.signIn)
	mux.Handle("POST /v1/auth/apple/link", authenticator.Require(
		http.HandlerFunc(handler.link),
	))
	return mux
}

func (h *appleHandler) signIn(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	var input auth.AppleSignInInput
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}

	result, err := h.service.SignIn(requestContext(request), input)
	if err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	writeJSON(response, http.StatusOK, result)
}

func (h *appleHandler) link(response http.ResponseWriter, request *http.Request) {
	requestID := requestID(request, h.newRequestID)
	principal, ok := PrincipalFrom(request.Context())
	if !ok {
		writeTypedError(
			response,
			http.StatusUnauthorized,
			string(session.Unauthenticated),
			requestID,
		)
		return
	}

	var input auth.AppleLinkInput
	if err := decodeJSON(request, &input); err != nil {
		writeTypedError(response, http.StatusBadRequest, string(auth.ValidationFailed), requestID)
		return
	}

	if err := h.service.Link(
		requestContext(request),
		authPrincipal(principal),
		input,
	); err != nil {
		writeAuthError(response, err, requestID)
		return
	}
	response.WriteHeader(http.StatusNoContent)
}

// authPrincipal converts the bearer session principal into the auth package's
// own principal. The conversion lives here because auth must not import
// session: session already imports auth for SessionIssuer.
func authPrincipal(principal session.Principal) auth.Principal {
	return auth.Principal{
		UserID:       principal.UserID,
		SessionID:    principal.SessionID,
		RecentAuthAt: principal.RecentAuthAt,
	}
}
