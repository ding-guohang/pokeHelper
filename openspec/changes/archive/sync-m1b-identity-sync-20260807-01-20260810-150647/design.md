---
name: sync-m1b-identity-sync-20260807-01
status: designed
---

# M1B 独立身份与同步技术设计

## 方案概述

M1B 在 M1A 的离线现金局教练之上增加一个模块化 Go 单体、MySQL/InnoDB 持久层以及 iOS App Infrastructure 认证与同步层：

```text
SwiftUI Account / Sync UI
  → AccountSessionController / SyncEngine
  → HTTPS JSON API
  → Go Auth / Session / Sync / Account
  → MySQL 8.4+ InnoDB
```

客户端继续以本地 `TrainingEventStore` 为第一读写源。登录不是训练墙；网络、认证、Keychain 和 MySQL DTO 不进入 `PokerCore`、`StrategyContent` 或 `TrainingDomain`。

完整批准设计见 `docs/superpowers/specs/2026-08-07-m1b-identity-sync-design.md`，本文件记录 Harness 实施所需的稳定技术决策。

## 选择该方案的原因

### 对比过的方案

1. **模块化 Go 单体 + MySQL（采用）**：认证、同步和数据权利共享事务边界，部署与测试成本适合 M1B，内部 package 仍可在规模增长后拆分。
2. **认证与同步微服务**：隔离更强，但当前需要分布式事务、服务发现和额外部署，不能提高首个账号同步闭环的产品价值。
3. **CloudKit 或 BaaS**：实现更快，但违背独立后端、未来 Android/Web 和供应商无关的已批准方向。

### 关键取舍

- 邮箱登录使用密码；邮箱验证与密码重置使用一次性挑战。
- 密码采用 Argon2id PHC，15–128 个 Unicode scalar，NFC 规范化，不使用组合规则，并校验弱密码 blocklist。
- Apple subject 与邮箱身份不按邮箱自动合并；关联必须先近期认证。
- access/refresh token 均为随机不透明值，服务端只保存 hash；refresh token 保留 consumed/revoked 历史以检测重放。
- 同步 sequence 不使用 AUTO_INCREMENT 作为游标真值；每个用户通过 `user_sync_sequences` 行锁在同一 InnoDB 事务内串行分配。
- 远端 ownership 来自 bearer session；事件内 `localUserID` 和 `deviceID` 保留但不参与授权。
- 生产部署、域名与真实 SMTP/Apple 密钥不在 M1B 自动执行范围内。

## iOS 模块设计

### Account

新增 `PokerCoach/Infrastructure/Auth/`：

- `AccountSessionController`：actor/主线程展示状态桥，管理 anonymous、awaiting verification、authenticated、locked 和 recoverable failure。
- `CredentialStore`：Keychain-backed access/refresh/session/user 凭据。
- `AppleAuthorizationClient`：AuthenticationServices 适配器，生成 nonce 并返回 credential DTO。
- `AccountAPI`：注册、验证、登录、重置、Apple、refresh、reauth 和 logout 协议。

账号中心由根导航工具栏进入，不增加第五个主 Tab。

### Profile

新增 `PokerCoach/Infrastructure/Profiles/`：

- `ProfileID`：本机 opaque ID。
- `ProfileAssociationStore`：远端 user 与本机 profile 的受保护映射。
- `ProfileDirectoryProvider`：为匿名与账号 profile 提供独立目录。
- `ProfileLifecycleController`：匿名认领、退出锁定、重新登录恢复、账号删除后的匿名化或删除。

每个 profile 独立保存事件日志、Outbox、acknowledgement、checkpoint、待撤销会话和损坏历史备份。已有 M1A `localUserID`、`deviceID` 和事件正文不改写。

### Sync

新增 `PokerCoach/Infrastructure/Sync/`：

- `OutboxStore`：持久记录 pending、in-flight、acknowledged event ID 与 idempotency key。
- `SyncStateStore`：server checkpoint、远端确认和 pending revocation。
- `SyncTrackingTrainingEventStore`：装饰既有 store，先本地追加再入 Outbox。
- `SyncAPI`：批量上传与分页拉取协议。
- `SyncEngine`：actor，串行执行 reconcile → upload → pull → merge → checkpoint。

每轮同步先以“全部本地事件 − 已确认事件 − 已排队事件”恢复 Outbox。非空拉取页的 checkpoint 必须是该页最后返回 sequence；整页合并成功后才持久化，循环至 `hasMore == false`。

## Go 服务设计

### 目录与依赖

```text
Server/
  cmd/api/
  internal/
    account/
    appleauth/
    auth/
    config/
    httpapi/
    mail/
    mysqlstore/
    password/
    session/
    sync/
  migrations/
  test/
```

