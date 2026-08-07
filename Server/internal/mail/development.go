package mail

import (
	"context"
	"sync"
)

type DevelopmentMailbox struct {
	mu       sync.Mutex
	messages []Message
}

func (m *DevelopmentMailbox) store(message Message) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.messages = append(m.messages, message)
}

func (m *DevelopmentMailbox) Messages() []Message {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Message(nil), m.messages...)
}

type DevelopmentMailer struct {
	mailbox *DevelopmentMailbox
}

func NewDevelopmentMailer(
	environment string,
	mailbox *DevelopmentMailbox,
) (*DevelopmentMailer, error) {
	if environment != "development" || mailbox == nil {
		return nil, &ConfigurationError{Code: ConfigurationInvalid}
	}
	return &DevelopmentMailer{mailbox: mailbox}, nil
}

func (m *DevelopmentMailer) Deliver(_ context.Context, message Message) error {
	m.mailbox.store(message)
	return nil
}
