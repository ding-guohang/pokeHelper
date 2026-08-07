---
name: sync-m1b-identity-sync-20260807-01
created: 2026-08-07
status: review_passed
---

# 需求提案：M1B 独立身份与同步

## Why

M1A 已证明离线现金局教练闭环可运行，但训练历史仍只存在单台设备。M1B 需要在不破坏本地优先体验和既有 `TrainingEvent` 语义的前提下，建立独立账号、MySQL 后端、跨设备幂等同步和用户数据权利，为 M1C 的诊断、课程进度与间隔复练提供稳定身份和数据地基。

## What Changes

### New Capabilities

- `independent-account-access` — 提供匿名离线使用、邮箱密码账号、邮箱验证、密码重置和 Apple 登录。
- `secure-device-sessions` — 使用 Keychain 保存令牌，提供轮换会话、设备管理和本地账号数据隔离。
- `local-first-event-sync` — 在本地事件日志之上增加可恢复 Outbox、幂等上传和单调 Checkpoint 拉取。
- `mysql-sync-service` — 提供 Go HTTPS API、MySQL 8.4+ 数据模型、事务隔离、邮箱投递边界和安全门禁。
- `account-data-rights` — 提供近期重新认证、结构化数据导出、账号删除和本机数据删除选择。
- `m1b-verification` — 一键验证 M1A 回归、Go 服务、隔离 MySQL、iPhone/iPad 账号与双设备同步。

### Modified Capabilities

- `local-learning-profile` — 保留 M1A 的全部本地画像行为，并让已同步的跨设备事件进入同一确定性归约。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: independent-account-access

#### Requirement: 匿名离线连续性

The system SHALL allow a user without a remote account or active session to continue using deterministic training and local history.

##### Scenario: 首次离线启动

- GIVEN APP 没有远端会话且网络不可用
- WHEN 用户启动 APP
- THEN 今日、学习、训练和复盘仍可进入
- AND 本地决策继续写入现有不可变 TrainingEvent 日志

##### Scenario: 登录入口不阻断训练

- GIVEN 用户尚未登录
- WHEN 用户忽略账号入口并开始训练
- THEN 系统不强制展示登录墙
- AND 同步状态明确显示“仅保存在本机”

#### Requirement: 邮箱密码注册

The system SHALL register a canonical email identity with a verified password policy and require email verification before remote synchronization.

##### Scenario: 合法注册

- GIVEN 用户提交格式合法且未占用的邮箱以及 15–128 个 Unicode scalar、未命中弱密码列表的密码
- WHEN 服务端完成注册
- THEN 密码以带独立 salt 和参数的 Argon2id PHC 字符串保存
- AND APP 进入等待邮箱验证状态
- AND 未验证账号不能上传或下载训练事件

##### Scenario: 不合规密码

- GIVEN 密码少于 15 个 Unicode scalar、超过 128 个 Unicode scalar 或命中弱密码列表
- WHEN 用户提交注册
- THEN 服务端拒绝注册并返回 typed validation error
- AND 系统不要求大小写、数字或符号组合规则

##### Scenario: Unicode 密码长度边界

- GIVEN 密码包含由多个 UTF-8 字节表示的 Unicode scalar
- WHEN 客户端和服务端校验密码长度
- THEN 两端都按 Unicode scalar 而不是 UTF-8 字节计数
- AND 15 与 128 个 scalar 被接受，14 与 129 个 scalar 被拒绝

##### Scenario: 邮箱枚举保护

- GIVEN 邮箱已经注册
- WHEN 未认证调用方再次请求注册或密码重置
- THEN API 返回与未注册邮箱不可区分的接受响应
- AND 日志不记录邮箱正文、密码或验证凭据

#### Requirement: 邮箱验证与密码重置

The system SHALL use expiring, single-use email challenges for email verification and password reset.

##### Scenario: 一次性邮箱验证

- GIVEN 用户收到仍在有效期内且未使用的验证凭据
- WHEN 用户提交正确凭据
- THEN 邮箱身份变为已验证
- AND 同一凭据再次提交被拒绝

##### Scenario: 密码重置

- GIVEN 已验证用户完成有效的密码重置挑战
- WHEN 用户设置合规的新密码
- THEN 新密码替换旧密码
- AND 该账号的既有刷新会话全部失效

