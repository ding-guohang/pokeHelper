# Capability: m1b-verification

## Requirement: 一键 M1B 验证

The system SHALL provide one command that verifies M1A regression, Go tests, MySQL migrations, API contracts, iOS models, and cross-device synchronization.

### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift、XcodeGen、Go 和 MySQL
- WHEN 执行 `bash scripts/verify-m1b.sh`
- THEN M1A 包、App、iPhone/iPad UI 与 Release 门禁通过
- AND Go 单元和 HTTP 合约测试通过
- AND 隔离 MySQL 迁移及集成测试通过
- AND 两设备离线事件最终双向合并且无重复

## Requirement: 隔离测试环境

The system SHALL run MySQL integration tests in a temporary isolated data directory without relying on or mutating a developer's existing schema.

### Scenario: 本机已有 MySQL

- GIVEN 本机可能存在其他 MySQL 数据目录或服务
- WHEN M1B 验证启动测试数据库
- THEN 使用独立端口、临时目录和测试凭据
- AND 验证退出后不改动已有数据库

## Requirement: 密钥与开发能力隔离

The system SHALL keep production secrets, development mailbox access, test reset hooks, and Apple test credentials out of Release resources and version control.

### Scenario: Release 检查

- GIVEN APP 和 Go 服务使用 Release/production 配置构建
- WHEN 检查产物和版本化文件
- THEN 不包含测试令牌、SMTP 密码、开发邮箱内容或认证 bypass
- AND 缺少必要生产配置时显式失败
