---
name: sync-m1b-identity-sync-20260807-01
status: planned
---

# M1B Independent Identity and Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`. Execute every Task with test-driven development, then run a specification review and a code-quality review before advancing.

**Goal:** Add independent email/password and Apple accounts, secure device sessions, MySQL-backed event synchronization, local profile isolation, and account data rights without placing a login wall in front of M1A training.

**Architecture:** Keep `TrainingEventStore` as the first local read/write source. Add profile-routed iOS Infrastructure actors around it, and connect them to a modular Go service backed by MySQL/InnoDB. Server ownership comes only from opaque bearer sessions; per-user locked sequences provide monotonic pull checkpoints.

**Tech stack:** Swift 6.2/SwiftUI/Security/AuthenticationServices, Go 1.25+, `net/http`, MySQL 8.4+ InnoDB, `go-sql-driver/mysql`, `x/crypto`, `x/text`, UUID.

## Global constraints

- No login wall; anonymous and offline training remains usable.
- Passwords are NFC-normalized, 15–128 Unicode scalars, blocklist checked, and Argon2id PHC encoded with `m=19456 KiB,t=2,p=1`.
- Access and refresh tokens are random opaque 32-byte values. Servers store SHA-256 hashes; iOS stores active credentials only in Keychain.
- A refresh-token replay revokes the complete session family.
- `deviceID` is installation-scoped; `localUserID` is profile-scoped. Claiming a profile never rewrites either ID, any event ID, or event content.
- Event wire schema starts at `1`; UUIDs are lowercase hyphenated strings; dates are UTC RFC 3339 with at most millisecond precision.
- Upload batches contain at most 100 events and 1 MiB JSON; pull limits are 1–200.
- An in-flight Outbox batch persists and retries the same idempotency key, ordered event IDs, canonical encoded request bytes, and request hash.
- Remote merge appends directly to the underlying idempotent event store, not the tracking decorator.
- MySQL migrations use InnoDB and `utf8mb4`; sequence allocation and event insertion occur in one row-locked transaction.
- Production deployment, real SMTP credentials, Apple production secrets, subscriptions, M1C curriculum, M2 simulation, and M3 tournaments are outside this change.

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| independent-account-access | 匿名离线连续性 | 首次离线启动 | Task 6 |
| independent-account-access | 匿名离线连续性 | 登录入口不阻断训练 | Task 6 |
| independent-account-access | 邮箱密码注册 | 合法注册 | Task 2 |
| independent-account-access | 邮箱密码注册 | 不合规密码 | Task 2 |
| independent-account-access | 邮箱密码注册 | Unicode 密码长度边界 | Task 2, 6 |
| independent-account-access | 邮箱密码注册 | 邮箱枚举保护 | Task 2, 3 |
| independent-account-access | 邮箱验证与密码重置 | 一次性邮箱验证 | Task 2 |
| independent-account-access | 邮箱验证与密码重置 | 密码重置 | Task 3 |
| independent-account-access | 邮箱密码登录 | 成功登录并认领匿名历史 | Task 7 |
| independent-account-access | 邮箱密码登录 | 通用登录失败 | Task 3 |
| independent-account-access | Apple 登录与显式身份关联 | 合法 Apple 登录 | Task 5 |
| independent-account-access | Apple 登录与显式身份关联 | 相同邮箱不自动合并 | Task 5 |
| independent-account-access | Apple 登录与显式身份关联 | 无效 Apple credential | Task 5 |
| secure-device-sessions | Keychain 凭据存储 | 会话持久化 | Task 6 |
| secure-device-sessions | Keychain 凭据存储 | Keychain 不可用 | Task 6 |
| secure-device-sessions | 不透明令牌与刷新轮换 | 正常刷新 | Task 4 |
| secure-device-sessions | 不透明令牌与刷新轮换 | 刷新令牌重放 | Task 4, 10 |
| secure-device-sessions | 设备会话管理 | 查看设备 | Task 4, 12 |
| secure-device-sessions | 设备会话管理 | 撤销其他设备 | Task 4, 12 |
| secure-device-sessions | 本地账号数据隔离 | 同设备切换账号 | Task 7 |
| local-first-event-sync | 本地先写与可恢复 Outbox | 离线完成训练 | Task 8 |
| local-first-event-sync | 本地先写与可恢复 Outbox | 追加与入队之间中断 | Task 8 |
| local-first-event-sync | 幂等批量上传 | 上传响应丢失后重试 | Task 9 |
| local-first-event-sync | 幂等批量上传 | 幂等键请求冲突 | Task 9 |
| local-first-event-sync | 幂等批量上传 | 事件归属由会话决定 | Task 9 |
| local-first-event-sync | 单调 Checkpoint 拉取 | 跨设备增量同步 | Task 10 |
| local-first-event-sync | 单调 Checkpoint 拉取 | 设备时钟回拨 | Task 9 |
| local-first-event-sync | 单调 Checkpoint 拉取 | 多页 checkpoint 边界 | Task 9, 10 |
| local-first-event-sync | 远端事件本地合并 | 拉取重复事件 | Task 10 |
| local-first-event-sync | 同步状态与自动恢复 | 网络恢复 | Task 10 |
| local-first-event-sync | 同步状态与自动恢复 | 会话失效 | Task 10 |
| mysql-sync-service | Go 与 MySQL 兼容基线 | 空数据库迁移 | Task 1 |
| mysql-sync-service | Go 与 MySQL 兼容基线 | 重复迁移 | Task 1 |
| mysql-sync-service | 事务与唯一约束 | 重复事件并发写入 | Task 9 |
| mysql-sync-service | 事务与唯一约束 | 同一用户并发顺序分配 | Task 9 |
| mysql-sync-service | 事务与唯一约束 | 账号删除事务 | Task 11 |
| mysql-sync-service | API 授权与输入验证 | 越权 user ID | Task 9 |
| mysql-sync-service | API 授权与输入验证 | 超限批次 | Task 9 |
| mysql-sync-service | 认证速率限制 | 连续失败登录 | Task 3 |
| mysql-sync-service | 可替换邮件投递 | 测试投递 | Task 2 |
| mysql-sync-service | 可替换邮件投递 | SMTP 配置缺失 | Task 2 |
| account-data-rights | 近期重新认证 | 过期认证 | Task 11 |
| account-data-rights | 结构化数据导出 | 导出成功 | Task 11, 12 |
| account-data-rights | 账号与本机数据删除 | 仅删除云端账号 | Task 11, 12 |
| account-data-rights | 账号与本机数据删除 | 同时删除本机历史 | Task 12 |
| account-data-rights | 安全退出 | 离线退出 | Task 12 |
| m1b-verification | 一键 M1B 验证 | 从干净检出验证 | Task 13 |
| m1b-verification | 隔离测试环境 | 本机已有 MySQL | Task 1, 13 |
| m1b-verification | 密钥与开发能力隔离 | Release 检查 | Task 13 |
| local-learning-profile | 不可变本地训练事件 | 首次追加 | Task 8 |
| local-learning-profile | 不可变本地训练事件 | 重复事件 | Task 8 |
| local-learning-profile | 不可变本地训练事件 | 损坏事件文件 | Task 8 |
| local-learning-profile | 能力画像归约 | 高信心错误 | Task 13 |
| local-learning-profile | 今日训练优先级 | 高信心弱项优先 | Task 13 |
| local-learning-profile | 今日与复盘使用真实历史 | 决策完成后刷新 | Task 10, 13 |
| local-learning-profile | 跨设备历史确定性归约 | 远端事件进入画像 | Task 10 |