#### Requirement: 邮箱密码登录

The system SHALL authenticate a verified email identity with a generic failure response and bind the installation profile to the remote user.

##### Scenario: 成功登录并认领匿名历史

- GIVEN 当前安装有稳定 localUserID、deviceID 和尚未绑定的本地训练事件
- WHEN 已验证用户使用正确邮箱密码登录
- THEN 服务端创建该设备的独立会话
- AND 本地身份与历史绑定到远端用户但事件正文及 ID 不被改写
- AND 后续同步上传既有匿名历史

##### Scenario: 通用登录失败

- GIVEN 邮箱不存在、尚未验证或密码错误
- WHEN 用户尝试登录
- THEN API 返回相同的认证失败语义
- AND 不泄露账号是否存在

#### Requirement: Apple 登录与显式身份关联

The system SHALL authenticate Sign in with Apple credentials and map each verified Apple subject to one independent user.

##### Scenario: 合法 Apple 登录

- GIVEN APP 获得带匹配 nonce 的有效 Apple credential
- WHEN 服务端完成签名、issuer、audience、expiry 和 nonce 校验
- THEN Apple subject 映射到稳定远端用户
- AND 当前安装的本地身份可按与邮箱登录相同规则绑定

##### Scenario: 相同邮箱不自动合并

- GIVEN Apple 返回的邮箱与现有邮箱密码账号相同但用户未先认证现有账号
- WHEN 服务端处理 Apple 登录
- THEN 系统不依据邮箱自动合并身份
- AND 只有近期认证的账号持有者可以显式关联 Apple 身份

##### Scenario: 无效 Apple credential

- GIVEN Apple credential 的签名、audience、expiry 或 nonce 任一无效
- WHEN 服务端验证凭据
- THEN 登录被拒绝
- AND 不创建用户、身份或会话

### Capability: secure-device-sessions

#### Requirement: Keychain 凭据存储

The system SHALL store access and refresh credentials only in Keychain-backed secure storage.

##### Scenario: 会话持久化

- GIVEN 用户成功登录
- WHEN APP 保存远端会话
- THEN access token 和 refresh token 写入 Keychain
- AND UserDefaults、本地 JSON、诊断日志和崩溃信息不包含令牌

##### Scenario: Keychain 不可用

- GIVEN Keychain 读取或写入失败
- WHEN APP 尝试建立或恢复会话
- THEN APP 返回中文可恢复错误
- AND 不把令牌降级保存到非安全存储

#### Requirement: 不透明令牌与刷新轮换

The system SHALL issue random opaque access and refresh tokens, persist only their hashes, and rotate refresh tokens.

##### Scenario: 正常刷新

- GIVEN access token 已过期且 refresh token 有效
- WHEN 客户端请求刷新
- THEN 服务端签发新的 access token 和 refresh token
- AND 旧 refresh token 立即失效

##### Scenario: 刷新令牌重放

- GIVEN 已轮换的旧 refresh token 再次被使用
- WHEN 服务端检测到重放
- THEN 对应会话族全部撤销
- AND 客户端回到需要登录状态而不删除本地训练历史

#### Requirement: 设备会话管理

The system SHALL let an authenticated user inspect and revoke device sessions without trusting a client-supplied user ID.

##### Scenario: 查看设备

- GIVEN 用户拥有多个有效设备会话
- WHEN 打开设备管理
- THEN APP 显示设备名称、平台、最近活动时间和当前设备标记
- AND API 只返回认证用户自己的设备

##### Scenario: 撤销其他设备

- GIVEN 用户选择另一个有效设备会话
- WHEN 确认撤销
- THEN 该设备的 access 和 refresh 凭据失效
- AND 当前设备会话保持有效

#### Requirement: 本地账号数据隔离

The system SHALL keep cached training events and sync state in separate installation profiles for different remote users.

##### Scenario: 同设备切换账号

- GIVEN 账号 A 已在本机同步私有训练历史并退出
- WHEN 账号 B 登录同一安装
- THEN 账号 B 不读取、归约或上传账号 A 的缓存
- AND 账号 A 再次登录时可恢复自己的隔离数据空间

### Capability: local-first-event-sync

#### Requirement: 本地先写与可恢复 Outbox

