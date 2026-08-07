# 审需报告：poker-coach-m1a-cash-coach-20260806-01

## 检查结果

### 一致性检查

- [x] 每个 Capability 至少有一个 Requirement
- [x] 每个 Requirement 至少有一个 Scenario
- [x] 每个 Scenario 都包含 GIVEN/WHEN/THEN
- [x] Capabilities 之间没有冲突或重复
- [x] 当前没有 Modified/Removed Capabilities
- [x] Impact 中的模块和依赖方向与架构知识库一致

### 规格完整性

| Capability | Requirements | Scenarios | 状态 |
|---|---:|---:|---|
| adaptive-native-shell | 2 | 3 | OK |
| cash-decision-domain | 4 | 7 | OK |
| versioned-strategy-content | 3 | 6 | OK |
| explainable-decision-training | 4 | 9 | OK |
| local-learning-profile | 4 | 6 | OK |
| m1a-release-safety | 2 | 3 | OK |

### 可测试性

- GIVEN 均能由固定设备、场景、事件、策略包或构建配置设置。
- WHEN 均为单一可触发动作，如加载、校验、提交、评分、刷新或构建。
- THEN 均包含可由 Swift Testing、XCTest、XCUITest、文件检查或构建退出码验证的结果。

### 架构与规范符合性

- 依赖方向保持 `SwiftUI → TrainingDomain → StrategyContent → PokerCore`。
- 金额、EV 和频率分别使用 centi-BB、milli-BB 和 basis points。
- 策略内容具有版本、来源、审核状态和 Release 隔离。
- DecisionScorer 不读取 runout 或输赢。
- TrainingEvent 为后续 M1B 保留幂等同步所需字段。

## 问题列表

审查中发现一处 GIVEN 格式缺少空格，已直接修正。没有需要用户澄清的规格问题。

## 结论

- [x] 通过 — 可进入 plan 阶段
- [ ] 有条件通过
- [ ] 不通过