Test arrange/act/assert comments must quote the corresponding Scenario's GIVEN/WHEN/THEN. A cross-layer Scenario is not complete until both server and iOS halves pass.

## File and module map

- `Server/cmd/{api,migrate}` — executable composition roots.
- `Server/internal/{auth,password,mail,session,appleauth,sync,account}` — use cases and ports.
- `Server/internal/{httpapi,mysqlstore,config}` — adapters.
- `Server/migrations` — embedded versioned MySQL schema.
- `PokerCoach/Infrastructure/{Network,Auth,Profiles,Sync,Export}` — iOS service adapters and local-first actors.
- `PokerCoach/Features/Account` — account center, email flow, devices, export, deletion.
- `PokerCoachTests` and `Server/**_test.go` — deterministic unit/contract tests.
- `Server/test/e2e` and `PokerCoachUITests` — cross-device and adaptive UI gates.

## Exact iOS test commands

Run `xcodegen generate` before the first iOS test after any `project.yml` change. Focused suites use:

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/AppleAuthorizationClientTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/PasswordPolicyTests \
  -only-testing:PokerCoachTests/CredentialStoreTests \
  -only-testing:PokerCoachTests/AccountSessionControllerTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/ProfileAssociationStoreTests \
  -only-testing:PokerCoachTests/ActiveProfileControllerTests \
  -only-testing:PokerCoachTests/ProfileLifecycleControllerTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/FileOutboxStoreTests \
  -only-testing:PokerCoachTests/SyncTrackingTrainingEventStoreTests \
  -only-testing:PokerCoachTests/OutboxReconciliationTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/SyncAPIDTOTests \
  -only-testing:PokerCoachTests/SyncEngineTests \
  -only-testing:PokerCoachTests/TwoProfileConvergenceTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/AccountExportBuilderTests \
  -only-testing:PokerCoachTests/AccountDeletionTests \
  -only-testing:PokerCoachTests/OfflineLogoutTests
