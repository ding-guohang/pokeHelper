package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"porkhelper/server/internal/session"
)

type principalContextKey struct{}

// PrincipalFrom returns the authenticated principal a bearer-protected handler
// was reached with. Handlers must take identity from here and never from the
// request body, path, or query.
func PrincipalFrom(ctx context.Context) (session.Principal, bool) {
	principal, ok := ctx.Value(principalContextKey{}).(session.Principal)
	return principal, ok
}

func withPrincipal(ctx context.Context, principal session.Principal) context.Context {
	return context.WithValue(ctx, principalContextKey{}, principal)
}

type Authenticator struct {
	manager      *session.Manager
	newRequestID func() string
}

func NewAuthenticator(manager *session.Manager, newRequestID func() string) *Authenticator {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}
	return &Authenticator{manager: manager, newRequestID: newRequestID}
}

// Require rejects any request without a live bearer access token and injects
// the resolved principal for the wrapped handler.
func (a *Authenticator) Require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		requestID := requestID(request, a.newRequestID)
		token, ok := bearerToken(request.Header.Get("Authorization"))
		if !ok {
			writeTypedError(
				response,
				http.StatusUnauthorized,
				string(session.Unauthenticated),
				requestID,
			)
			return
		}

		principal, err := a.manager.AuthenticateAccess(request.Context(), token)
		if err != nil {
			writeSessionError(response, err, requestID)
			return
		}

		next.ServeHTTP(response, request.WithContext(
			withPrincipal(request.Context(), principal),
		))
	})
}

// bearerToken parses an RFC 6750 Authorization header. The scheme is matched
// case-insensitively; the credential itself is returned untouched.
func bearerToken(header string) (string, bool) {
	scheme, credential, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return "", false
	}
	credential = strings.TrimSpace(credential)
	if credential == "" {
		return "", false
	}
	return credential, true
}

func writeSessionError(response http.ResponseWriter, err error, requestID string) {
	var sessionError *session.Error
	if !errors.As(err, &sessionError) {
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
		return
	}
	switch sessionError.Code {
	case session.ValidationFailed:
		writeTypedError(response, http.StatusBadRequest, string(sessionError.Code), requestID)
	case session.Unauthenticated:
		writeTypedError(response, http.StatusUnauthorized, string(sessionError.Code), requestID)
	case session.NotFound:
		writeTypedError(response, http.StatusNotFound, string(sessionError.Code), requestID)
	default:
		writeTypedError(response, http.StatusInternalServerError, "internalError", requestID)
	}
}