使用 Go `net/http`、锁定版本的 MySQL driver、`golang.org/x/crypto`、`golang.org/x/text` 和 UUID 库；`x/text/unicode/norm` 负责密码 NFC 规范化。不使用 ORM、Web framework 或全局 service locator。

### HTTP API

- `/v1/auth/*`：register、verify-email、resend、login、password reset、apple、link apple、refresh、reauth、logout。
- `/v1/sessions`：列出与撤销设备会话。
- `/v1/sync/events`：POST 批量上传，GET checkpoint 分页拉取。
- `/v1/account`：读取、导出、删除。
- `/health`：存活与依赖状态。

API 使用稳定错误 code、request ID 和可选 retry-after；日志不输出密码、token、邮件正文或完整事件 payload。

### MySQL 数据模型

所有表使用 MySQL 8.4+、InnoDB、`utf8mb4` 和版本化迁移：

- `users`
- `auth_identities`
- `password_credentials`
- `email_challenges`
- `devices`
- `sessions`
- `refresh_tokens`
- `auth_throttles`
- `user_sync_sequences`
- `training_events`
- `idempotency_records`
- `schema_migrations`

关键约束：

- `UNIQUE(provider, subject)`
- `UNIQUE(user_id, event_id)`
- `UNIQUE(user_id, server_sequence)`
- `UNIQUE(user_id, idempotency_key)`
- refresh token hash 全局唯一

上传事务锁定该用户的 sequence row，只为新事件分配连续值。相同 idempotency key 只有 request hash 一致时返回原响应；否则返回 `idempotencyConflict` 并整批回滚。

## 稳定接口与持久化契约

### TrainingEvent wire envelope

- `schemaVersion` 固定从 `1` 开始；未知主版本返回 typed `unsupportedSchemaVersion`。
- UUID 使用小写连字符字符串；时间使用 UTC RFC 3339、最多毫秒精度。
- 单次上传最多 100 个事件、解压前 JSON 正文最多 1 MiB；分页 `limit` 为 1–200。
- request hash 是规范 JSON 中 `schemaVersion` 与有序 `events` 数组的 SHA-256；幂等键不进入 hash。
- 客户端创建批次后不得改变事件顺序或正文，直至收到确认或 typed 冲突。

### Outbox 与远端合并

`OutboxBatch` 稳定字段为 `idempotencyKey`、有序 `eventIDs`、规范 `encodedRequestBody`、`requestHash`、`state` 和 `createdAt`。`encodedRequestBody` 以 Data/base64 持久化，进入 `inFlight` 的批次必须逐字节原样重试，避免 App 升级后编码器变化。Swift 与 Go 共同读取 `Contracts/training-event-upload-v1.json` 和对应 SHA-256 golden fixture。同步拉取使用底层 `FileTrainingEventStore` 的幂等 append 路径，不能经过 `SyncTrackingTrainingEventStore`，否则远端事件会再次入队。

### Profile 与凭据

- `deviceID` 是安装级稳定 ID；`localUserID` 是 profile 级稳定 ID。
- `ActiveProfileController` 在账号切换时重新路由 event store、Outbox、acknowledgement、checkpoint 和损坏备份目录。
- `CredentialStore` 必须提供 `saveActive`、`loadActive`、`clearActive` 和原子的 `moveRefreshToPendingRevocation`。active 与 pending-revocation 是同一个 Keychain vault item 内的两个逻辑槽，移动使用一次 `SecItemUpdate`，避免跨 item 操作无法原子化；pending token 不可恢复认证，只能调用 revoke。
- `recentAuthAt` 只采用服务端 session principal 中的值，客户端时间或 UserDefaults 不能扩大敏感操作窗口。
- APP 在启动、进入前台和网络恢复时运行 pending-revocation processor；它只能使用 pending refresh token 调用 logout/revoke，并在成功、已撤销或已过期后清除 pending 槽。
- 收到 401 时 `SessionAuthorizer` 最多轮换一次 refresh token 并重试原请求一次；第二次认证失败或 refresh replay 才清除 active 凭据并锁定 profile。

### MySQL 事务顺序

初始迁移写全外键与 `ON DELETE` 行为、challenge purpose/expiry 索引、设备唯一约束、幂等 response schema 与 sequence 初值。上传在同一事务内依次锁定 `user_sync_sequences`、检查幂等记录、分配新 sequence、写事件与最终 response 后提交；因此更大的 sequence 不能早于较小的 sequence 提交。

## 跨语言验证边界

