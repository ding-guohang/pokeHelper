package httpapi

import (
	"net/http"

	"porkhelper/server/internal/config"
	"porkhelper/server/internal/mail"
)

// NewDevelopmentMailboxHandler exposes the in-memory mailbox so an automated
// end-to-end run can read a verification token.
//
// It returns nil outside development. That is the whole safety argument: the
// route does not exist in a production process, rather than existing behind a
// flag someone could flip. The release gate asserts this constructor is still
// environment-gated.
func NewDevelopmentMailboxHandler(
	environment config.Environment,
	mailbox *mail.DevelopmentMailbox,
	newRequestID func() string,
) http.Handler {
	if environment == config.Production || mailbox == nil {
		return nil
	}
	if newRequestID == nil {
		newRequestID = randomRequestID
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/dev/mailbox", func(
		response http.ResponseWriter,
		request *http.Request,
	) {
		messages := mailbox.Messages()
		payload := make([]developmentMessage, 0, len(messages))
		for _, message := range messages {
			payload = append(payload, developmentMessage{
				To:      message.To,
				Subject: message.Subject,
				Body:    message.Body,
			})
		}
		writeJSON(response, http.StatusOK, developmentMailbox{Messages: payload})
	})
	return mux
}

type developmentMailbox struct {
	Messages []developmentMessage `json:"messages"`
}

type developmentMessage struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}
