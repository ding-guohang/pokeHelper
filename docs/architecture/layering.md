# 分层规则

## 层次结构

```text
SwiftUI UI
  ↓ 绑定
Feature ViewModel / Presentation
  ↓ 调用
TrainingDomain
  ↓ 读取
StrategyContent → PokerCore

Infrastructure
  ├─ Local TrainingEventStore
  ├─ Remote Synchronizer
  └─ Auth / Content / Hand Analysis API Clients
```

## 调用规则

1. SwiftUI View 只负责布局、交互和无业务含义的显示状态。
2. ViewModel 可以组合领域协议，但不得自行计算 EV、合法行动或能力分数。
3. TrainingDomain 可以读取 PokerCore 与 StrategyContent，不得依赖 SwiftUI、HTTP 或数据库实现。
4. StrategyContent 使用 PokerCore 的牌、金额和行动类型，负责解码、校验与版本追溯。
5. PokerCore 不依赖其他项目模块，不含教学文案、网络、存储或用户状态。
6. 本地与远端存储通过协议接入；远端 DTO 在基础设施层转换为领域类型。
7. 生成式 AI 只消费结构化分析，不得作为策略真值或规则引擎。

## 文件职责

- 一个文件聚焦一个稳定职责。
- 同一功能域内的 View、ViewModel 和 Presentation 放在同一 Feature 目录。
- 跨功能复用且无业务状态的 SwiftUI 组件放入 `PokerCoach/Shared/`。
- 测试支持代码位于对应测试目标的 `Support/`，不得进入生产目标。

## 禁止的依赖

- `PokerCore → StrategyContent`
- `PokerCore → TrainingDomain`
- 领域包 → SwiftUI
- 领域包 → 具体 HTTP 客户端
- View → MySQL、文件系统或同步 DTO
- 生成式文本 → DecisionScorer 输入

## 违反案例

项目尚无源代码。首次发现违反分层的实现时，应在本节记录文件、原因和修复结果。

