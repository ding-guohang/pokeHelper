package config_test

import (
	"errors"
	"testing"

	"porkhelper/server/internal/config"
)

func TestLoadUsesDevelopmentDefaults(t *testing.T) {
	got, err := config.Load(mapLookup(nil))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if got.Environment != config.Development {
		t.Errorf("Environment = %q, want %q", got.Environment, config.Development)
	}
	if got.HTTPAddr != "127.0.0.1:8080" {
		t.Errorf("HTTPAddr = %q, want %q", got.HTTPAddr, "127.0.0.1:8080")
	}
	if got.MySQLDSN != "" {
		t.Errorf("MySQLDSN = %q, want empty", got.MySQLDSN)
	}
}

func TestLoadReadsPokerCoachEnvironment(t *testing.T) {
	got, err := config.Load(mapLookup(map[string]string{
		"POKER_COACH_ENV":       "test",
		"POKER_COACH_MYSQL_DSN": "test:test@tcp(127.0.0.1:3307)/poker_coach_test",
		"POKER_COACH_HTTP_ADDR": "127.0.0.1:9090",
	}))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if got.Environment != config.Test {
		t.Errorf("Environment = %q, want %q", got.Environment, config.Test)
	}
	if got.MySQLDSN != "test:test@tcp(127.0.0.1:3307)/poker_coach_test" {
		t.Errorf("MySQLDSN = %q", got.MySQLDSN)
	}
	if got.HTTPAddr != "127.0.0.1:9090" {
		t.Errorf("HTTPAddr = %q", got.HTTPAddr)
	}
}

func TestLoadRejectsUnknownEnvironment(t *testing.T) {
	_, err := config.Load(mapLookup(map[string]string{
		"POKER_COACH_ENV": "staging",
	}))

	var configErr *config.Error
	if !errors.As(err, &configErr) {
		t.Fatalf("Load() error = %v, want *config.Error", err)
	}
	if configErr.Code != config.InvalidEnvironment {
		t.Errorf("error code = %q, want %q", configErr.Code, config.InvalidEnvironment)
	}
}

func TestLoadRequiresMySQLDSNInProduction(t *testing.T) {
	_, err := config.Load(mapLookup(map[string]string{
		"POKER_COACH_ENV": "production",
	}))

	var configErr *config.Error
	if !errors.As(err, &configErr) {
		t.Fatalf("Load() error = %v, want *config.Error", err)
	}
	if configErr.Code != config.MissingMySQLDSN {
		t.Errorf("error code = %q, want %q", configErr.Code, config.MissingMySQLDSN)
	}
}

func mapLookup(values map[string]string) func(string) (string, bool) {
	return func(key string) (string, bool) {
		value, ok := values[key]
		return value, ok
	}
}
