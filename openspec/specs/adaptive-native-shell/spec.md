# Capability: adaptive-native-shell

## Requirement: 四个核心入口

The system SHALL provide the primary destinations 今日、学习、训练、复盘 in Simplified Chinese.

### Scenario: iPhone 紧凑导航

- GIVEN 用户在 iPhone 或紧凑宽度窗口启动 APP
- WHEN 根界面完成加载
- THEN 系统显示包含今日、学习、训练、复盘的底部导航
- AND 训练入口使用黑桃标识

### Scenario: iPad 多栏导航

- GIVEN 用户在 iPad 常规宽度窗口启动 APP
- WHEN 根界面完成加载
- THEN 系统使用侧边栏呈现四个核心入口
- AND 选择入口不会创建第二套领域状态

## Requirement: 原生平台支持

The system SHALL build for iOS 18.0 and iPadOS 18.0 with Swift strict concurrency enabled.

### Scenario: 两种设备构建

- GIVEN 已生成 Xcode 工程
- WHEN 分别执行通用 iOS Simulator 与通用 iOS 构建
- THEN 两个构建均成功
- AND 项目自有代码没有严格并发警告