```

---

### Task 1: Establish the Go service, versioned schema, and isolated MySQL harness | covers: mysql-sync-service/Go 与 MySQL 兼容基线, m1b-verification/隔离测试环境

**Files:**
- Create: `Server/go.mod`, `Server/go.sum`
- Create: `Server/cmd/migrate/main.go`
- Create: `Server/internal/config/config.go`, `Server/internal/config/config_test.go`
- Create: `Server/internal/mysqlstore/open.go`
- Create: `Server/migrations/embed.go`, `Server/migrations/runner.go`, `Server/migrations/runner_test.go`, `Server/migrations/0001_m1b_initial.sql`
- Create: `Server/test/mysqltest/database.go`, `scripts/test-server-mysql.sh`
- Create: `Contracts/training-event-upload-v1.json`, `Contracts/training-event-upload-v1.sha256`

**Interfaces:**

```go
func config.Load(lookup func(string) (string, bool)) (config.Config, error)
func mysqlstore.Open(ctx context.Context, dsn string) (*sql.DB, error)
func migrations.Apply(ctx context.Context, db *sql.DB) error
func migrations.CurrentVersion(ctx context.Context, db *sql.DB) (uint64, error)
```

- [ ] Write failing config and integration tests for an empty schema, a second migration run, InnoDB/utf8mb4, all 11 domain tables plus `schema_migrations`, foreign keys, and unique constraints.
- [ ] Run `cd Server && go test ./internal/config ./migrations`; expect failures for missing packages.
- [ ] Implement the locked Go dependencies and `0001_m1b_initial.sql`. Use binary UUID columns consistently; include challenge purpose/expiry indexes, `(provider,subject)`, `(user_id,event_id)`, `(user_id,server_sequence)`, `(user_id,idempotency_key)`, refresh hash, and device identity constraints. Add the canonical schema-version-1 upload body plus its lowercase hexadecimal SHA-256 golden fixture under `Contracts/`.
- [ ] Implement `scripts/test-server-mysql.sh` with `mktemp -d`, an OS-assigned free port, a socket inside the temporary directory, test-only credentials, and `trap` cleanup. It must never invoke a system service manager or a pre-existing DSN.
- [ ] Run `bash scripts/test-server-mysql.sh go test -tags=integration ./migrations ./internal/mysqlstore`; expect PASS. Commit `feat: add mysql service foundation and migrations`.

---

### Task 2: Implement password policy, registration, verification challenges, and mail adapters | covers: independent-account-access/邮箱密码注册, independent-account-access/邮箱验证与密码重置, mysql-sync-service/可替换邮件投递

**Files:**
- Create: `Server/internal/password/{policy,argon2id,blocklist,errors}.go` and matching tests
- Create: `Server/resources/weak-passwords.txt`
- Create: `Server/internal/auth/{models,store,registration}.go`, `registration_test.go`
- Create: `Server/internal/mail/{mailer,memory,development,smtp}.go`, `mailer_test.go`
- Create: `Server/internal/mysqlstore/auth_store.go`, `auth_store_integration_test.go`
- Create: `Server/internal/httpapi/{json,errors,registration_handlers}.go`, `registration_handlers_test.go`

**Interfaces:**

```go
func (p password.Policy) NormalizeAndValidate(raw string) (string, error)
func (h password.Hasher) Hash(normalized string) (string, error)
func (h password.Hasher) Verify(phc, candidate string) (bool, bool, error)
func (s *auth.Service) Register(context.Context, auth.RegisterInput) (auth.Accepted, error)
func (s *auth.Service) VerifyEmail(context.Context, string) error
type Mailer interface { Deliver(context.Context, mail.Message) error }
```

- [ ] Write failing tests for NFC scalar boundaries 14/15/128/129, multi-byte scalars, no composition rule, blocklist rejection, independent salts, exact Argon2id parameters, enumeration-safe acceptance, single-use/expired challenges, and log capture without credentials.
- [ ] Run `cd Server && go test ./internal/password ./internal/auth ./internal/mail ./internal/httpapi`; expect failures.
- [ ] Implement the policy using `norm.NFC.String` and `utf8.RuneCountInString`; store only challenge SHA-256 hashes and password PHC strings. Creating a user also creates its `user_sync_sequences` row at value zero in the same transaction. Return the same accepted envelope for occupied and unoccupied email registration.
- [ ] Add memory, explicitly development-only, and SMTP mailers. Production config without host, port, username, password, and sender returns `configurationInvalid`; it never falls back to logging message bodies.
- [ ] Run unit and isolated integration tests; expect PASS. Commit `feat: add secure email registration and verification`.

---

### Task 3: Add email login, password reset, and authentication throttling | covers: independent-account-access/邮箱验证与密码重置, independent-account-access/邮箱密码登录, mysql-sync-service/认证速率限制

**Files:**
- Create: `Server/internal/auth/login.go`, `reset.go`, `throttle.go` and tests
- Update: `Server/internal/auth/store.go`
- Update: `Server/internal/mysqlstore/auth_store.go`
- Create: `Server/internal/httpapi/auth_handlers.go`, `auth_handlers_test.go`

**Interfaces:**

```go
func (s *auth.Service) Login(context.Context, auth.LoginInput) (auth.LoginResult, error)
func (s *auth.Service) RequestPasswordReset(context.Context, string) (auth.Accepted, error)
func (s *auth.Service) ConfirmPasswordReset(context.Context, string, string) error
type SessionIssuer interface {
    Issue(context.Context, string, auth.DeviceMetadata, time.Time) (auth.SessionTokens, error)
    RevokeAll(context.Context, string, string) error
}
```

- [ ] Write failing tests proving missing, unverified, and wrong-password login share `authenticationFailed`; reset enumeration is indistinguishable; a consumed reset challenge cannot be reused; reset revokes all refresh families; account and network throttle keys both produce generic `rateLimited` with retry-after.
- [ ] Run `cd Server && go test ./internal/auth ./internal/httpapi -run 'Login|Reset|Throttle'`; expect failures.
- [ ] Implement normalized-email throttle transactions and generic HTTP errors. `auth.DeviceMetadata` and `auth.SessionTokens` keep the auth port independent of the later session package; Task 4 supplies the adapter. Correct credentials must not bypass an already-open throttle window.
- [ ] Run MySQL integration tests for challenge consumption, credential replacement, and session-revocation port calls; expect PASS.
- [ ] Commit `feat: add email login reset and throttling`.

---

### Task 4: Implement opaque rotating sessions and device management | covers: secure-device-sessions/不透明令牌与刷新轮换, secure-device-sessions/设备会话管理

**Files:**
- Create: `Server/internal/session/{models,store,tokens,manager}.go` and tests
- Create: `Server/internal/session/auth_adapter.go`, `auth_adapter_test.go`
- Create: `Server/internal/mysqlstore/session_store.go`, `session_store_integration_test.go`
- Create: `Server/internal/httpapi/auth_middleware.go`, `session_handlers.go`, `session_handlers_test.go`

**Interfaces:**

```go
func (m *session.Manager) Issue(context.Context, string, session.DeviceMetadata, time.Time) (session.TokenPair, error)
func (m *session.Manager) AuthenticateAccess(context.Context, string) (session.Principal, error)
func (m *session.Manager) Refresh(context.Context, string) (session.TokenPair, error)
func (m *session.Manager) Logout(context.Context, string) error
func (m *session.Manager) ListDevices(context.Context, session.Principal) ([]session.DeviceSession, error)
func (m *session.Manager) RevokeSession(context.Context, session.Principal, string) error
```

- [ ] Write failing tests for 32 random bytes, hash-only persistence, atomic rotation, two concurrent refreshes, consumed-token replay family revocation, current-device marking, own-user scoping, and revoking another device without revoking current.
- [ ] Run `cd Server && go test ./internal/session ./internal/httpapi -run 'Session|Refresh|Device'`; expect failures.
- [ ] Implement transaction-backed token history and the adapter from Task 3 `auth.SessionIssuer` DTOs; never delete consumed rows before the security retention window. `Principal` carries server-derived `UserID`, `SessionID`, and `RecentAuthAt`.
- [ ] Run isolated MySQL tests including a real replay after rotation; expect PASS.
- [ ] Commit `feat: add rotating device sessions`.

---

### Task 5: Verify Apple credentials and require explicit identity linking | covers: independent-account-access/Apple 登录与显式身份关联, account-data-rights/近期重新认证

**Files:**
- Create: `Server/internal/appleauth/{claims,jwks,verifier}.go` and tests
- Create: `Server/internal/appleauth/testdata/apple_claims.json`
- Create: `Server/internal/auth/apple_service.go`, `apple_service_test.go`
- Create: `Server/internal/mysqlstore/apple_identity_store.go`, integration tests
- Create: `Server/internal/httpapi/apple_handlers.go`, `apple_handlers_test.go`

**Interfaces:**

```go
func (v *appleauth.Verifier) Verify(context.Context, string, string) (appleauth.Claims, error)
func (s *auth.AppleService) SignIn(context.Context, auth.AppleSignInInput) (auth.LoginResult, error)
func (s *auth.AppleService) Link(context.Context, session.Principal, auth.AppleLinkInput) error
```

- [ ] Write failing tests for signature, `kid`, issuer, audience, issued-at, expiry, nonce, stable subject mapping, no merge by matching email, no record on invalid credential, and ten-minute recent-auth linking. Generate an ephemeral RSA key/JWKS at test runtime; do not commit any private key or credential.
- [ ] Run `cd Server && go test ./internal/appleauth ./internal/auth ./internal/httpapi -run Apple`; expect failures.
- [ ] Implement cached JWKS verification and `(provider,subject)` uniqueness. An existing email plus a new Apple subject produces an independent user unless a recently authenticated principal calls Link.
- [ ] Run Go Apple unit and isolated MySQL identity tests; expect PASS. Commit `feat: add explicit apple identity linking`.

---

### Task 6: Add iOS account contracts, password validation, Keychain credentials, and anonymous account entry | covers: independent-account-access/匿名离线连续性, secure-device-sessions/Keychain 凭据存储

**Files:**
- Create: `PokerCoach/Infrastructure/Network/{APIClient,APIError,APIDTO}.swift`
- Create: `PokerCoach/Infrastructure/Auth/{AccountAPI,AccountSessionController,AppleAuthorizationClient,CredentialStore,KeychainCredentialStore,PasswordPolicy,SessionAuthorizer}.swift`
- Create: `PokerCoach/Features/Account/{AccountCenterView,EmailAccountView}.swift`
- Create: `PokerCoachTests/{PasswordPolicy,CredentialStore,AccountSessionController}Tests.swift`
- Update: `PokerCoach/App/AppDependencies.swift`, `PokerCoach/App/Root/AdaptiveRootView.swift`, localizations

**Interfaces:**

```swift
protocol CredentialStore: Sendable {
    func loadActive() async throws -> StoredSession?
    func saveActive(_ session: StoredSession) async throws
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws
    func clearActive() async throws
    func moveRefreshToPendingRevocation() async throws
    func loadPendingRevocation() async throws -> PendingSessionRevocation?
    func clearPendingRevocation() async throws
}

