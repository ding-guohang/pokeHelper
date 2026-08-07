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

---

## Fix Round 1

### Status

DONE

Reviewer base: `53ca11be471a5561677a3731cfbb805ff487d838`

### Root-cause findings

1. `auth_throttles.window_started_at/failure_count` retained only one fixed-window summary, so attempts near the end of that window were discarded together with an older first attempt.
2. `RequestPasswordReset` returned the mail transport error after the verified-account challenge had already committed, while unknown/unverified identities skipped mail and returned 202.
3. `Login` treated a `password.Hasher.Verify` parse error as an internal error instead of a credential failure.
4. Registration, reset request, and invalid-email login returned immediately after `NormalizeEmail`; reset confirmation called `Hasher.Hash` before the Store row-locked and validated the challenge.
5. Login discarded the `needsUpgrade` result returned by `Hasher.Verify`.

### Implementation summary

- Added immutable migration `0005_auth_throttle_attempts.sql`.
  - Stores only the two HMAC sentinel hashes, millisecond attempt timestamp, and an aggregated count for attempts sharing the same millisecond.
  - Backfills version-four summaries conservatively and idempotently.
  - Cascades attempt history when a successful login clears its account bucket.
- MySQL throttle consumption now locks account then network, deletes records at or before the rolling cutoff, sums the exact remaining 15-minute events, records the new event, and opens the block on count 6/26.
- Reset mail delivery failure now remains exact 202 accepted. A later request consumes prior active reset challenges before committing a new one; undelivered challenges therefore expire if untouched or are superseded on retry.
- Malformed stored PHC is mapped to the same `authenticationFailed` path and consumes both quotas.
- Added domain-separated `invalid-account` and `challenge` HMAC signals. Invalid emails use deterministic trim + Unicode lowercase + NFC normalization (invalid UTF-8 uses deterministic base64 bytes) before HMAC; only hashes reach MySQL.
- Registration, reset request, and invalid-email login now consume quotas even when email normalization fails.
- Reset confirmation checks an open challenge bucket before policy/hash work. The Store row-locks and validates token purpose/expiry/consumption before invoking the password-hash callback; invalid tokens consume account/network quotas without Argon2 hashing.
- Successful login now honors `needsUpgrade`, hashes the normalized candidate with current parameters, and conditionally updates by `user_id + old PHC` so a concurrent reset is never overwritten. Failed verification never upgrades.

### RED commands and key output

#### True rolling window and migration 0005

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./migrations ./internal/mysqlstore \
  -run 'VersionFive|VersionFourThrottle|RollingFifteen'

TestApplyUpgradesVersionFourThrottleStateAndIsIdempotent:
  CurrentVersion() after version 4 upgrade = 4, want 5
TestApplyVersionFiveResumesEachCommittedStatementBeforeCheckpoint:
  open 0005_auth_throttle_attempts.sql: no such file or directory
TestThrottleCountsTheExactRollingFifteenMinuteWindow:
  seventh total attempt error = <nil>, want rateLimited
FAIL
```

#### Reset mail enumeration

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./internal/httpapi -run 'MailerFailure'

reset response = 500
"{\"error\":{\"code\":\"internalError\",\"requestID\":\"reset-mail-failure\"}}"
want exact 202 accepted
FAIL
```

#### Malformed stored PHC

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./internal/httpapi -run 'MalformedStoredPHC'

attempt 1 response = 500
"{\"error\":{\"code\":\"internalError\",\"requestID\":\"malformed-phc\"}}"
want 401 authenticationFailed
FAIL
```

#### Invalid-email and reset-confirm throttling

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./internal/httpapi \
  -run 'InvalidEmailRequests|UnknownResetToken'

registration/reset/login invalid account sixth attempt:
  got validationFailed/authenticationFailed, want rateLimited
invalid-email network twenty-sixth:
  got validationFailed, want rateLimited
unknown reset account/network attempt 1:
  got 500 internalError, want challengeInvalid before Hash
FAIL
```

#### Argon2 upgrade

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./internal/httpapi -run 'UpgradesWeakPHC'

upgraded PHC does not use current parameters
FAIL
```

#### Tooling corrections

- The first migration RED invocation passed `./Server/...` even though the temporary-MySQL script already changes into `Server`; it failed with `Server/Server/... directory not found` and was immediately rerun with the corrected package paths shown above.
- One final formatting command likewise used a root-relative path while already inside `Server`; it was corrected before any validation claim.

### Focused GREEN commands and output

```text
... go test -tags=integration -count=1 ./migrations ./internal/mysqlstore \
  -run 'VersionFive|VersionFourThrottle|RollingFifteen'
ok   porkhelper/server/migrations
ok   porkhelper/server/internal/mysqlstore

