# M1B 独立身份与同步设计

## 1. 目标与边界

M1B 在 M1A 的离线训练闭环之上增加独立账号、MySQL 后端和跨设备同步，但不让网络成为训练前提。用户未登录或断网时仍能训练、评分和复盘；登录后，现有匿名历史被绑定到远端账号，并通过可恢复 Outbox 在 iPhone 与 iPad 间幂等合并。

M1B 交付可本地完整验证、可配置部署的客户端和服务端代码。生产服务器、域名、真实 SMTP 凭据和 Apple 生产密钥需要独立部署授权，不在本阶段擅自创建。

## 2. 已批准决策

- 邮箱认证使用邮箱和密码，不使用验证码或 Magic Link 作为登录方式。
- 同时支持 Sign in with Apple。
- 服务端采用模块化 Go 单体，而不是微服务或 BaaS。
- 数据库采用 MySQL/InnoDB，不使用 PostgreSQL。
- MySQL 8.4 为最低兼容基线；本地开发环境可使用已安装的 MySQL 9.6。
- 客户端保持本地优先，登录不是训练墙。
- M1A 的 `TrainingEvent`、`TrainingEventStore`、`FileTrainingEventStore` 和 `StrategyPackManifest` 语义不变。

## 3. 总体架构

```text
SwiftUI Account / Sync UI
        │
        ▼
App Infrastructure
  ├─ AccountSessionController
  ├─ KeychainCredentialStore
  ├─ ProfileStore
  ├─ OutboxStore
  ├─ SyncEngine
  └─ APIClient
        │ HTTPS JSON
        ▼
Go API
  ├─ Auth
  ├─ Sessions
  ├─ Sync
  ├─ Account Rights
  ├─ Mail
  └─ MySQL Repositories
        │
        ▼
MySQL 8.4+ / InnoDB
```

网络、认证和 MySQL DTO 只存在于 App Infrastructure 与 Go 服务。`PokerCore`、`StrategyContent` 和 `TrainingDomain` 不依赖 HTTP、Keychain、MySQL 或服务端模型。

## 4. iOS 客户端设计

### 4.1 账号入口

四个核心导航入口保持不变。账号中心从根界面工具栏进入，按状态展示：

- 未登录：继续本机使用、邮箱注册、邮箱登录、Apple 登录。
- 待验证：重新发送验证邮件、输入验证凭据、退出待验证账号。
- 已登录：同步状态、邮箱/Apple 身份、设备会话、数据导出、退出和删除账号。

登录不阻断 Today、Learn、Train 或 Review。未登录时同步状态显示“仅保存在本机”。

### 4.2 账号状态

`AccountSessionController` 使用显式状态机：

```text
anonymous
registering
awaitingEmailVerification
authenticating
authenticated
refreshing
locked
failed(recoverable)
```

ViewModel 只驱动交互与中文错误。密码政策、凭据校验、会话轮换和远端授权由服务端决定。

### 4.3 Keychain

`CredentialStore` 协议隔离 Keychain：

- access token
- refresh token
- session ID
- remote user ID
- last strong authentication time

生产实现使用 Security.framework；测试使用内存实现。Keychain 失败时 fail closed，不回退到 UserDefaults、JSON 文件或日志。

### 4.4 本地 Profile 隔离

Application Support 下按 installation profile 分目录：

```text
Profiles/
  anonymous-{installationProfileID}/
  account-{opaqueLocalProfileID}/
```

每个 profile 独立保存：

- `training-events.jsonl`
- Outbox journal
- remote acknowledgement state
- server checkpoint
- 损坏历史备份
- 待处理会话撤销

匿名 profile 只能被第一个远端账号认领一次。远端 user ID 与本地 opaque profile ID 的映射不进入日志。退出账号后 profile 被锁定；其他账号或新的匿名 profile 不读取该目录。

### 4.5 训练写入与 Outbox

训练提交顺序保持：

1. 确定性评分。
2. `TrainingEventStore.append(event)`。
3. 进入反馈。

同步层通过 `SyncTrackingTrainingEventStore` 装饰现有 store，在本地追加成功后记录 Outbox。由于两次本地写入不能共享文件事务，启动和每次同步前必须执行对账：

```text
all local event IDs
  − remote acknowledged IDs
  − already queued IDs
  = recovered pending IDs
```

即使 APP 在 event append 与 Outbox append 之间终止，事件仍会在下次对账重新入队。

### 4.6 SyncEngine

`SyncEngine` 是 actor，单次只运行一个同步周期：

1. 恢复缺失 Outbox 项。
2. 按固定上限读取待上传事件。
3. 使用稳定 idempotency key 批量上传。
4. 持久化服务端确认。
5. 使用当前 server checkpoint 分页拉取。
6. 通过既有 `TrainingEventStore.append` 幂等合并。
7. 持久化新 checkpoint。
8. 触发 Today 与 Review 从完整本地历史刷新。

触发时机：

