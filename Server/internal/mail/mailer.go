package mail

import "context"

type Message struct {
	To      string
	Subject string
	Body    string
}

type Mailer interface {
	Deliver(context.Context, Message) error
}
