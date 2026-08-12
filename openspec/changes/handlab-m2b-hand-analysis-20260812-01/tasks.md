---
name: handlab-m2b-hand-analysis-20260812-01
status: planned
---

# 执行计划：M2B 个人牌局实验室（第二切片：关键节点与策略对照）

铁律沿用：先写测试并**观察它红**，再写实现。每条依赖夹具的断言前置「夹具确实产出了东西」的自检。

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| imported-hand-signatures | 确定性导出英雄决策点签名 | 附录 A 四节点逐街钉死 | T1 |
| imported-hand-signatures | 确定性导出英雄决策点签名 | 面对情形由加注次数得出 | T1 |
| imported-hand-signatures | 确定性导出英雄决策点签名 | 跨进程签名黄金 | T2 |
| imported-hand-analysis | 逐节点判断覆盖与偏离幅度 | 命中内容的翻前节点对照 | T4 |
| imported-hand-analysis | 逐节点判断覆盖与偏离幅度 | 未命中翻后节点不编造 | T4 |
| imported-hand-analysis | 逐节点判断覆盖与偏离幅度 | 空内容全部 uncovered（成对） | T4 |
| imported-hand-analysis | 逐节点判断覆盖与偏离幅度 | 偏离幅度是权重的严格减函数 | T3 |
| imported-hand-analysis | 据偏离与全下选关键节点、不产生事件 | 偏离节点被选且高权重不算偏离 | T5 |
| imported-hand-analysis | 据偏离与全下选关键节点、不产生事件 | 全下决策入选 | T5 |
| imported-hand-analysis | 据偏离与全下选关键节点、不产生事件 | 上界5/可为空 | T5 |
| imported-hand-analysis | 据偏离与全下选关键节点、不产生事件 | 分析不产生 TrainingEvent | T6 |

## 里程碑 A：HandHistory 签名导出

### T1 — `heroDecisionSignatures()`
`covers:` imported-hand-signatures / 附录 A 四节点、面对加注

新增 `Packages/HandHistory/Sources/HandHistory/HeroDecisionSignature.swift`：`HeroDecisionSignature`（street, actionIndexInStreet, signature, action, isAllIn；全 `Codable, Hashable, Sendable`）+ `extension ObservedHand { func heroDecisionSignatures() -> [HeroDecisionSignature] }`。

实现见 design.md 决断 1：英雄=唯一 `.known` 座位；逐街维护每座位本街/累计投入（`forcedPosts` 计入盲注座）；`priorRaiseCount`=英雄行动前本街 `raiseTo`/`bet` 次数；effectiveStack=英雄起始筹码−行动前累计投入；`isAllIn`=行动后累计投入==起始筹码。

提交夹具 `Tests/Fixtures/sample-ps-6max-vs-raise.txt`（附录 F：英雄翻前面对恰一次加注后行动；6-max、$0.50/$1、英雄非盲注位、有人先加注、英雄再行动）。

先写测试 `HeroDecisionSignatureTests`（Swift Testing）：
1. `附录A四节点逐街` — 恰 4 个签名，street 依次 preflop/flop/turn/river；`handClass == HandClass(Card(code:"Ah")!, Card(code:"Kd")!)`；`heroSeatOffsetFromButton==0`；`facing == FacingAction(priorRaiseCount:0)` ×4；`stackBucket` 依次 `StackBucket(effectiveStack: BBAmount(centiBB: 10000/9700/9300/9300))`（据算参考值，逐街不同）。自检 `#expect(!sigs.isEmpty)`。
2. `面对加注` — 附录 F 英雄决策点 `facing == FacingAction(priorRaiseCount:1)`；与附录 A 的 0 成对。

**红灯观察**：把 effectiveStack 写成固定 `startingStack`（不减投入）→ 翻牌/转牌 stackBucket 断言红；把 priorRaiseCount 写死 0 → 附录 F 红。

### T2 — `hand-model-writer --signatures` + 跨进程黄金
`covers:` imported-hand-signatures / 跨进程签名黄金

给 `Sources/hand-model-writer/main.swift` 加 `--signatures`：解析 `--fixture`，成功则对 `heroDecisionSignatures()` 数组 `canonicalJSON`（`[.sortedKeys,.prettyPrinted,.withoutEscapingSlashes]`）打印；`.unsupported` 走原路径非零退出。提交黄金 `Tests/Fixtures/sample-ps-6max-nlhe.signatures.json`（附录 A 的 `--signatures` 实际输出，运行一次后提交）。

先写测试 `SignatureCrossProcessTests`（复用 `Support/WriterBinary.swift`）：两独立进程各跑 `--signatures` 于附录 A，断言 stdout 字节相等且等于黄金；不等打印首个差异位置与重生成命令。

**红灯观察**：改黄金一个字节 → 测试红。

## 里程碑 B：App 层分析

### T3 — 偏离幅度纯函数
`covers:` imported-hand-analysis / 偏离幅度严格减函数

新增 `PokerCoach/Infrastructure/HandLab/DeviationMagnitude.swift`（或并入 selection 文件）：`deviationMagnitude(weightBasisPoints:) -> Int = 10_000 - w`。

先写测试 `PokerCoachTests/ImportedHandDeviationTests`：对 `w1<w2` 断言 `deviationMagnitude(w1) > deviationMagnitude(w2)`；`deviationMagnitude(0)==10000`、`deviationMagnitude(10000)==0`。

**红灯观察**：把函数写成常量 → 单调断言红。

### T4 — `ImportedHandContentMatcher`
`covers:` imported-hand-analysis / 命中对照、未命中不编造、空内容成对

