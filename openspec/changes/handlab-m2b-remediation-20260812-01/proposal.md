---
name: handlab-m2b-remediation-20260812-01
created: 2026-08-12
status: review_passed
---

# 需求提案：M2B 个人牌局实验室（第三切片：补救训练）

## Why

第一、二切片把真实牌谱变成可信的 `ObservedHand`，逐节点对照已安装内容、挑出偏离关键节点——但那些只是"看清问题"。产品最高宗旨是把用户练成更好的职业牌手，闭环最后一步是**把真实牌里暴露的漏洞变成训练**：

> 原始文本 → 格式识别 → 标准牌谱 → 冲突预览 → 关键节点 → 策略分析 →〔**后续训练**〕

对一个**偏离关键节点**（英雄真实打法偏离已安装内容、且该局面被内容覆盖），提供一道"补救训练"——在该节点的**覆盖场景**上走一遍既有训练流程（出示行动与信心、评分、落库为普通 `TrainingEvent`、进能力画像）。这与 M1C 的训练同一条管线，也满足 M2 gate："模拟与牌谱导入必须发同一个版本化 `TrainingEvent` 契约"。

区分（沿用一、二切片）：**导入与对照不产生 `TrainingEvent`**；只有用户主动做补救训练才产生事件，且走既有管线、发既有冻结契约。

## 复用与一处必要的加法（据审需修正）

- 复用 `DecisionSessionViewModel` 训练流程：它只需一个 `scenarioID`，自行从包解析场景并构造 `TrainingEvent(scenarioID:…)`；`AppDependencies.makeDecisionSessionViewModel(scenarioID:)` 已注入 grader/eventStore/ids/now。补救训练就是用偏离节点的覆盖场景 ID 驱动它。
- **必要的加法**：审需发现第二切片的 `KeyNode` **并未携带覆盖 `scenarioID`**（`selectKeyNodes` 把 `.covered(scenarioID, weight)` 的 id 丢进了 `_`）。本切片**追加一个字段** `coveringScenarioID: String?` 到 `KeyNode`，在 `selectKeyNodes` 里对 `deviation` 节点保留该 id。这是**加法**——不改变 `imported-hand-analysis` 任何既有 scenario（其 scenario 不涉及 `KeyNode` 字段集），第二切片测试不受影响。故 `imported-hand-analysis` 不列为 Modified，但此加法在 Impact 里明确记录，不藏。
- 复用既有事件归约、同步与冻结契约 `Contracts/training-event-upload-v1.json`。

## What Changes

### New Capabilities

- `imported-hand-remediation` — 偏离关键节点暴露其覆盖场景并可发起补救训练；完成后经既有训练管线产出一条与"直接训练该场景"无从区分的 `TrainingEvent`。

### Modified Capabilities

无。`KeyNode` 追加 `coveringScenarioID` 是加法，不改 `imported-hand-analysis` 的任何 scenario；不改 `DecisionSessionViewModel`/`TrainingDomain`/事件契约的语义。

### Removed Capabilities

无。

## 术语

- **补救训练**：以偏离关键节点的**覆盖场景**（该节点 `coveringScenarioID` 所指的已安装 `DecisionScenario`）为题的一次标准决策训练。
- **可补救节点**：`reason == .deviation` 的关键节点——据第二切片，deviation 必然 covered，故必有 `coveringScenarioID`。`allIn` 关键节点无覆盖场景，不可补救。

## Capabilities Detail

### Capability: imported-hand-remediation

#### Requirement: 偏离关键节点暴露覆盖场景并据此发起补救训练

The system SHALL expose, on each `deviation` key node, the id of the `DecisionScenario` that covers it, and SHALL offer a remediation drill whose scenario is exactly that scenario; an `allIn` key node exposes no covering scenario and offers no drill.

##### Scenario: 偏离节点的覆盖场景就是分析判定的那个场景

- GIVEN 两手已采纳并分析的导入牌谱，其翻前节点均为 `deviation`，但位置不同、被不同场景覆盖：附录 G（`32o` 从 BTN 开池，被 `rfi-btn` 覆盖）与附录 I（`32o` 从 CO 开池，被 `rfi-co` 覆盖）
- WHEN 读取各自偏离节点的覆盖场景，并据此发起补救训练
- THEN 每个偏离节点的 `coveringScenarioID` 等于内容匹配对该节点签名判定出的 `scenarioID`（附录 G 为 `rfi-btn`、附录 I 为 `rfi-co`），两者不同
- AND 每道补救训练的场景 ID 等于对应节点的 `coveringScenarioID`（据节点导出，而非某个写死的常量——常量实现会在两手之一失败）

##### Scenario: 全下关键节点不提供补救训练

- GIVEN 一个 `reason == .allIn` 的关键节点（附录 H 的全下节点）
- WHEN 请求补救训练
- THEN 不提供补救训练，且该节点不暴露任何 `coveringScenarioID`
- AND 与上一场景成对：只有覆盖偏离节点可补救，全下节点不可

#### Requirement: 完成补救训练产生与直接训练该场景无从区分的事件

