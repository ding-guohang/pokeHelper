---
name: poker-coach-m1a-cash-coach-20260806-01
status: designed
---

# M1A 现金局教练纵向切片技术设计

## 方案概述

M1A 使用一个离线可运行的纵向切片验证产品最核心的行为链：

```text
版本化现金局场景
  → 用户选择合法行动和信心
  → 确定性 EV 评分
  → 专业反馈
  → 本地 TrainingEvent
  → 能力画像和今日计划更新
```

客户端使用 SwiftUI 原生支持 iPhone/iPad。稳定领域能力拆成三个本地 Swift Package：

- `PokerCore`：牌、精确金额、行动和合法性。
- `StrategyContent`：策略包模型、加载、checksum 和语义校验。
- `TrainingDomain`：评分、训练事件、能力归约和今日计划。

SwiftUI App 只组合领域协议和展示模型。M1A 使用 append-only 本地事件存储，事件模型直接服务 M1B 的独立账号与同步，不在 M1A 引入 HTTP 或数据库 DTO。

## 选择该方案的原因

### 对比过的方案

1. **单一 App target 快速实现**：首屏速度快，但扑克规则、策略内容、评分和 UI 强耦合，M1B/M2/M3 难以复用和测试。
2. **按技术层建立大量 framework**：隔离充分，但绿地首个切片的工程成本过高。
3. **三个领域 Swift Package + 一个 App target（采用）**：用最少模块建立清晰边界，包测试可脱离 Simulator，SwiftUI 仍保持快速迭代。

### 关键取舍

- M1A 只使用 `testFixture` 策略内容，不宣称提供生产扑克建议。
- 本地事件采用 JSON Lines 原子持久化，先验证事件契约；M1B 增加 Outbox 和远端同步。
- M1A 只建模存储场景的决策节点，不实现完整发牌与 Session；完整模拟属于 M2A。
- 金额、EV 和频率使用带单位整数，牺牲直接浮点展示的便利，换取可复现和可同步。

## 模块设计

### PokerCore

职责：

- `Suit`、`Rank`、`Card` 和稳定两字符编码。
- `BBAmount` 使用 centi-BB。
- `EVAmount` 使用 milli-BB。
- `DecisionAction` 使用稳定 `{kind,toCentiBB}` JSON。
- `BettingDecisionContext.legalActions()` 计算 stored node 的合法行动。

禁止：

- 教学文案、策略频率、用户状态、文件、HTTP 和 SwiftUI。

### StrategyContent

职责：

- `StrategyPackManifest` 保存 schema/content version、来源和审核状态。
- `DecisionScenario` 保存牌、行动上下文、选项、频率、EV、范围和解释。
- `StrategyPackLoader` 先校验 SHA-256，再 ISO-8601 解码。
- `StrategyPackValidator` 校验重复牌、合法行动、重复行动、频率总和和审核元数据。
- `StrategyPackProviding` 隔离内容来源。

策略内容不可原地修改。历史事件固定引用原 pack ID 与 content version。

### TrainingDomain

职责：

- `DecisionScorer` 根据最佳 EV、所选 EV 和 pot 生成 raw loss、loss rate、score 和 quality。
- `TrainingEvent` 保存 M1B 同步所需字段。
- `TrainingEventStore` 定义追加和 checkpoint 读取协议。
- `FileTrainingEventStore` 提供本地幂等持久化。
- `PlayerModelReducer` 生成样本、均分、EV loss 和高信心错误。
- `TrainingPlanner` 按弱项、信心错误和遗忘时间选择三个项目。

评分不接收 runout、pot result 或 winnings。

### SwiftUI App

职责：

- 紧凑宽度使用四项 Tab，常规宽度使用四项 Sidebar。
- `DecisionSessionViewModel` 管理 loading、answering、feedback、completed 和 failed。
- Train 展示牌桌信息、合法行动和信心。
- Feedback 展示 raw EV、全部频率、范围、结构化推理、假设、来源和版本。
- Today 与 Review 从真实本地 TrainingEvent 刷新。

