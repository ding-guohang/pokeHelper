package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"porkhelper/server/internal/auth"
)

// Retry-After is the only guidance a throttled client gets. Rounding it down
// would invite a retry the server still refuses, and advertising zero would
// invite an immediate hammer.
func TestRetryAfterIsRoundedUpAndNeverBelowOneSecond(t *testing.T) {
	tests := map[string]struct {
		retryAfter time.Duration
		want       string
	}{
		"sub-second rounds up to one": {retryAfter: 200 * time.Millisecond, want: "1"},
		"zero still advertises one":   {retryAfter: 0, want: "1"},
		"exact seconds are kept":      {retryAfter: 30 * time.Second, want: "30"},
		"fractions round up":          {retryAfter: 30*time.Second + time.Millisecond, want: "31"},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			response := httptest.NewRecorder()

			writeAuthError(
				response,
				&auth.Error{Code: auth.RateLimited, RetryAfter: test.retryAfter},
				"test-request",
			)

			if got := response.Header().Get("Retry-After"); got != test.want {
				t.Errorf("Retry-After = %q, want %q", got, test.want)
			}
			if response.Code != http.StatusTooManyRequests {
				t.Errorf("status = %d, want 429", response.Code)
			}
		})
	}
}
