# Capability: local-first-event-sync

## Requirement: 本地先写与可恢复 Outbox

The system SHALL persist a completed TrainingEvent locally before network work and durably record it for synchronization.

### Scenario: 离线完成训练

- GIVEN 用户已登录但网络不可用
- WHEN 完成一个决策
- THEN TrainingEvent 先写入本地 append-only 日志
- AND 事件进入持久 Outbox
- AND 用户立即看到反馈、今日和复盘更新

### Scenario: 追加与入队之间中断

- GIVEN TrainingEvent 已写入但 APP 在 Outbox 入队前终止
- WHEN APP 下次启动执行对账
- THEN 未被远端确认的本地事件重新进入 Outbox
- AND 事件不会永久漏传

## Requirement: 幂等批量上传

The system SHALL upload event batches with an idempotency key and deduplicate by authenticated user and event ID.

### Scenario: 上传响应丢失后重试

- GIVEN 服务端已经提交一个事件批次但客户端未收到响应
- WHEN 客户端使用相同幂等键重试
- THEN 服务端返回与首次提交一致的确认
- AND 每个 event ID 在该用户下只存在一份

### Scenario: 幂等键请求冲突

- GIVEN 同一认证用户已经使用某个幂等键提交一个请求正文
- WHEN 客户端使用相同幂等键提交不同 request hash 的事件批次
- THEN 服务端返回 typed `idempotencyConflict`
- AND 不返回旧批次的成功确认
- AND 不写入新批次的任何事件

### Scenario: 事件归属由会话决定

- GIVEN 请求正文包含与认证用户不同的 localUserID
- WHEN API 保存事件
- THEN 远端 user ownership 只由认证会话决定
- AND 原始 localUserID 作为不可变事件字段保留而不用于授权

## Requirement: 单调 Checkpoint 拉取

The system SHALL return events after a per-user monotonic server sequence checkpoint.

### Scenario: 跨设备增量同步

- GIVEN 设备 A 与设备 B 属于同一远端用户且各自产生事件
- WHEN 两台设备依次上传并按 checkpoint 拉取
- THEN 两台设备最终拥有相同的事件 ID 集合
- AND 每个事件只出现一次

### Scenario: 设备时钟回拨

- GIVEN 晚上传事件的 occurredAt 早于当前 checkpoint 前的事件
- WHEN 客户端按 server sequence 拉取
- THEN 该事件仍出现在 checkpoint 之后
- AND 同步不依赖客户端时间排序

### Scenario: 多页 checkpoint 边界

- GIVEN checkpoint 之后的事件数量超过单页上限
- WHEN 客户端连续分页拉取
- THEN 每个非空响应的 next checkpoint 等于该页最后一条已返回事件的 server sequence
- AND 空页保持请求 checkpoint 不变
- AND hasMore 只在仍有后续已提交事件时为 true
- AND 连续拉取不会跳过或重复任何 event ID

## Requirement: 远端事件本地合并

The system SHALL append downloaded TrainingEvents through the existing idempotent TrainingEventStore without rewriting historical content.

### Scenario: 拉取重复事件

- GIVEN 本地已经存在服务端返回的 event ID
- WHEN 同步器合并下载批次
- THEN 本地日志不重复
- AND strategy pack ID、content version、grade 和原设备 ID 保持原值

## Requirement: 同步状态与自动恢复

The system SHALL expose offline, pending, syncing, synced, and failed states without blocking deterministic training.

### Scenario: 网络恢复

- GIVEN Outbox 有待上传事件且上次同步因网络错误失败
- WHEN 网络恢复或用户手动重试
- THEN 同步从持久状态继续
- AND 已确认事件不会重复计数

### Scenario: 会话失效

- GIVEN 服务端撤销当前设备会话
- WHEN 下一次同步收到认证失败
- THEN APP 清除 Keychain 会话并锁定该账号的同步
- AND 本地历史保持隔离且不被删除