新增 `PokerCoach/Infrastructure/HandLab/ImportedHandContentMatcher.swift`（仿 `SessionContentMatcher`）：`func classify(_ sig: HeroDecisionSignature) -> NodeCoverage`，`NodeCoverage = .covered(scenarioID:String, weightBasisPoints:Int) | .uncovered`。命中用 `signature.coverageKey` 找场景，查范围表对 `handClass`+`action` 的权重（走 `RangeBaseline` 同源通路）。

复用 App 测试支持里的附录 A 文本常量（slice 1 已有 `HandImportFixtureText.appendixA`）解析成 `ObservedHand`。

先写测试 `PokerCoachTests/ImportedHandContentMatchTests`：
1. `命中翻前` — 装入覆盖 BTN 翻前的内容，附录 A 翻前节点 `.covered(scenarioID, w)`，`w` 等于对该 scenarioID/handClass/action 查表所得（非编造）。
2. `翻后不编造` — 翻牌/转牌/河牌节点 `.uncovered`，无权重。
3. `空内容成对` — 内容为空时附录 A 翻前节点 `.uncovered`；与 1 成对（排除恒 covered/恒 uncovered）。自检：确有节点被分类。

**红灯观察**：恒 `.covered` → 空内容断言红；恒 `.uncovered` → 命中断言红。

### T5 — `ImportedHandKeyNodeSelection`
`covers:` imported-hand-analysis / 偏离入选、全下入选、上界5可为空

新增 `PokerCoach/Infrastructure/HandLab/ImportedHandKeyNodeSelection.swift`：输入 `[(HeroDecisionSignature, NodeCoverage)]`，输出 `[KeyNode]`（`KeyNode{signature, reason: .deviation/.allIn, deviationMagnitude:Int?}`）。规则见 design.md 决断 3：deviation 当 covered 且 w<5000；allIn 当 isAllIn；一节点两者取 deviation；排序 deviation 按幅度降序再 allIn；`min(5,数量)`。

提交夹具 `sample-ps-6max-btn-open-trash.txt`（附录 G：英雄 BTN 用 `3s 2d` 开池，其余同附录 A 的翻前布局）、`sample-ps-6max-hero-allin.txt`（附录 H：英雄某决策点全下）、`sample-ps-6max-six-deviations.txt`（构造：英雄 6 个被覆盖且低权重的决策点）。

先写测试 `PokerCoachTests/ImportedHandKeyNodeTests`：
1. `偏离成对` — 附录 G 翻前节点标 `.deviation`、幅度 10000（先读 pack 确认 32o 权重 0，否则换手并更新夹具）；附录 A 翻前 `AKo` 不标 `.deviation`。
2. `全下入选` — 附录 H 全下节点在关键节点、理由 `.allIn`；依据是投入达起始筹码，非文本 "all-in" 字样。
3. `上界与空集` — 附录 A + 空内容 → 关键节点为空；6-偏离夹具 → 恰 5 个、按幅度降序。

**红灯观察**：恒标一种理由 → 成对断言红；不设上界 → 6-偏离断言红。

### T6 — `HandAnalysisCoordinator` 与事件隔离
`covers:` imported-hand-analysis / 分析不产生 TrainingEvent

新增 `PokerCoach/Infrastructure/HandLab/HandAnalysisCoordinator.swift`（`@MainActor`，持有 `any TrainingEventStore`（**不写**，仿 `HandImportCoordinator` 注释）+ 库 + matcher）：`analyze(identity:) -> [KeyNode]`，读库中已采纳牌谱产出关键节点。

先写测试 `PokerCoachTests/HandAnalysisEventIsolationTests`（仿 `HandImportEventIsolationTests`）：种非空事件存储；采纳附录 G（含偏离）后 `analyze`；断言关键节点非空（确有产出）且事件存储条数与内容 == before。

**红灯观察**：让协调器顺手写事件 → 不变断言红；`analyze` 空实现 → 非空断言红。

## 里程碑 C：UI 与收口

### T7 — 分析视图与可达
`covers:` imported-hand-analysis（真实构建可达）

`PokerCoach/Features/HandLab/` 加关键节点/对照视图；从复盘→牌谱库项进入分析。`ImportedHandKeyNodePresentation` 纯映射（无业务计算）。

先写 `PokerCoachUITests/M2BAnalysisSurfaceTests`：复盘→牌谱→采纳附录 G→查看分析→看到被标偏离的关键节点与"你打的 vs 内容频率"。

**红灯观察**：不接入 → UI 测试找不到入口。

### T8 — `verify-m2b.sh` 扩展
`covers:` 全部

`scripts/verify-m2b.sh`：包测试已含 HandHistory；App 单测已含新测试；新增 UI `M2BAnalysisSurfaceTests` 可达；新增签名黄金门禁（`hand-model-writer --signatures` 输出 == 提交黄金，反向：改黄金一字节 → HandHistory 套件红）。保留既有跑通 verify-m1a/m1c/m2a 兜底。每道门禁有实测失败路径。

## 不变量（每里程碑末复验）
- `ObservedHand` 存储字段与 slice 1 黄金 `sample-ps-6max-nlhe.model.json` 未变（本切片只新增方法）。
- `HandHistory` 不依赖 `StrategyContent`/`SessionSimulation`；分析在 App 层。
- 不 import `SessionSimulation.KeyHandSelection`。
- `Contracts/…v1.sha256`、`CoreStrategyPack.json` 及其 `.sha256` 未变。
- `bash scripts/verify-m2b.sh` 通过（含 verify-m1a/m1c/m2a）。
