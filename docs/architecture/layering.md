# 分层规则

## 层次结构

```text
SwiftUI UI
  ↓ 绑定
Feature ViewModel / Presentation
  ↓ 调用
TrainingDomain            SessionSimulation
  ↓ 读取                    ↓ 只依赖
StrategyContent   →      PokerCore

Infrastructure
  ├─ Local TrainingEventStore
  ├─ Session 记录存储
  ├─ Remote Synchronizer
  └─ Auth / Content / Hand Analysis API Clients
```

`SessionSimulation` 与 `TrainingDomain` 是**并列**的，不是上下游。牌局引擎
不知道教学内容存在，训练领域不知道牌局引擎存在；两者各自向 `PokerCore`
的 `SpotSignature` 产出签名，由 Feature 层——唯一同时看得见两边的层——做
比较。

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
- `PokerCore → SessionSimulation`
- `SessionSimulation → StrategyContent`
- `SessionSimulation → TrainingDomain`
- `TrainingDomain → SessionSimulation`

后四条是同一件事的两面。让 `SessionSimulation` 看见 `StrategyContent`
之后，回答「这个决策点值不值得与内容对照」最省事的写法就是在引擎里查
内容，而那个问题的答案就不再是关于这手牌的事实；反方向则直接构成环，
因为引擎推进牌局时要向训练层提问。`Packages/SessionSimulation/Package.swift`
的依赖列表是这条规则的执行点。
- 领域包 → SwiftUI
- 领域包 → 具体 HTTP 客户端
- View → MySQL、文件系统或同步 DTO
- 生成式文本 → DecisionScorer 输入

## 违反案例

项目尚无源代码。首次发现违反分层的实现时，应在本节记录文件、原因和修复结果。