The system SHALL persist a completed TrainingEvent locally before network work and durably record it for synchronization.

##### Scenario: 离线完成训练

- GIVEN 用户已登录但网络不可用
- WHEN 完成一个决策
- THEN TrainingEvent 先写入本地 append-only 日志
- AND 事件进入持久 Outbox
- AND 用户立即看到反馈、今日和复盘更新

##### Scenario: 追加与入队之间中断

- GIVEN TrainingEvent 已写入但 APP 在 Outbox 入队前终止
- WHEN APP 下次启动执行对账
- THEN 未被远端确认的本地事件重新进入 Outbox
- AND 事件不会永久漏传

#### Requirement: 幂等批量上传

The system SHALL upload event batches with an idempotency key and deduplicate by authenticated user and event ID.

##### Scenario: 上传响应丢失后重试

- GIVEN 服务端已经提交一个事件批次但客户端未收到响应
- WHEN 客户端使用相同幂等键重试
- THEN 服务端返回与首次提交一致的确认
- AND 每个 event ID 在该用户下只存在一份

##### Scenario: 幂等键请求冲突

- GIVEN 同一认证用户已经使用某个幂等键提交一个请求正文
- WHEN 客户端使用相同幂等键提交不同 request hash 的事件批次
- THEN 服务端返回 typed `idempotencyConflict`
- AND 不返回旧批次的成功确认
- AND 不写入新批次的任何事件

##### Scenario: 事件归属由会话决定

- GIVEN 请求正文包含与认证用户不同的 localUserID
- WHEN API 保存事件
- THEN 远端 user ownership 只由认证会话决定
- AND 原始 localUserID 作为不可变事件字段保留而不用于授权

#### Requirement: 单调 Checkpoint 拉取

The system SHALL return events after a per-user monotonic server sequence checkpoint.

##### Scenario: 跨设备增量同步

- GIVEN 设备 A 与设备 B 属于同一远端用户且各自产生事件
- WHEN 两台设备依次上传并按 checkpoint 拉取
- THEN 两台设备最终拥有相同的事件 ID 集合
- AND 每个事件只出现一次

##### Scenario: 设备时钟回拨

- GIVEN 晚上传事件的 occurredAt 早于当前 checkpoint 前的事件
- WHEN 客户端按 server sequence 拉取
- THEN 该事件仍出现在 checkpoint 之后
- AND 同步不依赖客户端时间排序

##### Scenario: 多页 checkpoint 边界

- GIVEN checkpoint 之后的事件数量超过单页上限
- WHEN 客户端连续分页拉取
- THEN 每个非空响应的 next checkpoint 等于该页最后一条已返回事件的 server sequence
- AND 空页保持请求 checkpoint 不变
- AND hasMore 只在仍有后续已提交事件时为 true
- AND 连续拉取不会跳过或重复任何 event ID

#### Requirement: 远端事件本地合并

The system SHALL append downloaded TrainingEvents through the existing idempotent TrainingEventStore without rewriting historical content.

##### Scenario: 拉取重复事件

- GIVEN 本地已经存在服务端返回的 event ID
- WHEN 同步器合并下载批次
- THEN 本地日志不重复
- AND strategy pack ID、content version、grade 和原设备 ID 保持原值

#### Requirement: 同步状态与自动恢复

The system SHALL expose offline, pending, syncing, synced, and failed states without blocking deterministic training.

##### Scenario: 网络恢复

- GIVEN Outbox 有待上传事件且上次同步因网络错误失败
- WHEN 网络恢复或用户手动重试
- THEN 同步从持久状态继续
- AND 已确认事件不会重复计数

##### Scenario: 会话失效

- GIVEN 服务端撤销当前设备会话
- WHEN 下一次同步收到认证失败
- THEN APP 清除 Keychain 会话并锁定该账号的同步
- AND 本地历史保持隔离且不被删除

### Capability: mysql-sync-service

#### Requirement: Go 与 MySQL 兼容基线

The system SHALL provide a Go service whose migrations and queries are compatible with MySQL 8.4 or later using InnoDB.

##### Scenario: 空数据库迁移

- GIVEN 一个空的 MySQL 8.4+ schema
- WHEN 服务启动或运行迁移命令
- THEN schema migrations 按版本一次性应用
- AND 用户、身份、密码、挑战、设备、会话、事件、幂等和游标表可用

