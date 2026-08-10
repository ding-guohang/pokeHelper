# Capability: mysql-sync-service

## Requirement: Go 与 MySQL 兼容基线

The system SHALL provide a Go service whose migrations and queries are compatible with MySQL 8.4 or later using InnoDB.

### Scenario: 空数据库迁移

- GIVEN 一个空的 MySQL 8.4+ schema
- WHEN 服务启动或运行迁移命令
- THEN schema migrations 按版本一次性应用
- AND 用户、身份、密码、挑战、设备、会话、事件、幂等和游标表可用

### Scenario: 重复迁移

- GIVEN 所有迁移已经成功应用
- WHEN 再次运行迁移
- THEN 数据结构保持不变
- AND 不删除或重写用户数据

## Requirement: 事务与唯一约束

The system SHALL use InnoDB transactions and database constraints to preserve identity, session, and event idempotency.

### Scenario: 重复事件并发写入

- GIVEN 两个并发请求为同一认证用户上传相同 event ID
- WHEN 两个事务竞争提交
- THEN 只有一条 training_events 记录存在
- AND 两个请求得到一致的已确认语义

### Scenario: 同一用户并发顺序分配

- GIVEN 同一认证用户有两个包含不同新事件的并发上传事务
- WHEN 服务端分配同步 sequence
- THEN 事务通过该用户的 sequence row 串行分配严格递增值
- AND 较大的 sequence 不会先于较小的 sequence 提交
- AND checkpoint 拉取不会越过尚未提交的事件

### Scenario: 账号删除事务

- GIVEN 用户通过近期重新认证请求删除账号
- WHEN 服务端执行删除
- THEN 用户拥有的身份、凭据、设备、会话、事件和幂等记录被完整删除
- AND 不留下可继续认证的孤立记录

## Requirement: API 授权与输入验证

The system SHALL derive user scope from bearer credentials and validate body size, schema version, UUIDs, batch size, and cursor bounds.

### Scenario: 越权 user ID

- GIVEN 认证用户在请求参数或正文中提交另一个 user ID
- WHEN API 处理请求
- THEN 数据查询和写入仍限定在认证用户范围
- AND 不返回其他用户是否存在

### Scenario: 超限批次

- GIVEN 同步请求超过允许的事件数量或正文大小
- WHEN API 校验请求
- THEN 返回 typed limit error
- AND MySQL 不写入部分批次

## Requirement: 认证速率限制

The system SHALL rate-limit registration, login, verification, password reset, and refresh attempts by normalized account and network signals.

### Scenario: 连续失败登录

- GIVEN 同一账号或网络来源短时间内反复认证失败
- WHEN 请求超过限额
- THEN API 返回可重试时间但不泄露账号状态
- AND 正确密码不会绕过当前节流窗口

## Requirement: 可替换邮件投递

The system SHALL deliver verification and reset challenges through an injected mail interface with test, development, and SMTP implementations.

### Scenario: 测试投递

- GIVEN 服务运行在自动化测试环境
- WHEN 创建邮箱验证或重置挑战
- THEN 内存投递器可供测试读取一次性凭据
- AND 凭据不写入普通服务日志

### Scenario: SMTP 配置缺失

- GIVEN 非开发环境没有完整 SMTP 配置
- WHEN 服务启动
- THEN 启动失败并返回 typed configuration error
- AND 不静默退回日志打印邮件正文
