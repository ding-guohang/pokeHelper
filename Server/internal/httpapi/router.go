package httpapi

import (
	"net/http"

	"porkhelper/server/internal/account"
	"porkhelper/server/internal/auth"
	"porkhelper/server/internal/session"
	"porkhelper/server/internal/sync"
)

// Handlers are the feature mounts the service exposes. Each is built and
// tested independently; the router only composes them.
type Handlers struct {
	Auth    *auth.Service
	Apple   *auth.AppleService
	Account *account.Service
	Upload  *sync.UploadService
	Pull    *sync.PullService
	Session *session.Manager

	// Development-only routes. Nil in production, which is what keeps them
	// from existing there at all rather than sitting behind a flag.
	Development http.Handler
}

// NewRouter composes every feature handler into one entry point.
//
// Each feature owns its own mux so it stays independently testable. They are
// tried in order and a mux that matches nothing falls through to the next,
// which keeps a missing mount visible in this one file rather than spread
// across packages.
func NewRouter(handlers Handlers, newRequestID func() string) http.Handler {
	if newRequestID == nil {
		newRequestID = randomRequestID
	}

	health := http.NewServeMux()
	health.HandleFunc("GET /health", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, struct {
			Status string `json:"status"`
		}{Status: "ok"})
	})

	mounted := firstMatch{
		health,
		NewAuthHandler(handlers.Auth, newRequestID),
		NewSessionHandler(handlers.Session, newRequestID),
		NewAppleHandler(handlers.Apple, handlers.Session, newRequestID),
		NewAccountHandler(handlers.Account, handlers.Session, newRequestID),
		NewSyncHandler(handlers.Upload, handlers.Pull, handlers.Session, newRequestID),
	}
	if handlers.Development != nil {
		mounted = append(mounted, handlers.Development)
	}
	return mounted
}

// firstMatch serves the request with the first mux that has a pattern for it.
type firstMatch []http.Handler

func (f firstMatch) ServeHTTP(response http.ResponseWriter, request *http.Request) {
	for _, handler := range f {
		if mux, ok := handler.(*http.ServeMux); ok {
			if _, pattern := mux.Handler(request); pattern == "" {
				continue
			}
		}
		handler.ServeHTTP(response, request)
		return
	}
	http.NotFound(response, request)
}