@MainActor @Observable final class AccountSessionController {
    private(set) var state: AccountSessionState
    func restore() async
    func register(email: String, password: String) async
    func verifyEmail(token: String) async
    func resendVerification() async
    func login(email: String, password: String) async
    func requestPasswordReset(email: String) async
    func confirmPasswordReset(token: String, newPassword: String) async
    func signInWithApple() async
    func linkApple() async
    func reauthenticate(_ proof: ReauthenticationProof) async
}

actor SessionAuthorizer {
    func validAccessToken() async throws -> String
    func authorize<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T
}
```

- [ ] Write failing tests for Swift NFC/scalar parity, Keychain save/load/delete/compare-and-replace, fail-closed errors, anonymous offline startup, register/verify/resend/reset/login/Apple/link states, generic login failure, one refresh and one original-request retry after 401, second-401 profile lock, and no token in UserDefaults or JSON fixtures.
- [ ] Run the focused `PokerCoachTests`; expect failures.
- [ ] Implement the complete typed `AccountAPI`, nonce-generating AuthenticationServices adapter, `URLSession` transport, Security-backed vault with test-injected operations, `SessionAuthorizer`, and Chinese recoverable errors. Account center implements verification token, resend, reset request/confirm, Apple sign-in/link, and reauthentication; it is a toolbar/split-view destination, not a fifth Tab and not a launch wall.
- [ ] Run iPhone and iPad model/UI smoke tests proving all four M1A entries remain usable anonymously and show “仅保存在本机”.
- [ ] Commit `feat: add local first account entry and keychain sessions`.

---

### Task 7: Route isolated profiles and claim anonymous history without rewriting it | covers: independent-account-access/邮箱密码登录, secure-device-sessions/本地账号数据隔离

**Files:**
- Create: `PokerCoach/Infrastructure/Profiles/{ProfileID,ProfileAssociationStore,ProfileDirectoryProvider,ActiveProfileController,ProfileLifecycleController}.swift`
- Create: `PokerCoachTests/{ProfileAssociationStore,ActiveProfileController,ProfileLifecycleController}Tests.swift`
- Update: `PokerCoach/App/AppDependencies.swift`, `PokerCoach/App/LocalIdentityStore.swift`

**Interfaces:**

```swift
actor ActiveProfileController {
    func current() async throws -> ActiveProfile
    func claimCurrent(remoteUserID: UUID) async throws -> ActiveProfile
    func activate(remoteUserID: UUID) async throws -> ActiveProfile
    func lockCurrent() async throws
}

