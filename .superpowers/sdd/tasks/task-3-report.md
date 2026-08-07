# Task 3 Report

## Status

DONE

## Implementation summary

- Added canonical-email password login with a fixed current-policy dummy Argon2id PHC for missing credentials. Missing, unverified, and wrong-password identities return the same `authenticationFailed` result. An already-open throttle is checked before credential lookup/password verification.
- Added auth-owned `DeviceMetadata`, `SessionTokens`, `LoginResult`, and `SessionIssuer`. Successful password login passes the service clock value as `RecentAuthAt`.
- Added enumeration-safe password-reset request and confirmation. Reset tokens are 32 random bytes encoded as unpadded base64url, stored only as SHA-256, use purpose `resetPassword`, expire after one hour, and are row-locked/consumed once.
- Password replacement, challenge consumption, and `SessionIssuer.RevokeAll(..., "passwordReset")` are coordinated inside one MySQL transaction. Revocation failure rolls back the password and challenge changes.
- Added exported auth `Throttle` boundary for Task 4 reuse. It derives HMAC-SHA-256 account/network keys with a required injected 32-byte secret and domain separation.
- Added transactional MySQL account/network buckets using the existing composite key and zero-hash sentinels. Limits are 5/25 attempts, a 15-minute rolling window, and a 15-minute block opened by attempt 6/26.
- Registration and reset requests consume both buckets; failed login and invalid verification consume both; successful login clears only the account bucket. HTTP 429 is a generic `rateLimited` envelope with a ceiling/minimum-one `Retry-After`.
- HTTP network signals are canonicalized exclusively from `request.RemoteAddr`; `X-Forwarded-For` is not read.
- Preserved migrations `0001`–`0004` byte-for-byte and added the existing `0004` checksum to the historical checksum contract.

## RED evidence

1. Brief focused command initially hit the managed Go cache restriction before compilation:

   ```text
   go test ./internal/auth ./internal/httpapi -run 'Login|Reset|Throttle'
   open /Users/wenzheng/Library/Caches/go-build/...: operation not permitted
   FAIL
   ```

   The same command was rerun with a task-local `/tmp` `GOCACHE`.

2. First feature RED:

   ```text
   GOCACHE=/tmp/porkhelper-task3-gocache go test ./internal/auth ./internal/httpapi -run 'Login|Reset|Throttle'
   internal/auth/throttle_test.go:20:13: undefined: signalHash
   internal/auth/throttle_test.go:20:32: undefined: accountSignalDomain
   internal/auth/throttle_test.go:21:32: undefined: networkSignalDomain
   FAIL porkhelper/server/internal/auth [build failed]
   ```

3. The first HMAC GREEN attempt exposed an incorrect hand-entered test vector:

   ```text
   GOCACHE=/tmp/porkhelper-task3-gocache go test ./internal/auth -run ThrottleSignal -count=1
   account hash = dcae18d75f6bee467207e34908833721ab256168c89138b6c46770c6dd794b0e
   FAIL
   ```

   The independent vectors were recalculated with OpenSSL, the fixture was corrected, and the same focused test passed.

4. Login/reset/MySQL API RED:

   ```text
   GOCACHE=/tmp/porkhelper-task3-gocache go test -tags=integration ./internal/httpapi ./internal/mysqlstore -run 'Login|Reset|Throttle' -count=1
   undefined: auth.NewThrottle
   too many arguments in call to auth.NewService
   undefined: auth.WithThrottle
   undefined: auth.WithSessionIssuer
   undefined: httpapi.NewAuthHandler
   undefined: auth.DeviceMetadata
   undefined: auth.SessionTokens
   undefined: auth.RateLimited
   FAIL
   ```

5. Direct integration execution without the isolated runner correctly failed closed:

   ```text
   mysqltest requires POKER_COACH_ENV=test
   FAIL porkhelper/server/internal/httpapi
   FAIL porkhelper/server/internal/mysqlstore
   ```

6. The first sandboxed isolated-MySQL launcher attempt could not bind a loopback port:

   ```text
   PermissionError: [Errno 1] Operation not permitted
   ```

   It was rerun with the required managed escalation and temporary-server proof.

## GREEN evidence

### Focused