- APP 启动且已登录。
- APP 回到前台。
- 新 TrainingEvent 保存后。
- 网络恢复。
- 用户手动刷新。

失败使用指数退避和有界随机抖动；认证失败只刷新一次，仍失败则清除 Keychain 会话并锁定 profile。训练永远不等待同步成功。

## 5. Go 服务设计

### 5.1 目录

```text
Server/
  cmd/api/
  internal/
    auth/
    session/
    sync/
    account/
    mail/
    httpapi/
    mysqlstore/
    config/
  migrations/
  test/
  go.mod
```

使用 Go 标准 `net/http` 路由。第三方运行时依赖只包含锁定版本的 MySQL driver、`golang.org/x/crypto` 和必要 UUID 包；不引入 Web framework、ORM 或依赖注入框架。

### 5.2 HTTP API

```text
POST   /v1/auth/register
POST   /v1/auth/verify-email
POST   /v1/auth/resend-verification
POST   /v1/auth/login
POST   /v1/auth/password-reset/request
POST   /v1/auth/password-reset/confirm
POST   /v1/auth/apple
POST   /v1/auth/link/apple
POST   /v1/auth/refresh
POST   /v1/auth/reauth
POST   /v1/auth/logout

GET    /v1/account
GET    /v1/account/export
DELETE /v1/account

GET    /v1/sessions
DELETE /v1/sessions/{sessionID}

POST   /v1/sync/events
GET    /v1/sync/events?after={sequence}&limit={pageSize}

GET    /health
```

所有受保护接口从 bearer token 解析远端用户，不接受客户端 user ID 作为授权真值。错误响应使用稳定 code、中文可映射 message key、request ID 和可选 retry-after，不回显敏感输入。

### 5.3 密码

- 规范化邮箱使用 trim + Unicode-safe lowercase，并保存展示邮箱与 canonical email。
- 密码允许 15–128 个 Unicode scalar，并允许空格；长度不按 UTF-8 字节计算。
- 不要求大小写、数字或符号组合。
- 注册和重置时对完整密码执行常见/泄露弱密码 blocklist。
- 使用 Argon2id，最低参数 `m=19456 KiB, t=2, p=1`。
- 每个密码使用独立随机 salt。
- 保存标准 PHC 字符串，登录时若参数落后则成功验证后升级。
- 登录失败使用相同外部语义；账号与网络信号均进行速率限制。

### 5.4 邮箱验证与重置

邮箱挑战只保存 token hash、用途、过期时间、尝试次数和 consumed-at。投递接口分为：

- `MemoryMailer`：Go 测试。
- `DevelopmentMailbox`：本地端到端测试，凭据不写普通日志。
- `SMTPMailer`：由环境变量提供 host、port、username、password、sender 和 TLS 模式。

非开发环境缺少 SMTP 配置时服务拒绝启动。注册与重置请求对账号存在性返回相同语义。

### 5.5 Apple 登录

iOS 使用 AuthenticationServices 生成随机 nonce 并获取 credential。服务端验证：

- Apple 公钥签名与 key ID。
- issuer。
- bundle/service audience。
- expiry 与 issued-at。
- nonce。

Apple subject 是身份唯一键。Apple 邮箱不能触发自动账号合并；关联现有账号需要近期认证和新的 Apple credential。

### 5.6 会话

- access token：32 字节随机不透明值，15 分钟有效。
- refresh token：32 字节随机不透明值，30 天有效。
- 数据库只保存 SHA-256 token hash。
- 每次 refresh 轮换两种 token。
- 已使用 refresh token 再出现时撤销整个 session family。
- 会话记录设备名称、平台、APP 版本、创建时间、最近活动和撤销时间。

客户端退出时服务端撤销当前 refresh session。离线退出将 refresh token 从活动会话 Keychain item 原子移动到不可用于登录恢复的 pending-revocation Keychain item；界面立即退出并锁定 profile，网络恢复后只使用该 token 调用撤销接口，成功或过期后删除待撤销项。

## 6. MySQL 数据设计

最低版本 MySQL 8.4，所有表使用 InnoDB、`utf8mb4`，迁移显式版本化。

| 表 | 关键字段与约束 |
|---|---|
| `users` | `id CHAR(36) ascii_bin PK`、状态、created/deleted timestamps |
| `auth_identities` | provider、subject、canonical email、verified；`UNIQUE(provider,subject)` |
| `password_credentials` | user ID unique、PHC hash、password changed-at |
| `email_challenges` | token hash `BINARY(32)`、purpose、expiry、consumed-at |
| `devices` | user ID、installation device ID、display metadata；用户内唯一 |
| `sessions` | token family、access/refresh hashes、expiry、revoked-at、recent-auth-at |
| `training_events` | `server_sequence BIGINT UNSIGNED AUTO_INCREMENT`、user ID、event ID、device ID、payload JSON；`UNIQUE(user_id,event_id)` |
| `idempotency_records` | user ID、key、request hash、response JSON；`UNIQUE(user_id,key)` |
| `schema_migrations` | version PK、applied-at |