struct ActiveProfile: Sendable {
    let id: ProfileID
    let localUserID: UUID
    let deviceID: UUID
    let directory: URL
}
```

- [ ] Write failing tests for installation-stable device ID, profile-stable local user ID, one-time anonymous claim, unchanged event bytes/IDs after claim, A→logout→B isolation, A restoration, and corrupt-backup directory isolation.
- [ ] Run focused tests; expect failures.
- [ ] Implement protected remote-user association storage and dynamic dependency routing for event store, Outbox, acknowledgements, checkpoint, pending revocation, and backups.
- [ ] Run existing M1A local identity and event-store tests plus new tests; expect PASS.
- [ ] Commit `feat: isolate and claim local training profiles`.

---

### Task 8: Persist recoverable Outbox state and track local event appends | covers: local-first-event-sync/本地先写与可恢复 Outbox, local-learning-profile/不可变本地训练事件

**Files:**
- Create: `PokerCoach/Infrastructure/Sync/{OutboxBatch,OutboxStore,FileOutboxStore,SyncStateStore,FileSyncStateStore,SyncTrackingTrainingEventStore}.swift`
- Create: `PokerCoachTests/{FileOutboxStore,SyncTrackingTrainingEventStore,OutboxReconciliation}Tests.swift`
- Update: `PokerCoach/App/AppDependencies.swift`

**Interfaces:**

```swift
protocol OutboxStore: Sendable {
    func pendingEventIDs() async throws -> Set<UUID>
    func enqueue(_ eventID: UUID) async throws
    func beginBatch(
        eventsByID: [UUID: TrainingEvent],
        limit: Int
    ) async throws -> OutboxBatch?
    func acknowledge(_ batch: OutboxBatch, eventIDs: Set<UUID>) async throws
}