The system SHALL, when the user completes a remediation drill by submitting an action and a confidence, grade and persist a `TrainingEvent` through the existing training pipeline; that event's `scenarioID`, `strategyPackID`, `strategyContentVersion`, `abilityDimension`, `submission` and full `grade` SHALL equal those of an event produced by training the same scenario directly with the same submission, differing only in `id`, `occurredAt` and `deviceID`.

##### Scenario: 补救训练事件与直接训练该场景的事件按字段相等

- GIVEN 覆盖场景 S 上的一道补救训练，与直接在 S 上的一次普通训练（同一用户、同一 pack），二者提交相同的行动与信心
- WHEN 各自完成
- THEN 事件存储各多出一条
- AND 两条事件的 `scenarioID`(均为 S)、`strategyPackID`、`strategyContentVersion`、`abilityDimension`、`submission`、以及完整的 `grade`（`DecisionGrade` 的全部字段：selectedAction/frequency/selectedEV/bestEV/evLoss/lossRate/score/quality/isStrategicallyAvailable）逐字段相等
- AND 两条事件仅在 `id`、`occurredAt`、`deviceID` 上不同（不用 `TrainingEvent` 的 `==`，因为它把这三者也纳入相等）

##### Scenario: 补救事件绑定到正确场景并进入能力画像

- GIVEN 覆盖场景 S（能力维度 D）上的一道补救训练，事件存储非空
- WHEN 用户完成该补救训练
- THEN 事件存储恰多出一条，其 `scenarioID == S`、`abilityDimension == D`、含 `submission` 与 `grade`
- AND 该事件被既有 `PlayerModelReducer` 计入能力画像的维度 D（与其他训练事件一视同仁）

##### Scenario: 打开分析而不发起补救训练不产生任何事件

- GIVEN 一条持有事件存储、可发起补救训练的分析路径（本切片新增、具备写事件能力的桥）
- WHEN 用户打开分析、查看关键节点，但不发起任何补救训练
- THEN 事件存储的条数与内容不变
- AND 只有完成一道补救训练才 +1；分析与导入本身仍不产生事件（本切片不回退第二切片的隔离）

## Impact

- **Code:** 追加 `KeyNode.coveringScenarioID: String?`，在 `ImportedHandKeyNodeSelection.selectKeyNodes` 对 `deviation` 节点保留 `.covered` 的 scenarioID（加法，不改分析行为）。App 层 `Features/HandLab` 分析视图为 `deviation` 节点加"练这个漏洞"入口，经一个薄桥用该 `coveringScenarioID` 调 `AppDependencies.makeDecisionSessionViewModel(scenarioID:)` 呈现既有训练流程。桥持有事件存储仅用于驱动训练管线；打开分析不写事件。无新领域类型、无新事件字段。
- **Interfaces:** 复盘→Hand Lab→某手→分析→（偏离节点）练这个漏洞 → 既有训练界面；无服务端接口变更。
- **Dependencies:** 复用 `TrainingDomain`（评分/事件/归约）、`StrategyContent`（场景）、既有 `DecisionSessionViewModel`；无第三方。

## Risks

- **`KeyNode` 不带 scenarioID（审需已证）** → 本切片显式追加 `coveringScenarioID`（加法），并断言其等于分析对该节点判定的 scenarioID；用 BTN/CO 两个不同覆盖场景防"写死常量"。
- **补救事件与普通训练事件分歧** → 直接复用 `DecisionSessionViewModel` 事件构造；成对断言除 id/时间/设备外逐字段相等，且 `grade` 全字段比，不用 `TrainingEvent.==`。
- **给不可补救节点也发训练** → 只有覆盖 deviation 可补救；成对断言 allIn 节点无 `coveringScenarioID`、无训练。
- **新桥回退"分析不产生事件"** → 新增场景：打开分析不发起训练则事件不变（新写能力路径也被断言）。

## Non-Goals

- 分支重放与反事实对比、漏洞标签落库、手动场景构建器——后续 M2B 切片。
- 自动从原始牌生成训练（不经用户主动重打）；新事件字段或契约变更；翻后补救（deviation 只在翻前覆盖）。
- 改动 `imported-hand-analysis` 的既有 scenario 或 `DecisionSessionViewModel` 的评分/事件语义。

## Acceptance Criteria

1. `deviation` 关键节点暴露 `coveringScenarioID`，等于分析对其签名判定的 scenarioID（BTN→`rfi-btn`、CO→`rfi-co`，两者不同，防常量）；补救训练场景 ID 等于该值；`allIn` 节点无 scenarioID、无补救（成对）。
2. 完成补救训练产出的事件，与直接训练同场景同提交的事件，除 `id`/`occurredAt`/`deviceID` 外逐字段相等（含完整 `grade`）。
3. 补救事件 `scenarioID == S`、进入既有 `PlayerModelReducer` 的维度 D；打开分析不发起训练则事件不变；导入/分析本身仍不产生事件。
4. 分层不破坏：`coveringScenarioID` 加法在 App 的 HandLab 选择逻辑；桥与训练呈现在 App 层；不改 `TrainingDomain`/`StrategyContent`/事件契约/`DecisionSessionViewModel` 语义。