`TrainingEvent` payload 在写入前由 Go DTO 完成大小、schema version、UUID、日期、单位字段和必填字段验证。远端 `user_id` 是独立列并来自会话；payload 中原 `localUserID` 和 `deviceID` 保留用于历史追溯，但不参与授权。

上传批次在一个 InnoDB 事务中完成。重复 event ID 或 idempotency key 映射为成功确认，任何非重复错误使整批回滚。

拉取使用 `server_sequence > checkpoint ORDER BY server_sequence LIMIT ?`。sequence 只定义同步顺序，不替代 `occurredAt` 的学习时间语义。

## 7. 数据权利与本地隐私

敏感操作要求十分钟内的近期重新认证：

- 密码账号重新提交密码。
- Apple 账号提交新的 Apple credential。

导出返回带 schema version、生成时间、账号元数据、设备和训练事件的 JSON，不含密码哈希、token hash 或挑战凭据。

删除账号在 MySQL 事务内删除全部当前 M1B 数据并撤销会话。APP 随后清除 Keychain，并单独询问本机历史的处理方式：选择保留时，清除远端 acknowledgement、checkpoint 与账号绑定，把事件历史转为新的匿名本机 profile；选择删除时，删除该 profile 的事件、Outbox、checkpoint 和损坏历史备份。不同 profile 不受影响。

## 8. 错误处理

| 错误 | 客户端行为 |
|---|---|
| 离线/超时 | 保持本地功能，显示待同步并自动重试 |
| 429 节流 | 显示等待时间，不连续请求 |
| access 过期 | 使用 refresh token 重试一次 |
| refresh 失效/重放 | 清除 Keychain、锁定 profile、要求登录 |
| MySQL 暂时不可用 | API 返回可重试错误，不确认事件 |
| 事件 schema 无效 | 整批拒绝，标出安全的 event ID 与 error code |
| checkpoint 越界 | 返回 typed error，客户端执行受控全量重建而不删除本地事件 |
| Keychain 失败 | fail closed，不降级存储 |
| 本地历史损坏 | 沿用 M1A 的显式备份后恢复，不自动截断 |

## 9. 测试设计

### Go

- 密码政策、Argon2id PHC 编解码与参数升级。
- 注册、验证、登录、重置、通用失败和速率限制。
- Apple token verifier 使用固定签名夹具与 nonce。
- refresh rotation、重放撤销和设备会话范围。
- MySQL 空库/重复迁移。
- 并发重复事件、幂等响应和事务回滚。
- checkpoint 在 occurredAt 回拨时仍不漏事件。
- 导出不含凭据、删除无孤立数据。

### iOS

- Keychain wrapper 与 fail-closed 行为。
- 账号状态机与中文错误映射。
- profile 认领、退出锁定和账号隔离。
- event append 后 Outbox 入队。
- append/queue 中断后的启动对账。
- 上传响应丢失重试、重复 pull、checkpoint 持久化。
- 401 refresh 一次、重放锁定和离线恢复。
- 同步后 Today/Review 使用跨设备事件。

### 端到端

`scripts/verify-m1b.sh`：

1. 运行 M1A 完整回归。
2. 启动使用临时 data directory、独立端口和测试账号的 MySQL。
3. 应用迁移并运行 Go tests。
4. 启动本地 Go API 与 development mailbox。
5. 运行 iPhone/iPad 账号 UI 测试。
6. 模拟两个 installation profile 各自离线创建事件。
7. 联网后上传与拉取，验证最终 event ID 集合相同且无重复。
8. 构建 Release，检查没有开发邮箱、测试 token、认证 bypass 或 M1A fixture。
9. 停止临时服务并删除临时测试目录。

验证脚本不得启动、停止或修改开发者已有 MySQL 服务和 schema。

## 10. 实施分解原则

实现按以下可独立评审的纵向顺序推进：

1. Go 工程、配置和隔离 MySQL 验证框架。
2. MySQL migrations 与 repository 契约。
3. 密码政策、邮箱注册验证与登录。
4. refresh session、设备管理和 Keychain。
5. Apple credential 验证与显式身份关联。
6. iOS profile 隔离和匿名历史认领。
7. Outbox、上传幂等和 checkpoint 拉取。
8. 账号中心与同步状态 UI。
9. 导出、退出和删除。
10. 双设备端到端、Release 门禁和文档交接。

每个任务采用 TDD，并分别通过规格符合性和代码质量评审后才能完成。

## 11. 后续演进

- M1C 在同一远端用户和事件集合之上增加诊断、已审核课程与间隔复练，不改变同步 ownership。
- M2 牌谱与场景使用版本化资源和独立冲突副本，不塞入 `TrainingEvent`。
- M3 继续复用 2–9 人桌位置、内容版本和评分契约。
- M4 为现有 Go 服务增加订阅权益、生产部署、观测和正式邮件运营，不重新设计学习闭环。
