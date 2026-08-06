# 编码规范

## Swift 与文件命名

- 类型和文件使用 `UpperCamelCase`。
- 变量、函数和属性使用 `lowerCamelCase`。
- 一个文件聚焦一个主要职责；测试夹具位于测试目标 `Support/`。
- Swift 采用严格并发检查，项目代码中的并发警告视为错误。
- 可跨任务使用的领域类型必须显式遵守 `Sendable`。

## 精确数据

- 筹码和底池使用整数 centi-BB。
- EV 使用整数 milli-BB。
- 频率使用总和为 10,000 的 basis points。
- 浮点数只用于最终展示，不作为领域存储或比较真值。
- 金额、频率和 EV 的 JSON 字段名必须带单位。

## 代码组织

- 领域模块按稳定职责拆分，不按“所有 Models/Views/Utils”横向堆积。
- Feature 目录可包含该功能专属的 View、ViewModel 和 Presentation。
- App 通过依赖组合注入协议实现，不允许在 View 内直接创建文件或网络客户端。
- 测试专用 fixture、reset hook 和开发数据不得进入 Release。

## 错误处理

- 使用可枚举、可测试的 typed error。
- 用户可恢复的错误必须提供中文说明和明确重试动作。
- 牌谱解析冲突不得静默猜测。
- 内容损坏时回退到上一个已验证版本，不使用部分数据继续评分。
- 日志只记录诊断元数据，不记录完整牌谱、凭据和密钥。

## Git 约定

- 每个 Harness task 形成可独立评审的小提交。
- 提交信息使用英文 Conventional Commit 风格，如 `feat:`, `test:`, `docs:`, `fix:`。
- 不提交 `.superpowers/` 工作区、派生数据、密钥或未脱敏牌谱。

