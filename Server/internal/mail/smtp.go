package mail

import (
	"bufio"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/smtp"
	"strconv"
	"strings"
)

type ConfigurationCode string

const ConfigurationInvalid ConfigurationCode = "configurationInvalid"

type ConfigurationError struct {
	Code     ConfigurationCode
	Variable string
}

func (e *ConfigurationError) Error() string {
	if e.Variable == "" {
		return "mail: configurationInvalid"
	}
	return fmt.Sprintf("mail: configurationInvalid: %s", e.Variable)
}

type TLSMode string

const (
	StartTLS TLSMode = "starttls"
	TLS      TLSMode = "tls"
)

type SMTPConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	Sender   string
	TLSMode  TLSMode
}

type SMTPTransport interface {
	Send(context.Context, SMTPConfig, Message) error
}

type SMTPMailer struct {
	config    SMTPConfig
	transport SMTPTransport
}

func NewSMTPMailer(
	_ string,
	lookup func(string) (string, bool),
	transport SMTPTransport,
) (*SMTPMailer, error) {
	names := []string{
		"POKER_COACH_SMTP_HOST",
		"POKER_COACH_SMTP_PORT",
		"POKER_COACH_SMTP_USERNAME",
		"POKER_COACH_SMTP_PASSWORD",
		"POKER_COACH_SMTP_SENDER",
		"POKER_COACH_SMTP_TLS_MODE",
	}
	values := make(map[string]string, len(names))
	for _, name := range names {
		value, _ := lookup(name)
		if value == "" {
			return nil, &ConfigurationError{Code: ConfigurationInvalid, Variable: name}
		}
		values[name] = value
	}
	port, err := strconv.Atoi(values["POKER_COACH_SMTP_PORT"])
	if err != nil || port < 1 || port > 65535 {
		return nil, &ConfigurationError{
			Code:     ConfigurationInvalid,
			Variable: "POKER_COACH_SMTP_PORT",
		}
	}
	mode := TLSMode(values["POKER_COACH_SMTP_TLS_MODE"])
	if mode != StartTLS && mode != TLS {
		return nil, &ConfigurationError{
			Code:     ConfigurationInvalid,
			Variable: "POKER_COACH_SMTP_TLS_MODE",
		}
	}
	if transport == nil {
		transport = networkSMTPTransport{}
	}
	return &SMTPMailer{
		config: SMTPConfig{
			Host:     values["POKER_COACH_SMTP_HOST"],
			Port:     port,
			Username: values["POKER_COACH_SMTP_USERNAME"],
			Password: values["POKER_COACH_SMTP_PASSWORD"],
			Sender:   values["POKER_COACH_SMTP_SENDER"],
			TLSMode:  mode,
		},
		transport: transport,
	}, nil
}

func (m *SMTPMailer) Deliver(ctx context.Context, message Message) error {
	if containsHeaderNewline(message.To) || containsHeaderNewline(message.Subject) {
		return errors.New("mail: invalid message header")
	}
	return m.transport.Send(ctx, m.config, message)
}

func containsHeaderNewline(value string) bool {
	return strings.ContainsAny(value, "\r\n")
}

type networkSMTPTransport struct{}

func (networkSMTPTransport) Send(ctx context.Context, config SMTPConfig, message Message) error {
	address := net.JoinHostPort(config.Host, strconv.Itoa(config.Port))
	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS12,
		ServerName: config.Host,
	}

	var client *smtp.Client
	if config.TLSMode == TLS {
		connection, err := (&tls.Dialer{
			NetDialer: &net.Dialer{},
			Config:    tlsConfig,
		}).DialContext(ctx, "tcp", address)
		if err != nil {
			return fmt.Errorf("mail: connect smtp: %w", err)
		}
		client, err = smtp.NewClient(connection, config.Host)
		if err != nil {
			_ = connection.Close()
			return fmt.Errorf("mail: initialize smtp: %w", err)
		}
	} else {
		connection, err := (&net.Dialer{}).DialContext(ctx, "tcp", address)
		if err != nil {
			return fmt.Errorf("mail: connect smtp: %w", err)
		}
		client, err = smtp.NewClient(connection, config.Host)
		if err != nil {
			_ = connection.Close()
			return fmt.Errorf("mail: initialize smtp: %w", err)
		}
		if err := client.StartTLS(tlsConfig); err != nil {
			_ = client.Close()
			return fmt.Errorf("mail: start tls: %w", err)
		}
	}
	defer client.Close()

	if err := client.Auth(smtp.PlainAuth("", config.Username, config.Password, config.Host)); err != nil {
		return fmt.Errorf("mail: authenticate smtp: %w", err)
	}
	if err := client.Mail(config.Sender); err != nil {
		return fmt.Errorf("mail: set sender: %w", err)
	}
	if err := client.Rcpt(message.To); err != nil {
		return fmt.Errorf("mail: set recipient: %w", err)
	}
	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("mail: start message: %w", err)
	}
	if err := writeSMTPMessage(writer, config.Sender, message); err != nil {
		_ = writer.Close()
		return err
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("mail: finish message: %w", err)
	}
	if err := client.Quit(); err != nil {
		return fmt.Errorf("mail: quit smtp: %w", err)
	}
	return nil
}

func writeSMTPMessage(writer io.Writer, sender string, message Message) error {
	buffer := bufio.NewWriter(writer)
	if _, err := fmt.Fprintf(
		buffer,
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		sender,
		message.To,
		message.Subject,
		message.Body,
	); err != nil {
		return fmt.Errorf("mail: write message: %w", err)
	}
	if err := buffer.Flush(); err != nil {
		return fmt.Errorf("mail: flush message: %w", err)
	}
	return nil
}