iPhone 使用单列滚动反馈；iPad 同时展示牌桌列和分析列。

## 数据流

```text
StrategyPackProvider
  → DecisionScenario
  → BettingDecisionContext.legalActions()
  → DecisionSubmission(action, confidence)
  → DecisionScorer
  → DecisionGrade
  → TrainingEventStore.append()
  → PlayerModelReducer
  → TrainingPlanner
  → Today / Review
```

提交必须满足：

1. 选择合法行动。
2. 选择信心。
3. 评分成功。
4. TrainingEvent 保存成功。
5. 才进入 feedback。

保存失败时保留用户选择并提供中文重试，不显示未持久化的成功反馈。

## Capability 覆盖

| Capability | 技术实现 | 主要 Task |
|---|---|---|
| adaptive-native-shell | XcodeGen、SwiftUI TabView/NavigationSplitView、依赖组合 | 1, 8, 12, 13 |
| cash-decision-domain | PokerCore 精确类型、合法行动和稳定 JSON | 2, 3 |
| versioned-strategy-content | StrategyContent loader、validator、provider 和 Debug pack | 4, 12 |
| explainable-decision-training | DecisionScorer、DecisionSession、ProfessionalFeedback | 5, 9, 10, 12 |
| local-learning-profile | TrainingEventStore、PlayerModelReducer、TrainingPlanner、Today/Review | 6, 7, 11 |
| m1a-release-safety | Debug disclosure、Release exclusion、验证脚本 | 1, 12, 13 |

## 文件与依赖

```text
PokerCoach/
  App/
  Features/{Today,Learn,Train,Feedback,Review}/
  Shared/
  Resources/
Packages/
  PokerCore/
  StrategyContent/      → PokerCore
  TrainingDomain/       → PokerCore + StrategyContent
PokerCoachTests/
PokerCoachUITests/
Config/
scripts/
project.yml
```

不新增第三方运行时依赖。工程由 XcodeGen 生成，`project.yml` 是工程真值。

## 向后兼容与后续演进

仓库当前无源代码，不存在运行时向后兼容负担。M1A 必须稳定以下接口供 M1B 使用：

- `TrainingEvent`
- `TrainingEventStore`
- `FileTrainingEventStore`
- `StrategyPackManifest`

M1B 通过基础设施适配器增加远端同步，不把认证、HTTP 或数据库 DTO 移入领域包。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 开发数据被误认为专业建议 | Debug 全链路披露；Release 资源排除 |
| 混合策略被压成唯一答案 | 保留全部行动、频率与 raw EV |
| 浮点误差影响评分或同步 | centi-BB、milli-BB、basis points |
| UI 生成非法行动 | 只展示 PokerCore 返回的合法行动 |
| 本地历史重复或损坏 | event ID 幂等、原子写入、行号错误 |
| M1A 过度扩张 | proposal Non-Goals 和 M1A completion gate |
| iPad 成为放大版 iPhone | 独立多栏 UI 测试 |

## 测试策略

- Swift Package 使用 Swift Testing。
- App model 使用 XCTest。
- iPhone/iPad 主流程使用 XCUITest。
- 所有 fixture 使用固定 UUID、日期和场景数据。
- 策略包覆盖 checksum、schema、频率、重复牌、非法/重复行动和审核状态。
- DecisionScorer 覆盖最高 EV、接近 EV、非法行动和结果独立性。
- Store 覆盖幂等、排序、checkpoint 和损坏行。
- Release 构建后检查 bundle 不包含 `DevStrategyPack.json`。
- `scripts/verify-m1a.sh` 汇总包、APP、iPhone、iPad 和 Release 验证。

## 完成边界

M1A 只在完整验证、逐 Task 双阶段评审和最终分支评审通过后完成。它仍不是完整 M1；M1B 独立账号同步和 M1C 自适应现金局课程必须后续分别验收。

