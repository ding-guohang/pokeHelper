package config

import "fmt"

type Environment string

const (
	Development Environment = "development"
	Test        Environment = "test"
	Production  Environment = "production"
)

type ErrorCode string

const (
	InvalidEnvironment ErrorCode = "invalidEnvironment"
	MissingMySQLDSN    ErrorCode = "missingMySQLDSN"
)

type Error struct {
	Code     ErrorCode
	Variable string
	Value    string
}

func (e *Error) Error() string {
	switch e.Code {
	case InvalidEnvironment:
		return fmt.Sprintf("config: %s has unsupported value %q", e.Variable, e.Value)
	case MissingMySQLDSN:
		return fmt.Sprintf("config: %s is required in production", e.Variable)
	default:
		return "config: invalid configuration"
	}
}

type Config struct {
	Environment Environment
	MySQLDSN    string
	HTTPAddr    string
}

func Load(lookup func(string) (string, bool)) (Config, error) {
	environment := Development
	if value, ok := lookup("POKER_COACH_ENV"); ok && value != "" {
		environment = Environment(value)
	}
	switch environment {
	case Development, Test, Production:
	default:
		return Config{}, &Error{
			Code:     InvalidEnvironment,
			Variable: "POKER_COACH_ENV",
			Value:    string(environment),
		}
	}

	mysqlDSN, _ := lookup("POKER_COACH_MYSQL_DSN")
	if environment == Production && mysqlDSN == "" {
		return Config{}, &Error{
			Code:     MissingMySQLDSN,
			Variable: "POKER_COACH_MYSQL_DSN",
		}
	}

	httpAddr := "127.0.0.1:8080"
	if value, ok := lookup("POKER_COACH_HTTP_ADDR"); ok && value != "" {
		httpAddr = value
	}

	return Config{
		Environment: environment,
		MySQLDSN:    mysqlDSN,
		HTTPAddr:    httpAddr,
	}, nil
}
