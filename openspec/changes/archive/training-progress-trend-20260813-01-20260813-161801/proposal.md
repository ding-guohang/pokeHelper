---
name: training-progress-trend-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：训练进度趋势（内容无关，聚合用户自己的训练事件）

## Why

复盘只显示当前能力**快照**（把所有事件折成每维度一组均值）。用户看不到「我在变好吗」
——每天练了多少、平均分怎么走。所有需要的数据都已在本地 `TrainingEvent` 里（时间戳、
0–100 分、失误质量），只是从没按时间聚合过。加一个**按日**的进度趋势，纯粹聚合用户
自己已评分的决策，**不涉及任何策略真值**（分数在评分时已由内容治理，这里只做加总）。

## What Changes

### New Capabilities

- `training-progress-trend` — 领域侧把 `[TrainingEvent]` 按日历日聚合为每日进度
  （手数、总分、失误数，均值在展示时用整数除法算），供复盘下的「训练进度」视图按时间
  升序展示，并给总览（总手数、练习天数、总平均分）。纯聚合，内容无关，不产生新事件。

### Modified Capabilities

无。

## Capabilities Detail

### Capability: training-progress-trend

- **领域（TrainingDomain，纯函数、可测）**：`DailyProgress`（`dayStart: Date`、
  `sampleCount`、`scoreTotal`、`blunderCount`；`meanScore` 为 `scoreTotal/sampleCount`
  的整数除法，空则 0）与 `ProgressTrend.daily(events:calendar:) -> [DailyProgress]`：
  按 `calendar.startOfDay(for: event.occurredAt)` 分组，累加 `grade.score`、计数、
  统计 `grade.quality == .blunder`，按 `dayStart` **升序**返回。日历由调用方传入（本地
  时区是展示关切，不藏进领域全局），保持纯净可测。
- **App（复盘下工具）**：`ProgressTrendViewModel(eventStore:calendar:)` 读
  `eventStore.allEvents()` → `ProgressTrend.daily` → 每日行文本 + 总览；空事件给空态。
  `ProgressTrendView` 手写 SwiftUI 文本行（与现有风格一致，不引图表库），入口在
  `ReviewView` 与其他复盘工具并列（`review.progressTrend`）。
- 精确：分数/失误为整数，逐日只存 `scoreTotal` 与 `sampleCount`，均值只在展示时整除。

#### Requirement: 按日聚合训练进度

The system SHALL aggregate the user's own training events into per-day progress
(hands practiced, score total, blunder count) grouped by calendar day and ordered
ascending by day, computing mean score by integer division, introducing no strategy
content and producing no new event.

##### Scenario: 多日事件按日聚合且均值精确

- GIVEN 三个训练事件：第 1 天两个（得分 `80`、`60`，其中一个质量为 `blunder`）、第 2 天
  一个（得分 `100`，非 blunder）
- WHEN 用 `ProgressTrend.daily(events:calendar:)` 聚合
- THEN 得两个 `DailyProgress`，按日升序：第 1 天 `sampleCount=2`、`scoreTotal=140`、
  `blunderCount=1`、`meanScore=70`；第 2 天 `sampleCount=1`、`scoreTotal=100`、
  `blunderCount=0`、`meanScore=100`
- AND 同一天的多个事件归入同一桶（不因时刻不同而拆分）

##### Scenario: 无事件给空结果

- GIVEN 空事件列表
- WHEN 聚合
- THEN 返回空数组（视图侧显示空态，不显示任何数字）

#### Requirement: 复盘下可达的进度趋势视图

The system SHALL make the progress trend reachable from within 复盘, showing per-day
rows and an overall summary, or an empty state when there are no events, without
altering the four core tabs.

##### Scenario: 复盘下打开进度趋势

- GIVEN 复盘标签
- WHEN 打开「训练进度」（`review.progressTrend`）
- THEN 显示每日进度行（或空态）；页面经复盘标签（iPhone）或侧栏（iPad）可达
- AND 四个核心标签不变（`AdaptiveNavigationTests` 仍断言 `[今日,学习,训练,复盘]`）

##### Scenario: ViewModel 聚合注入的事件（可测）

- GIVEN 注入一个返回上面三事件的事件存储
- WHEN `ProgressTrendViewModel.load()`
- THEN 有两日行；总览为「共 3 手 · 2 天 · 总平均 80 分」（`240/3` 整除）
- AND 注入空存储时只显示空态、无日行

## Impact

- **Code:** 新增 `Packages/TrainingDomain/Sources/TrainingDomain/ProgressTrend.swift`
  与其测试；新增 `PokerCoach/Features/Progress/{ProgressTrendView,ProgressTrendViewModel}.swift`；
  改 `PokerCoach/Features/Review/ReviewView.swift`（加入口）；新增 App 单测与 UI 测试。
- **Interfaces:** 复盘下多一个只读视图；无网络/存储/契约变更；不产生 `TrainingEvent`；
  不改 `TrainingEvent`/契约。
- **Dependencies:** 无新增（复用 `TrainingEventStore`、`AbilityDimensionPresentation` 不需要）。

## Risks

- **时区/日界不确定**：→ 日历由调用方注入（App 用 `.current`），领域纯函数不藏全局时区；
  测试用固定日历构造事件，确定性。
- **均值取整**：→ 逐日保 `scoreTotal`+`sampleCount`，只在展示整除；与既有 `PlayerModelReducer`
  取整口径一致。
- **被误当策略**：→ 纯聚合用户自己的历史评分，无范围/无新评分/无建议。

## Non-Goals

- 不引入图表库（先手写文本行/可选简单条）；不做周/月桶（先按日）。
- 不做按维度拆分趋势（先总体）；不做导出/同步。
- 不改 `TrainingEvent` 或冻结契约。

## Acceptance Criteria

1. `swift test --package-path Packages/TrainingDomain` 含 `ProgressTrend` 全绿：三事件两日、
   第 1 天 `140/2/1→70`、第 2 天 `100/1/0→100`、升序；空→空。
2. App 单测：注入三事件 → 两日行 + 总览「共 3 手 · 2 天 · 总平均 80 分」；空→空态。
3. UI 测试：复盘 →「训练进度」可达并渲染（重置事件后为空态）。
4. `AdaptiveNavigationTests` 绿；Release 构建通过；层禁通过（TrainingDomain 仍只 PokerCore/StrategyContent）。
