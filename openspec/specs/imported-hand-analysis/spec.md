# Capability: imported-hand-analysis

## Requirement: 逐节点判断覆盖并给出对照与偏离幅度

The system SHALL classify each hero decision point as covered or uncovered by installed content, present for a covered point the hero's action and the content's basis-point weight for it together with a deviation magnitude, and mark an uncovered point as having nothing to compare — never fabricating a weight or magnitude.

### Scenario: 命中内容的翻前节点给出对照

- GIVEN 附录 A（英雄 BTN 翻前用 `AKo` 加注），且已安装内容覆盖该 (位置, 面对情形, 筹码分桶)
- WHEN 分析该节点
- THEN 该节点为 `covered`，显示英雄行动（加注）与内容对该手牌类别所取行动给出的权重（基点）
- AND 该权重取自覆盖场景的范围表（等于对该 scenarioID、该手牌类别、该行动查表所得），不是被编造的

### Scenario: 未命中内容的翻后节点不编造频率

- GIVEN 附录 A 的翻牌/转牌/河牌节点（已安装内容只有翻前，翻后无覆盖）
- WHEN 分析这些节点
- THEN 每个翻后节点为 `uncovered`
- AND 其对照与偏离幅度均为"无"（无被编造的权重或幅度）

### Scenario: 无已安装内容时全部无内容可对照

- GIVEN 已安装内容为空的分析环境与附录 A
- WHEN 分析其英雄节点
- THEN 每个节点都为 `uncovered`
- AND 与"命中内容的翻前节点"成对：内容存在时附录 A 翻前节点为 `covered`，内容为空时同一节点为 `uncovered`——排除恒 covered / 恒 uncovered 的实现

### Scenario: 偏离幅度是内容权重的严格减函数

- GIVEN 两个基点权重 `w1 < w2`（均在 0..10000）
- WHEN 分别求偏离幅度
- THEN `deviationMagnitude(w1)` 严格大于 `deviationMagnitude(w2)`
- AND `deviationMagnitude(w)` 等于 `10000 − w`（对权重 0 得 10000，对权重 10000 得 0）

## Requirement: 据偏离与全下选出关键节点，且不产生 TrainingEvent