##### Scenario: 重复迁移

- GIVEN 所有迁移已经成功应用
- WHEN 再次运行迁移
- THEN 数据结构保持不变
- AND 不删除或重写用户数据

#### Requirement: 事务与唯一约束

The system SHALL use InnoDB transactions and database constraints to preserve identity, session, and event idempotency.

##### Scenario: 重复事件并发写入

- GIVEN 两个并发请求为同一认证用户上传相同 event ID
- WHEN 两个事务竞争提交
- THEN 只有一条 training_events 记录存在
- AND 两个请求得到一致的已确认语义

##### Scenario: 同一用户并发顺序分配

- GIVEN 同一认证用户有两个包含不同新事件的并发上传事务
- WHEN 服务端分配同步 sequence
- THEN 事务通过该用户的 sequence row 串行分配严格递增值
- AND 较大的 sequence 不会先于较小的 sequence 提交
- AND checkpoint 拉取不会越过尚未提交的事件

##### Scenario: 账号删除事务

- GIVEN 用户通过近期重新认证请求删除账号
- WHEN 服务端执行删除
- THEN 用户拥有的身份、凭据、设备、会话、事件和幂等记录被完整删除
- AND 不留下可继续认证的孤立记录

#### Requirement: API 授权与输入验证

The system SHALL derive user scope from bearer credentials and validate body size, schema version, UUIDs, batch size, and cursor bounds.

##### Scenario: 越权 user ID

- GIVEN 认证用户在请求参数或正文中提交另一个 user ID
- WHEN API 处理请求
- THEN 数据查询和写入仍限定在认证用户范围
- AND 不返回其他用户是否存在

##### Scenario: 超限批次

- GIVEN 同步请求超过允许的事件数量或正文大小
- WHEN API 校验请求
- THEN 返回 typed limit error
- AND MySQL 不写入部分批次

#### Requirement: 认证速率限制

The system SHALL rate-limit registration, login, verification, password reset, and refresh attempts by normalized account and network signals.

##### Scenario: 连续失败登录

- GIVEN 同一账号或网络来源短时间内反复认证失败
- WHEN 请求超过限额
- THEN API 返回可重试时间但不泄露账号状态
- AND 正确密码不会绕过当前节流窗口

#### Requirement: 可替换邮件投递

The system SHALL deliver verification and reset challenges through an injected mail interface with test, development, and SMTP implementations.

##### Scenario: 测试投递

- GIVEN 服务运行在自动化测试环境
- WHEN 创建邮箱验证或重置挑战
- THEN 内存投递器可供测试读取一次性凭据
- AND 凭据不写入普通服务日志

##### Scenario: SMTP 配置缺失

- GIVEN 非开发环境没有完整 SMTP 配置
- WHEN 服务启动
- THEN 启动失败并返回 typed configuration error
- AND 不静默退回日志打印邮件正文

### Capability: account-data-rights

#### Requirement: 近期重新认证

The system SHALL require a recent password or Apple reauthentication proof for export, account deletion, and sensitive identity linking.

##### Scenario: 过期认证

- GIVEN 当前会话有效但最近认证时间超过敏感操作窗口
- WHEN 用户请求导出或删除
- THEN API 拒绝执行并要求重新认证
- AND 不返回任何导出数据或删除部分记录

#### Requirement: 结构化数据导出

The system SHALL create a versioned export bundle containing the authenticated user's remote account data and the active profile's local corruption backups.

##### Scenario: 导出成功

- GIVEN 用户完成近期重新认证
- WHEN 请求数据导出
- THEN APP 生成带 schema version、生成时间和文件清单的导出 bundle
- AND 远端 JSON 只包含该认证用户的账号元数据、设备会话和不可变训练事件
- AND 当前 profile 的损坏历史备份以独立原始附件纳入 bundle 而不自动上传到服务端
- AND 导出不包含密码哈希、令牌哈希或邮箱挑战凭据

#### Requirement: 账号与本机数据删除

The system SHALL delete remote account data after explicit confirmation and separately ask whether to remove the current device's local profile.

##### Scenario: 仅删除云端账号

