# 模块与基础组件

## PokerCore

- **目标路径：** `Packages/PokerCore/`
- **用途：** 提供确定性、可测试的扑克值类型和规则。
- **首批接口：** `Card`、`BBAmount`、`EVAmount`、`DecisionAction`、`BettingDecisionContext`。
- **限制：** 筹码使用 centi-BB 整数，EV 使用 milli-BB 整数；不得用浮点数保存领域真值。

## StrategyContent

- **目标路径：** `Packages/StrategyContent/`
- **用途：** 加载不可变策略包，保存场景、行动频率、EV、范围和求解假设。
- **首批接口：** `StrategyPack`、`DecisionScenario`、`StrategyPackLoader`、`StrategyPackValidator`、`StrategyPackProviding`。
- **限制：** 每个节点频率总和为 10,000 basis points；Release 只能使用已审核内容。

## TrainingDomain

- **目标路径：** `Packages/TrainingDomain/`
- **用途：** 完成确定性评分、训练事件记录、能力画像和每日训练规划。
- **首批接口：** `DecisionScorer`、`TrainingEvent`、`TrainingEventStore`、`PlayerModelReducer`、`TrainingPlanner`。
- **限制：** 决策评分不得读取后续发牌或本次输赢。

## SwiftUI Feature

- **目标路径：** `PokerCoach/Features/`
- **用途：** 按 Today、Learn、Train、Feedback、Review 组织用户体验。
- **限制：** iPhone 使用紧凑单列流程，iPad 使用多栏专业分析；二者共享领域逻辑。

## Local Event Store

- **首个实现：** M1A 的 JSON Lines 追加事件存储。
- **长期接口：** `TrainingEventStore`。
- **演进方向：** M1B 在不改变事件语义的前提下增加 Outbox 和远端同步。
- **限制：** 同一事件 ID 重复写入不得形成重复历史。

## Independent Backend

- **阶段：** M1B。
- **用途：** Apple/邮箱登录、设备会话、幂等事件同步、能力重算、内容分发、导出和删除。
- **边界：** Go API 与 PostgreSQL 属于基础设施，不渗透到扑克领域模块。