... go test -tags=integration -count=1 ./internal/httpapi -run 'MailerFailure'
ok   porkhelper/server/internal/httpapi

... go test -tags=integration -count=1 ./internal/httpapi -run 'MalformedStoredPHC'
ok   porkhelper/server/internal/httpapi

... go test -tags=integration -count=1 ./internal/httpapi \
  -run 'InvalidEmailRequests|UnknownResetToken'
ok   porkhelper/server/internal/httpapi

... go test -tags=integration -count=1 ./internal/httpapi -run 'UpgradesWeakPHC'
ok   porkhelper/server/internal/httpapi
```

### Final GREEN commands and output

```text
cd Server
GOCACHE=/tmp/porkhelper-task3-fix1-gocache \
  go test ./internal/auth ./internal/httpapi -run 'Login|Reset|Throttle' -count=1
ok   porkhelper/server/internal/auth
?    porkhelper/server/internal/httpapi [no test files]

GOCACHE=/tmp/porkhelper-task3-fix1-gocache go test -count=1 ./...
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/config
ok   porkhelper/server/internal/mail
ok   porkhelper/server/internal/password
ok   porkhelper/server/migrations

GOCACHE=/tmp/porkhelper-task3-fix1-gocache go vet ./...
(exit 0, no output)
```

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -tags=integration -count=1 ./...
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/config
ok   porkhelper/server/internal/httpapi
ok   porkhelper/server/internal/mail
ok   porkhelper/server/internal/mysqlstore
ok   porkhelper/server/internal/password
ok   porkhelper/server/migrations
```

```text
GOCACHE=/tmp/porkhelper-task3-fix1-gocache ./scripts/test-server-mysql.sh \
  go test -race -tags=integration -count=1 \
  ./internal/auth ./internal/httpapi ./internal/mysqlstore ./migrations \
  -run 'Login|Reset|Throttle|VersionFive|VersionFourThrottle'
ok   porkhelper/server/internal/auth
ok   porkhelper/server/internal/httpapi
ok   porkhelper/server/internal/mysqlstore
ok   porkhelper/server/migrations
```

### Migration and concurrency evidence

- Fresh migration ends at version 5 with five migration rows and the new attempt table.
- Repeat `Apply` leaves one backfilled row/count unchanged.
- Original v1, v2, v3, and v4 upgrade paths all complete at v5 without modifying migrations 0001–0004.
- Version-five commit-before-checkpoint probes cover both statements:
  - statement 0 table DDL is detected as already committed;
  - statement 1 backfill safely repeats via `GREATEST`.
- The rolling boundary test records attempt 1 at 00:00, attempts 2–5 at 14:59, attempt 6 just after 15:00, then attempt 7. Attempt 1 is removed, attempt 6 is allowed as the fifth recent event, and attempt 7 opens the account block as the sixth recent event.
- Existing simultaneous 6-account and 26-network tests remain green and persist exact counts without lost increments.
- Account→network lock order remains unchanged.

### Files changed in Fix Round 1

- Added `Server/migrations/0005_auth_throttle_attempts.sql`
- Updated `Server/migrations/contracts_test.go`
- Updated `Server/migrations/resume.go`
- Updated `Server/migrations/runner_test.go`
- Updated `Server/internal/auth/login.go`
- Updated `Server/internal/auth/models.go`
- Updated `Server/internal/auth/registration.go`
- Updated `Server/internal/auth/reset.go`
- Updated `Server/internal/auth/store.go`
- Updated `Server/internal/auth/throttle.go`
- Updated `Server/internal/httpapi/auth_handlers.go`
- Updated `Server/internal/httpapi/auth_handlers_test.go`
- Updated `Server/internal/mysqlstore/auth_access_integration_test.go`
- Updated `Server/internal/mysqlstore/auth_store.go`

### Fix Round 1 self-review

- Migrations `0001`–`0004` remain byte-identical with locked checksums.
- Migration `0005` checksum is locked at `2a0dae10c22f3f7aba7bfb801e68c7242dcf41086f7b57133cb339567e9e62b3`.
- No raw email, invalid email, IP, reset token, password, PHC, or HMAC key is persisted in throttle history or logged.
- Password hashing for reset confirmation occurs only inside the valid row-locked challenge branch.
- Reset mail failure produces no identity-dependent status/body; unverified and missing identities remain exact 202.
- Retry after a committed-but-undelivered reset challenge supersedes the old active challenge transactionally.
- PHC upgrade is conditional on the exact old PHC and therefore cannot overwrite a concurrent password reset.
- Deferred Minor items (legal XFF fixture, extra Retry-After and concurrent registration/reset boundaries) were not expanded.

### Fix Round 1 concerns

- None.