actor SyncTrackingTrainingEventStore: TrainingEventStore {
    func append(_ event: TrainingEvent) async throws
    func appendRemote(_ event: TrainingEvent) async throws
}
```

- [ ] Write failing fault-injection tests: local append succeeds before enqueue, crash between writes, reconcile computes `all local − acknowledged − queued`, duplicate append stays single, corrupted history retains typed line number, and `appendRemote` never enqueues.
- [ ] Run focused tests; expect failures.
- [ ] Make Swift tests read the Task 1 `Contracts/training-event-upload-v1.json` and `.sha256` fixtures and assert byte-for-byte canonical encoding and the same hash Go will verify in Task 9.
- [ ] Implement atomic JSON state replacement and immutable in-flight batches containing key, ordered IDs, canonical encoded request Data, request hash, state, and createdAt. `beginBatch` resolves immutable events before persisting the batch, so later retries need no mutable resolver.
- [ ] Re-run new tests and M1A TrainingDomain store tests; expect PASS. Commit `feat: add recoverable local sync outbox`.

---

### Task 9: Implement transactional upload, idempotency conflicts, and paged MySQL pull | covers: local-first-event-sync/幂等批量上传, local-first-event-sync/单调 Checkpoint 拉取, mysql-sync-service/事务与唯一约束, mysql-sync-service/API 授权与输入验证

**Files:**
- Create: `Server/internal/sync/{event,validation,store,upload,pull}.go` and tests
- Create: `Server/internal/mysqlstore/{sync_upload_store,sync_pull_store}.go` and integration tests
- Create: `Server/internal/httpapi/{sync_upload_handler,sync_pull_handler}.go` and tests

**Interfaces:**

```go
func (s *sync.UploadService) Upload(context.Context, session.Principal, sync.UploadCommand) (sync.UploadResult, error)
func (s *sync.PullService) Pull(context.Context, session.Principal, uint64, int) (sync.EventPage, error)
func sync.HashUploadRequest(sync.UploadCommand) ([32]byte, error)
```

- [ ] Write failing service/HTTP tests for the shared golden body/hash, schema/UUID/body/batch/cursor bounds, user-scope ignoring payload user ID, same-key same-hash replay, same-key different-hash rollback, occurredAt rollback, empty/multi-page checkpoint rules, and `hasMore`.
- [ ] Write failing MySQL concurrency tests for duplicate event insertion and two same-user transactions. Hold the first row lock open and prove a third reader cannot observe the larger sequence before the smaller one commits.
- [ ] Implement the exact transaction order from design: sequence row `FOR UPDATE`, idempotency lookup/hash compare, new event sequence allocation, response persistence, commit.
- [ ] Implement `ORDER BY server_sequence LIMIT limit+1`; nonempty checkpoint is the last returned sequence and empty checkpoint equals the request.
- [ ] Run unit, HTTP, and isolated MySQL sync suites; expect PASS. Commit `feat: add transactional mysql event synchronization`.

---

### Task 10: Build the iOS SyncEngine, automatic recovery, and deterministic history refresh | covers: local-first-event-sync/单调 Checkpoint 拉取, local-first-event-sync/远端事件本地合并, local-first-event-sync/同步状态与自动恢复, local-learning-profile/跨设备历史确定性归约

**Files:**
- Create: `PokerCoach/Infrastructure/Sync/{SyncAPI,SyncEngine,SyncStatus}.swift`
- Create: `PokerCoachTests/{SyncAPIDTO,SyncEngine,TwoProfileConvergence}Tests.swift`
- Update: `PokerCoach/Features/Today/TodayViewModel.swift`, `PokerCoach/Features/Review/ReviewViewModel.swift`, `PokerCoach/App/AppDependencies.swift`

**Interfaces:**

```swift
actor SyncEngine {
    func synchronize(reason: SyncReason) async
    func retry() async
    func status() async -> SyncStatus
}