- GIVEN 用户完成近期重新认证并确认删除远端账号
- WHEN 服务端完成事务删除
- THEN 所有远端会话立即失效
- AND APP 清除 Keychain 凭据
- AND 用户选择保留本机历史时，该 profile 清除远端同步状态并转为匿名本机 profile

##### Scenario: 同时删除本机历史

- GIVEN 云端账号已删除且用户进一步确认删除本机数据
- WHEN APP 执行本地删除
- THEN 该账号 profile 的事件、Outbox、checkpoint 和损坏历史备份均被删除
- AND 其他账号 profile 不受影响

#### Requirement: 安全退出

The system SHALL revoke the current refresh session and clear local credentials without deleting training history.

##### Scenario: 离线退出

- GIVEN 用户离线请求退出
- WHEN APP 无法立即通知服务端
- THEN Keychain 凭据立即清除
- AND refresh token 被移动到 Keychain 中不可用于登录恢复的待撤销项
- AND 该账号训练 profile 被锁定而不是暴露给匿名或其他账号

### Capability: m1b-verification

#### Requirement: 一键 M1B 验证

The system SHALL provide one command that verifies M1A regression, Go tests, MySQL migrations, API contracts, iOS models, and cross-device synchronization.

##### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift、XcodeGen、Go 和 MySQL
- WHEN 执行 `bash scripts/verify-m1b.sh`
- THEN M1A 包、App、iPhone/iPad UI 与 Release 门禁通过
- AND Go 单元和 HTTP 合约测试通过
- AND 隔离 MySQL 迁移及集成测试通过
- AND 两设备离线事件最终双向合并且无重复

#### Requirement: 隔离测试环境

The system SHALL run MySQL integration tests in a temporary isolated data directory without relying on or mutating a developer's existing schema.

##### Scenario: 本机已有 MySQL

- GIVEN 本机可能存在其他 MySQL 数据目录或服务
- WHEN M1B 验证启动测试数据库
- THEN 使用独立端口、临时目录和测试凭据
- AND 验证退出后不改动已有数据库

#### Requirement: 密钥与开发能力隔离

The system SHALL keep production secrets, development mailbox access, test reset hooks, and Apple test credentials out of Release resources and version control.

##### Scenario: Release 检查

- GIVEN APP 和 Go 服务使用 Release/production 配置构建
- WHEN 检查产物和版本化文件
- THEN 不包含测试令牌、SMTP 密码、开发邮箱内容或认证 bypass
- AND 缺少必要生产配置时显式失败

### Capability: local-learning-profile

#### Requirement: 不可变本地训练事件

The system SHALL persist each completed decision as an immutable, append-only event that includes event ID, local user ID, device ID, occurrence time, scenario ID, strategy pack ID, content version, ability dimension, submission, and grade.

##### Scenario: 首次追加

- GIVEN 本地事件存储为空
- WHEN APP 追加一个 TrainingEvent
- THEN 事件可按时间顺序读取
- AND 所有同步所需标识与评分字段均保留

##### Scenario: 重复事件

- GIVEN 存储中已经存在相同 event ID
- WHEN APP 再次追加该事件
- THEN 存储内容不重复
- AND 读取结果仍只有一条该事件

##### Scenario: 损坏事件文件

- GIVEN JSON Lines 文件的某一行无法解码
- WHEN store 初始化或读取
- THEN 返回包含行号的 typed corruption error
- AND 日志不输出完整事件正文

#### Requirement: 能力画像归约

The system SHALL derive each ability dimension from its immutable training events.

##### Scenario: 高信心错误

- GIVEN very-sure 决策被评为 improvable 或 blunder
- WHEN reducer 生成能力画像
- THEN 对应维度 high-confidence-error-count 增加
- AND 其他能力维度不受影响

#### Requirement: 今日训练优先级

The system SHALL rank training catalog items using weakness, high-confidence errors, and days since practice.

##### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

#### Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the active profile's local event store after a completed or synchronized decision.

##### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 今日主训练可以指向该弱项

#### Requirement: 跨设备历史确定性归约

The system SHALL derive the active user's ability profile from the deduplicated union of locally created and synchronized TrainingEvents.

##### Scenario: 远端事件进入画像

