package password

import "fmt"

type ErrorCode string

const (
	TooShort ErrorCode = "passwordTooShort"
	TooLong  ErrorCode = "passwordTooLong"
	Blocked  ErrorCode = "passwordBlocked"
	Invalid  ErrorCode = "passwordInvalid"
)

type Error struct {
	Code ErrorCode
}

func (e *Error) Error() string {
	return fmt.Sprintf("password: %s", e.Code)
}
