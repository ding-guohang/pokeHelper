# Capability: secure-device-sessions

## Requirement: Keychain 凭据存储

The system SHALL store access and refresh credentials only in Keychain-backed secure storage.

### Scenario: 会话持久化

- GIVEN 用户成功登录
- WHEN APP 保存远端会话
- THEN access token 和 refresh token 写入 Keychain
- AND UserDefaults、本地 JSON、诊断日志和崩溃信息不包含令牌

### Scenario: Keychain 不可用

- GIVEN Keychain 读取或写入失败
- WHEN APP 尝试建立或恢复会话
- THEN APP 返回中文可恢复错误
- AND 不把令牌降级保存到非安全存储

## Requirement: 不透明令牌与刷新轮换

The system SHALL issue random opaque access and refresh tokens, persist only their hashes, and rotate refresh tokens.

### Scenario: 正常刷新

- GIVEN access token 已过期且 refresh token 有效
- WHEN 客户端请求刷新
- THEN 服务端签发新的 access token 和 refresh token
- AND 旧 refresh token 立即失效

### Scenario: 刷新令牌重放

- GIVEN 已轮换的旧 refresh token 再次被使用
- WHEN 服务端检测到重放
- THEN 对应会话族全部撤销
- AND 客户端回到需要登录状态而不删除本地训练历史

## Requirement: 设备会话管理

The system SHALL let an authenticated user inspect and revoke device sessions without trusting a client-supplied user ID.

### Scenario: 查看设备

- GIVEN 用户拥有多个有效设备会话
- WHEN 打开设备管理
- THEN APP 显示设备名称、平台、最近活动时间和当前设备标记
- AND API 只返回认证用户自己的设备

### Scenario: 撤销其他设备

- GIVEN 用户选择另一个有效设备会话
- WHEN 确认撤销
- THEN 该设备的 access 和 refresh 凭据失效
- AND 当前设备会话保持有效

## Requirement: 本地账号数据隔离

The system SHALL keep cached training events and sync state in separate installation profiles for different remote users.

### Scenario: 同设备切换账号

- GIVEN 账号 A 已在本机同步私有训练历史并退出
- WHEN 账号 B 登录同一安装
- THEN 账号 B 不读取、归约或上传账号 A 的缓存
- AND 账号 A 再次登录时可恢复自己的隔离数据空间
