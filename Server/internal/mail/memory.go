package mail

import (
	"context"
	"sync"
)

type MemoryMailer struct {
	mu        sync.Mutex
	delivered []Message
}

func (m *MemoryMailer) Deliver(_ context.Context, message Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.delivered = append(m.delivered, message)
	return nil
}

func (m *MemoryMailer) Delivered() []Message {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Message(nil), m.delivered...)
}