The system SHALL select the hero decision points whose reason is `deviation` (covered and weight below the deviation threshold) or `allIn` (the decision committed the hero's whole stack), order them deviations-first by descending magnitude then all-ins, cap them at five, and SHALL NOT produce any TrainingEvent while analyzing.

### Scenario: 偏离节点被选出且高权重节点不算偏离

- GIVEN 两手除英雄底牌外相同的 BTN 翻前开池牌谱：一手英雄用覆盖范围以 0 权重对待的手牌（`32o`，附录 G）开池，另一手用附录 A 的 `AKo`（覆盖范围高权重加注）
- WHEN 分析各自的翻前节点
- THEN `32o` 那一手该节点被标为 `deviation`，偏离幅度为 10000
- AND `AKo` 那一手该节点不被标为 `deviation`
- AND 这对断言排除"恒偏离 / 恒不偏离"的实现

### Scenario: 全下决策被选为关键节点

- GIVEN 一手英雄在某决策点投入全部筹码的导入牌谱（附录 H，随本切片提交）
- WHEN 选出关键节点
- THEN 该全下决策点在关键节点中，理由为 `allIn`
- AND 判定依据是该座位在此决策后投入达其起始筹码，而非行动文本里是否出现 "all-in" 字样

### Scenario: 关键节点最多五个且既非偏离也非全下时为空

- GIVEN 附录 A 且已安装内容为空（无覆盖故无 `deviation`，且附录 A 无全下）
- WHEN 选出关键节点
- THEN 关键节点为空集
- AND 对一个构造出的含 6 个偏离节点的牌谱，关键节点恰为 5 个（上界），按偏离幅度降序

### Scenario: 分析不产生 TrainingEvent

- GIVEN 一条持有非空训练事件存储的真实分析路径（仿第一切片导入协调器，持有存储却不写入）
- WHEN 分析一手已导入并采纳、且含至少一个关键节点的牌谱
- THEN 分析产出了非空的关键节点（证明分析确实发生）
- AND 训练事件存储的条数与内容在整个过程中保持不变

## Impact

- **Code:** `HandHistory` 新增"从 `ObservedHand` 导出英雄决策点签名"的纯逻辑（只依赖 PokerCore，产出 `SpotSignature`；重建每个英雄决策点前的下注状态求 `facing` 与 `stackBucket`），并给 `hand-model-writer` 加 `--signatures` 模式输出签名序列的规范序列化。App 层 `Features/HandLab` 新增：`ImportedHandContentMatcher`（仿 `SessionContentMatcher`，按 `SpotCoverageKey` 匹配、命中后查范围表权重）、节点分析与关键节点选择（节点粒度，理由 `deviation`/`allIn`）、对照视图；分析经持有事件存储却不写入的协调器路径。
- **Interfaces:** 复盘内牌谱库项新增"分析/关键节点"界面；无服务端接口变更。
- **Dependencies:** 复用 `PokerCore`、`StrategyContent`（内容与范围表权重）；无第三方；不依赖也不修改 `SessionSimulation`。

## Risks

- **重建下注状态求 facing/stackBucket 出错** → 附录 A 四个节点逐街钉死 facing 与随街变化的 stackBucket；附录 F 钉死"面对一次加注"。
- **偏离判定/幅度退化** → 偏离幅度作为纯函数 `10000 − w` 单独断言严格单调；再用 `32o`(权重0，附录G) vs `AKo`(高权重) 的成对牌谱断言 flag 两向。
- **覆盖判定与 M2A 漂移** → 复用同一 `SpotCoverageKey`，不新造键；App 层匹配仿 `SessionContentMatcher` 并各自测试。
- **关键节点计数恒真** → 明确上界 5、下界可为 0（附录 A 空内容），并用 6-偏离节点构造牌谱断言恰取 5。
- **分析路径悄悄写事件** → 走持有事件存储却不写入的路径，隔离场景同时断言"确有关键节点产出"，排除空操作。
- **英雄识别依赖"对手明牌暂不读取"** → 术语明确英雄座=唯一 `.known` 座位，并记其依赖第一切片的已知限制；将来读取摊牌明牌时引入显式英雄座字段。

## Non-Goals

- 分支重放与反事实对比、补救训练生成、漏洞标签落库——后续 M2B 切片。
- `bigSwing`/`bigPot` 理由——需要派彩数据（`ObservedHand` 没有）或手粒度语义，本切片不做。
- 给 `ObservedHand` 增派彩/赢家字段、改第一切片模型或其黄金——推迟。
- 生成任何 `TrainingEvent`；引入翻后内容；修改 `SessionSimulation`。

## Acceptance Criteria

1. 附录 A 导出恰 4 个英雄决策点签名，手牌类别 `AKo`、位置 BTN、facing 逐街为 `priorRaiseCount:0`、stackBucket 随街为 10000/9700/9300/9300 的据算参考值；附录 F 得 `priorRaiseCount:1`；跨进程签名序列逐字节相等且等于黄金。
2. 命中内容的翻前节点给"英雄行动 vs 范围表权重"的对照；翻后与空内容节点为 `uncovered` 且无被编造的权重/幅度（与覆盖节点成对）。
3. 偏离幅度 `= 10000 − w` 且严格随 `w` 递减；`32o` 开池被标 `deviation`(幅度10000)、`AKo` 开池不被标（成对）。
4. 关键节点理由仅 `deviation`/`allIn`、上界 5、可为空（附录 A 空内容为空集，6-偏离构造牌谱恰取 5）；全下决策以 `allIn` 入选；分析全程不产生 `TrainingEvent` 且断言确有关键节点产出。
5. 分层不破坏：签名导出只依赖 PokerCore；`HandHistory` 不依赖 `StrategyContent`/`SessionSimulation`；内容对照只在 App 层发生。
