# Capability: account-data-rights

## Requirement: 近期重新认证

The system SHALL require a recent password or Apple reauthentication proof for export, account deletion, and sensitive identity linking.

### Scenario: 过期认证

- GIVEN 当前会话有效但最近认证时间超过敏感操作窗口
- WHEN 用户请求导出或删除
- THEN API 拒绝执行并要求重新认证
- AND 不返回任何导出数据或删除部分记录

## Requirement: 结构化数据导出

The system SHALL create a versioned export bundle containing the authenticated user's remote account data and the active profile's local corruption backups.

### Scenario: 导出成功

- GIVEN 用户完成近期重新认证
- WHEN 请求数据导出
- THEN APP 生成带 schema version、生成时间和文件清单的导出 bundle
- AND 远端 JSON 只包含该认证用户的账号元数据、设备会话和不可变训练事件
- AND 当前 profile 的损坏历史备份以独立原始附件纳入 bundle 而不自动上传到服务端
- AND 导出不包含密码哈希、令牌哈希或邮箱挑战凭据

## Requirement: 账号与本机数据删除

The system SHALL delete remote account data after explicit confirmation and separately ask whether to remove the current device's local profile.

### Scenario: 仅删除云端账号

- GIVEN 用户完成近期重新认证并确认删除远端账号
- WHEN 服务端完成事务删除
- THEN 所有远端会话立即失效
- AND APP 清除 Keychain 凭据
- AND 用户选择保留本机历史时，该 profile 清除远端同步状态并转为匿名本机 profile

### Scenario: 同时删除本机历史

- GIVEN 云端账号已删除且用户进一步确认删除本机数据
- WHEN APP 执行本地删除
- THEN 该账号 profile 的事件、Outbox、checkpoint 和损坏历史备份均被删除
- AND 其他账号 profile 不受影响

## Requirement: 安全退出

The system SHALL revoke the current refresh session and clear local credentials without deleting training history.

### Scenario: 离线退出

- GIVEN 用户离线请求退出
- WHEN APP 无法立即通知服务端
- THEN Keychain 凭据立即清除
- AND refresh token 被移动到 Keychain 中不可用于登录恢复的待撤销项
- AND 该账号训练 profile 被锁定而不是暴露给匿名或其他账号