protocol SyncAPI: Sendable {
    func upload(_ batch: UploadBatch, accessToken: String) async throws -> UploadAcknowledgement
    func pull(after checkpoint: UInt64, limit: Int, accessToken: String) async throws -> EventPage
}
```

- [ ] Write failing tests for reconcile→upload→pull→merge ordering, exact in-flight byte retry after lost response, limit-one pagination, checkpoint persistence only after a full page merges, duplicate remote event, network recovery, 401→one refresh→one original-request retry, second authentication failure credential clear/profile lock, concurrent trigger serialization, and A/B convergence.
- [ ] Run focused tests; expect failures.
- [ ] Implement the actor and automatic triggers for launch, successful auth, foreground/network restoration, completed local decision, and manual retry. Route authenticated operations through Task 6 `SessionAuthorizer`; training continues regardless of sync failure.
- [ ] Publish an event-store revision after local completion or remote merge; Today and Review reload the active profile and deterministically reduce the deduplicated union.
- [ ] Run focused and M1A Today/Review tests; expect PASS. Commit `feat: synchronize and refresh local learning history`.

---

### Task 11: Add server recent reauthentication, export, and transactional account deletion | covers: account-data-rights/近期重新认证, account-data-rights/结构化数据导出, account-data-rights/账号与本机数据删除, mysql-sync-service/事务与唯一约束

**Files:**
- Create: `Server/internal/account/{models,store,service}.go` and tests
- Create: `Server/internal/mysqlstore/account_store.go`, integration tests
- Create: `Server/internal/httpapi/account_handlers.go`, tests
- Create: `Server/internal/httpapi/router.go`, `Server/cmd/api/main.go`

**Interfaces:**

```go
func account.RequireRecentAuthentication(session.Principal, time.Time, time.Duration) error
func (s *account.Service) Reauthenticate(context.Context, session.Principal, account.ReauthenticationProof) (time.Time, error)
func (s *account.Service) Export(context.Context, session.Principal) (account.ExportDocument, error)
func (s *account.Service) Delete(context.Context, session.Principal) error
```

- [ ] Write failing tests for password and Apple reauthentication proof, updating `sessions.recent_auth_at` only after valid proof, a ten-minute server-derived window, no partial export/delete when stale, export schema/account/devices/events only, absence of all credential hashes, and all bearer/refresh invalid after delete.
- [ ] Write a failing integration test that asserts deletion of identities, credentials, challenges, devices, sessions, refresh history, events, idempotency, and sequence in one transaction with no authenticatable orphan.
- [ ] Implement `/v1/auth/reauth`, repository transactions, and typed HTTP errors; reuse password verification and Apple credential verification while client-supplied time/user IDs have no authority.
- [ ] Run account unit, HTTP, and isolated MySQL tests; expect PASS.
- [ ] Commit `feat: add authenticated account export and deletion`.

---

### Task 12: Finish iOS devices, export bundle, deletion choices, and offline logout | covers: secure-device-sessions/设备会话管理, account-data-rights/结构化数据导出, account-data-rights/账号与本机数据删除, account-data-rights/安全退出

**Files:**
- Create: `PokerCoach/Infrastructure/Export/{AccountExportBuilder,AccountExportManifest}.swift`
- Create: `PokerCoach/Infrastructure/Auth/PendingRevocationProcessor.swift`
- Create: `PokerCoach/Features/Account/{DeviceSessionsView,DataRightsView,RecentAuthenticationView}.swift`
- Create: `PokerCoachTests/{AccountExportBuilder,AccountDeletion,OfflineLogout}Tests.swift`
- Update: `PokerCoach/Infrastructure/Auth/{AccountAPI,AccountSessionController,CredentialStore,KeychainCredentialStore}.swift`
- Update: `PokerCoach/Infrastructure/Profiles/ProfileLifecycleController.swift`
- Update: `PokerCoach/App/PokerCoachApp.swift`, `PokerCoach/App/AppDependencies.swift`

**Interfaces:**

```swift
struct AccountExportBuilder {
    func build(remote: RemoteAccountExport, profile: ActiveProfile, destination: URL) throws -> URL
}

@MainActor extension AccountSessionController {
    func logout() async
    func deleteAccount(localChoice: LocalDeletionChoice) async
}