`scripts/verify-m1b.sh` 启动临时 MySQL 与本机 Go API，再从 iOS Simulator 运行 `LiveServerSyncContractTests`。该测试使用生产 `JSONAPIClient`、两个独立 profile/Keychain 测试 vault 和真实 HTTP 合约完成注册、验证、登录、离线事件、丢失响应重试、分页拉取及确定性 Today/Review 归约。Go 与 Swift 的 wire/hash golden fixture 是补充证据，不替代真实 Swift→Go→MySQL 闭环。

## 账号与数据流

### 匿名历史认领

```text
anonymous profile
  → 用户登录/注册完成验证
  → 服务端返回 remote user/session
  → ProfileAssociationStore 绑定当前 profile
  → Outbox reconcile 发现全部未确认事件
  → 幂等上传，不改写 event
```

### 跨设备同步

```text
本地 append
  → Outbox
  → POST events (idempotency key)
  → ack event IDs
  → GET events after checkpoint
  → append through TrainingEventStore
  → checkpoint
  → Today / Review refresh
```

### 离线退出

refresh token 从活动 Keychain item 原子移动到 pending-revocation Keychain item。界面立即退出并锁定 profile；网络恢复后该 token 只能用于 revoke，成功或过期后删除。

### 导出与删除

敏感操作要求十分钟内的近期重新认证。服务端导出版本化 JSON；APP 生成最终 bundle，并把当前 profile 的损坏历史备份作为原始附件加入且不上传。删除远端账号后，用户可选择把本机历史匿名化保留，或删除该 profile 的事件、同步状态和备份。

## Capability 覆盖

| Capability | 技术实现 |
|---|---|
| `independent-account-access` | Go auth/password/apple/mail + iOS Account UI/Controller |
| `secure-device-sessions` | Keychain、opaque token rotation、refresh history、session/device API、profile isolation |
| `local-first-event-sync` | Outbox、reconcile、idempotent upload、per-user sequence、paged pull、merge |
| `mysql-sync-service` | Go modular monolith、MySQL migrations/repositories、rate limits、typed API |
| `account-data-rights` | recent reauth、server JSON、local export bundle、transactional delete |
| `m1b-verification` | isolated MySQL、Go/iOS tests、two-profile E2E、Release gates |
| `local-learning-profile` | merged events continue through existing reducer into Today/Review |

## 向后兼容

- `TrainingEvent` 字段、JSON 编码和评分内容不变。
- `TrainingEventStore` 与 `FileTrainingEventStore` 的 append、allEvents 和 append-order checkpoint 语义不变。
- M1A 的四入口、离线训练和 Debug/Release 内容隔离保持。
- M1B 新增 server checkpoint，不能与本地 event-ID checkpoint 混用。
- 现有匿名安装首次登录时只增加远端 ownership，不重写历史。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| MySQL sequence 先分配后乱序提交 | 用户级 sequence row `FOR UPDATE`，分配与事件写入同事务 |
| 同键不同请求静默复用旧确认 | request hash 比较，不同则 typed conflict |
| event append 后 Outbox 前崩溃 | 每次同步前从本地完整事件日志对账 |
| 刷新令牌重放无法识别 | 保留 consumed refresh token hash 历史并撤销 family |
| Apple 相同邮箱账号接管 | 不按邮箱自动合并，必须近期认证后显式关联 |
| 同设备账号间数据泄露 | profile 目录与关联状态隔离，退出只锁定自己的 profile |
| 导出遗漏损坏历史 | APP export bundle 显式加入本地原始备份 |
| 网络错误阻断训练 | 本地先写，所有同步错误只影响同步状态 |

## 测试策略

- Go 单元测试：密码、认证、Apple verifier、session rotation、rate limit、typed HTTP errors。
- MySQL 集成测试：迁移、事务回滚、唯一约束、同用户并发 sequence、分页 checkpoint、幂等冲突、删除级联。
- iOS 单元测试：Keychain fail closed、账号状态、profile 生命周期、Outbox 恢复、SyncEngine、导出与删除。
- iPhone/iPad UI：匿名继续、邮箱账号流程、同步状态、设备管理。
- 双 profile 端到端：各自离线事件最终双向合并且无重复。
- Release：无开发邮箱、测试 token、认证 bypass、SMTP/Apple secret 或 M1A fixture。
- `scripts/verify-m1b.sh` 组合 M1A 回归、Go、隔离 MySQL、iOS 与端到端验证。

## 完成边界

M1B 只有在每个 task 的 TDD、规格评审、代码质量评审和最终全量验证通过后完成。M1 仍需 M1C 的初始诊断、已审核现金局课程、能力树和间隔复练才能验收。