- GIVEN 同一账号的另一设备完成训练并同步
- WHEN 当前设备拉取并合并该事件
- THEN Today 与 Review 的样本和能力画像包含该事件
- AND 相同 event ID 的重复拉取不改变结果

## Impact

- **Code:** 新增 `Server/` Go 模块、MySQL migrations、认证与同步 API；新增 `PokerCoach/Infrastructure/{Auth,Network,Sync,Profiles}/` 和账号 UI；扩展工程配置与验证脚本。
- **Interfaces:** 新增 `/v1/auth/*`、`/v1/sync/events`、`/v1/account/*`、`/v1/sessions/*` HTTP API；新增账号中心、同步状态和设备管理界面。
- **Dependencies:** Go 服务新增锁定版本的 MySQL driver 与 Argon2id 支持；iOS 不新增第三方运行时依赖；最低兼容 MySQL 8.4。
- **Knowledge:** 将架构、路线、测试与安全文档中的 PostgreSQL 真值统一更新为 MySQL/InnoDB。

## Risks

- 登录后改写匿名事件导致历史或幂等键失效 → 远端建立 ownership 映射，不修改事件 ID、localUserID 或正文。
- 本地事件已保存但 Outbox 尚未入队时崩溃 → 每次启动用本地日志与远端确认状态对账恢复。
- 刷新令牌被窃取后重放 → 只存 token hash、单次轮换并撤销整个会话族。
- 相同邮箱的 Apple 身份被错误自动合并 → 禁止仅按邮箱合并，必须先完成现有账号的近期认证。
- 同设备切换账号泄露本地历史 → 每个远端用户使用独立加锁 profile，匿名 profile 只能被认领一次。
- MySQL 并发写入形成重复事件 → InnoDB 事务加 `(user_id,event_id)` 唯一约束并把重复键映射为幂等成功。
- 开发邮件或测试凭据进入生产 → 环境专属依赖组合、Release 检查和缺少生产配置时 fail closed。
- M1B 扩张到课程、模拟或部署运营 → Non-Goals 明确切分到 M1C、M2 和 M4。

## Non-Goals

- 初始诊断、能力树、已审核现金局课程和间隔复练内容；属于 M1C。
- 完整发牌、虚拟对手、现金局 Session 和个人牌谱实验室；属于 M2。
- Ante、短码、Push/Fold、Rejam、赛事路线和 ICM；属于 M3。
- 订阅、权益、产品分析、生产内容运营和 App Store 上架；属于 M4。
- 自动把相同邮箱的 Apple 身份与密码账号合并。
- 多人协作、社交资料、公开排行榜或共享牌谱。
- 擅自部署生产服务器、购买域名或配置真实 SMTP/Apple 密钥；本阶段交付可部署代码和本地完整验证。

## Acceptance Criteria

1. 未登录或离线时 M1A 训练、反馈、历史和复盘继续正常运行。
2. 邮箱密码注册、验证、登录、重置和通用失败语义通过服务与 iOS 测试。
3. 密码采用 Argon2id PHC 存储，执行 15–128 字符、弱密码列表、无组合规则的策略。
4. Apple credential 验证、nonce 和显式身份关联有正反向测试。
5. access/refresh token 只存 Keychain；服务端只存 token hash，并覆盖轮换与重放撤销。
6. 设备会话可查看、可撤销，API 用户范围只来自认证会话。
7. 匿名本地身份与历史在首次登录后被绑定但不改写。
8. 不同账号的本地事件、Outbox、checkpoint 和损坏备份互相隔离。
9. 离线训练本地立即生效，网络恢复后 Outbox 自动继续。
10. 重复上传、响应丢失重试和并发写入不会形成重复远端事件。
11. checkpoint 使用服务端单调 sequence，设备时间回拨不会漏同步。
12. 两个设备离线产生不同事件后最终拥有相同且去重的事件集合。
13. MySQL 8.4+ 空库迁移、重复迁移、事务约束和账号删除通过集成测试。
14. 数据导出不含凭据；账号删除和本机数据删除均要求明确确认与近期认证。
15. `bash scripts/verify-m1b.sh` 从干净检出完成 M1A 回归、Go、隔离 MySQL、iOS 和跨设备验证。
16. 领域包不依赖 HTTP、认证或 MySQL DTO，M1A 的稳定契约语义保持不变。