```text
GOCACHE=/tmp/porkhelper-task3-gocache go test ./internal/auth ./internal/httpapi -run 'Login|Reset|Throttle' -count=1
ok   porkhelper/server/internal/auth
?    porkhelper/server/internal/httpapi [no test files]
```

### Full non-integration suite

```text
GOCACHE=/tmp/porkhelper-task3-gocache go test -count=1 ./...
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/config
ok   porkhelper/server/internal/mail
ok   porkhelper/server/internal/password
ok   porkhelper/server/migrations
```

### Full isolated MySQL integration

```text
GOCACHE=/tmp/porkhelper-task3-gocache ./scripts/test-server-mysql.sh go test -tags=integration -count=1 ./...
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/config
ok   porkhelper/server/internal/httpapi
ok   porkhelper/server/internal/mail
ok   porkhelper/server/internal/mysqlstore
ok   porkhelper/server/internal/password
ok   porkhelper/server/migrations
```

### Relevant race

```text
GOCACHE=/tmp/porkhelper-task3-gocache ./scripts/test-server-mysql.sh go test -race -tags=integration -count=1 ./internal/auth ./internal/httpapi ./internal/mysqlstore -run 'Login|Reset|Throttle'
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/httpapi
ok   porkhelper/server/internal/mysqlstore
```

### Vet

```text
GOCACHE=/tmp/porkhelper-task3-gocache go vet ./...
(exit 0, no output)
```

## MySQL concurrency and transaction evidence

- `TestThrottleTransactionsDoNotLoseSimultaneousAccountOrNetworkAttempts` starts workers behind one barrier.
  - Six simultaneous attempts sharing one account persist account `failure_count = 6` and return exactly one `rateLimited`.
  - Twenty-six simultaneous attempts sharing one network persist network `failure_count = 26` and return exactly one `rateLimited`.
- Both sentinel rows are inserted/locked/updated in one `READ COMMITTED` transaction with `SELECT ... FOR UPDATE`; every caller uses the same account-then-network lock order.
- `TestPasswordResetIsEnumerationSafeSingleUseAndRevokesSessionsAtomically` injects a `RevokeAll` failure, verifies the old PHC still authenticates and the replacement does not, then retries the same challenge successfully. It also proves consumed, expired, and unknown challenges return `challengeInvalid`.
- The login test opens an account block, replaces the stored PHC with malformed data, then submits the correct password and still receives 429. This proves the open-window check occurs before password parsing/verification.

## Files

- Added `Server/internal/auth/login.go`
- Added `Server/internal/auth/reset.go`
- Added `Server/internal/auth/throttle.go`
- Added `Server/internal/auth/throttle_test.go`
- Updated `Server/internal/auth/models.go`
- Updated `Server/internal/auth/registration.go`
- Updated `Server/internal/auth/store.go`
- Updated `Server/internal/mysqlstore/auth_store.go`
- Added `Server/internal/mysqlstore/auth_access_integration_test.go`
- Added `Server/internal/httpapi/auth_handlers.go`
- Added `Server/internal/httpapi/auth_handlers_test.go`
- Updated `Server/internal/httpapi/registration_handlers.go`
- Updated `Server/migrations/contracts_test.go`
- Added `.superpowers/sdd/tasks/task-3-report.md`

## Self-review

- Confirmed no Task 4 session package or adapter was implemented.
- Confirmed no migration SQL file changed and no new migration was necessary.
- Confirmed production code does not log email, password, PHC, raw challenge, network signal, or HMAC key.
- Confirmed account and network responses share one error code/body and do not expose which bucket fired.
- Confirmed `X-Forwarded-For` appears only in the test proving it is ignored.
- Confirmed all test doubles are limited to clock, randomness, mail, and `SessionIssuer`; store/Argon2/HTTP/MySQL paths are real.
- Confirmed scenario comments use GIVEN/WHEN/THEN and tests assert observable behavior rather than mock existence.

## Concerns

- None blocking Task 3.
- Task 4 must provide the `SessionIssuer` adapter and pass its canonical RemoteAddr-derived signal through `auth.WithNetworkSignal` before reusing `Throttle.Check`/`Throttle.Consume` for refresh failures.