actor PendingRevocationProcessor {
    func process() async
}
```

- [ ] Write failing tests for own-device display/revoke, recent-auth prompts, export manifest/schema/generatedAt/file list, raw corrupted backups included without upload, forbidden credential fields, cloud-delete keep-local anonymization, full current-profile deletion, other-profile preservation, and offline logout.
- [ ] Add a Security adapter test proving one `SecItemUpdate` atomically moves active refresh into the pending-revocation logical slot of the same Keychain vault item, clears active access, makes restore ignore pending, and lets later work only revoke it.
- [ ] Write pending processor tests for launch/foreground/network-restored triggers, revoke-only API use, transient retention, and clearing after success, already-revoked, or expired responses.
- [ ] Implement UI and export ZIP/directory bundle using Foundation APIs. Wire the pending processor to launch, foreground, and network-restored signals. Cloud deletion clears remote association; full deletion removes events, Outbox, checkpoint, acknowledgement, and corruption backups.
- [ ] Run iPhone/iPad account UI tests and focused unit tests; expect PASS. Commit `feat: add device and account data controls`.

---

### Task 13: Add two-device E2E verification, Release gates, and MySQL documentation handoff | covers: m1b-verification/一键 M1B 验证, m1b-verification/隔离测试环境, m1b-verification/密钥与开发能力隔离, local-learning-profile/能力画像归约, local-learning-profile/今日训练优先级, local-learning-profile/今日与复盘使用真实历史

**Files:**
- Create: `Server/test/e2e/two_devices_test.go`
- Create: `PokerCoachTests/LiveServerSyncContractTests.swift`
- Create: `PokerCoachUITests/AccountAndSyncTests.swift`
- Create: `scripts/check-m1b-release-secrets.sh`, `scripts/test-live-m1b.sh`, `scripts/verify-m1b.sh`
- Update: `README.md`
- Update: `docs/architecture/{index,components,sync,m1a-module-boundaries}.md`
- Update: `docs/product/scope-and-milestones.md`, `docs/standards/{testing,security}.md`, `openspec/config.yaml`

- [ ] Write the deterministic Go E2E and simulator `LiveServerSyncContractTests`: two isolated profile and credential directories use production `JSONAPIClient` against the temporary Go API/MySQL, create different events offline, authenticate to the same account, lose one upload response, pull with limit one, include an occurredAt rollback, and converge to identical event ID sets and Today/Review samples without duplicates.
- [ ] Add iPhone/iPad UI smoke tests for anonymous use, account center, pending/syncing/synced/failed status, account switching isolation, devices, export, deletion, and offline logout.
- [ ] Implement `check-m1b-release-secrets.sh` to scan tracked files for credentials/private keys/bypasses and scan the Release app bundle plus Go production binary/config for test tokens, SMTP passwords, development mailbox content, Apple test material, authentication bypasses, and `DevStrategyPack.json`. The tracked source fixture `PokerCoach/Resources/DevStrategyPack.json` is allowed only as an explicitly Debug-excluded M1A fixture.
- [ ] Implement `scripts/test-live-m1b.sh` to allocate a concrete loopback port, start the temporary API/MySQL, export `M1B_TEST_API_BASE_URL`, and run `LiveServerSyncContractTests`; implement `verify-m1b.sh` to run that script after `verify-m1a.sh`, all Go unit/integration/E2E tests, then run focused iOS UI tests on iPhone and iPad, Release builds, and secret checks. Cleanup uses traps and never touches an existing MySQL service/schema.
- [ ] Replace PostgreSQL references with MySQL/InnoDB in project truth, document exact tool versions/configuration and non-production mail/Apple setup, then run `bash scripts/verify-m1b.sh`, `git diff --check`, and `git status --short`. Expect every gate PASS and only intended files. Commit `docs: verify and hand off m1b identity sync`.

## Dependency order

```text
Task 1 → Task 2 → Task 3 → Task 4 → Task 5
                           └──────→ Task 9
Task 1 → Task 6 → Task 7 → Task 8
Task 6 + Task 8 + Task 9 ─────────→ Task 10
Task 4 + Task 5 ──────────────────→ Task 11
Task 6 + Task 7 + Task 10 + Task 11 → Task 12 → Task 13
```

Task 6 may begin after Task 1 locks the wire/config contracts. Task 5 and Task 9 may run independently after Task 4, while Tasks 6–8 form the client-side chain. Each Task still receives its own implementation, specification review, quality review, and repair commit.

## M1B completion gate

- `bash scripts/verify-m1b.sh` passes from a clean checkout.
- All 56 Scenarios have executable evidence; cross-layer Scenarios pass on both sides.
- M1A anonymous/offline training and all four entries still work on iPhone and iPad.
- MySQL integration uses only an isolated temporary server and proves row-locked sequence ordering.
- Tokens and password material never enter logs, UserDefaults, non-Keychain JSON storage, Release resources, or version control.
- Same-key/different-hash upload produces `idempotencyConflict` and zero writes.
- Two isolated devices converge after offline work, response loss, pagination, and client clock rollback.
- Account export omits credential material and includes local corruption backups only in the client bundle.
- Account deletion and offline logout preserve or remove local data exactly according to the user's explicit choice.
- Specification-compliance review and code-quality review are both approved for every Task.

## Self-Review Checklist

- [x] Capability 追溯表完整：proposal 中 7 个 Capability、31 个 Requirement、56 个 Scenario 均映射到 Task。
- [x] 每个 Task 的 `covers:` 与 Capability 追溯表一致。
- [x] 每个代码步骤包含确切文件、接口、测试命令或预期结果。
- [x] 不含实现占位表达；所有安全、事务、分页与恢复边界均有明确断言。
- [x] 跨 Task 的 wire schema、UUID、时间、token、profile、Outbox、checkpoint 和 recent-auth 契约一致。
- [x] M1B Non-Goals 未混入任务。

## 下一步

执行 `/harness-apply sync-m1b-identity-sync-20260807-01`，使用 Sub-agent 模式。
