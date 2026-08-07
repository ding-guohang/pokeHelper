# Capability: m1a-release-safety

## Requirement: 开发策略数据隔离

The system SHALL include the deterministic development strategy pack in Debug only and exclude it from Release resources.

### Scenario: Debug 训练

- GIVEN APP 使用 Debug 配置启动
- WHEN 开发策略场景被加载
- THEN 用户可以完成纵向训练流程
- AND 所有相关页面显示“开发演示数据”

### Scenario: Release 构建

- GIVEN APP 使用 Release 配置构建
- WHEN 检查生成的 APP bundle
- THEN `DevStrategyPack.json` 不存在
- AND 缺少已审核内容时显示“未安装已审核策略内容”

## Requirement: 一键验证

The system SHALL provide one command that verifies packages, app models, iPhone flow, iPad layout, and Release fixture exclusion.

### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift 和 XcodeGen
- WHEN 执行 `bash scripts/verify-m1a.sh`
- THEN PokerCore、StrategyContent 和 TrainingDomain 测试通过
- AND APP 单元测试通过
- AND iPhone 与 iPad UI 测试通过
