---
name: handlab-m2b-hand-analysis-20260812-01
status: designed
---

# 技术方案：M2B 个人牌局实验室（第二切片：关键节点与策略对照）

本文写审需收窄后的结构与四个决断。proposal 已把行为规格定死，这里不复述。

## 结构

```text
        ┌──────────────┐
        │  PokerCore   │  SpotSignature / SpotCoverageKey / HandClass / FacingAction / StackBucket / Street
        └──────┬───────┘
               │
        ┌──────┴───────────┐
        │   HandHistory    │  ObservedHand（slice 1）
        │  + heroDecisionSignatures()  ← 本切片新增：纯函数，产出 [HeroDecisionSignature]
        │  hand-model-writer --signatures ← 新增模式，跨进程黄金用
        └──────┬───────────┘
               │
   App 层（唯一同时看得见 HandHistory 与 StrategyContent 的层）：
     PokerCoach/Infrastructure/HandLab/
       ImportedHandContentMatcher   （仿 SessionContentMatcher：按 SpotCoverageKey 匹配 + 查范围表权重）
       ImportedHandKeyNodeSelection （节点粒度：deviation/allIn，排序、上界 5）
       HandAnalysisCoordinator      （持有 TrainingEventStore 却不写，读库中牌谱产出分析）
     PokerCoach/Features/HandLab/    分析/关键节点视图
```

`HandHistory` 仍只依赖 `PokerCore`——签名导出是纯扑克事实，不知道教学内容存在。内容匹配、偏离判定、关键节点选择都在 App 层，因为只有它同时看得见两边（与 M2A 的 `SessionContentMatcher` 同一判断）。`check-package-layering.sh` 无需改（分析代码在 App 目标，脚本只查 `Packages/*`）。

## 决断 1：`heroDecisionSignatures()` 落 HandHistory，重建下注状态

新增（`HandHistory`，只依赖 PokerCore）：

```swift
public struct HeroDecisionSignature: Hashable, Sendable, Codable {
    public let street: Street
    public let actionIndexInStreet: Int      // 该街自主行动序列中的位置，定位到具体决策
    public let signature: SpotSignature      // street/offset/handClass/facing/stackBucket
    public let action: ObservedAction        // 英雄在该点实际所取行动
    public let isAllIn: Bool                 // 该决策后英雄投入达其起始筹码（纯事实）
}

extension ObservedHand {
    /// 英雄每个自主决策点的签名，按发生顺序。英雄 = holeCards 为 .known 的座位。
    public func heroDecisionSignatures() -> [HeroDecisionSignature]
}
```

重建逻辑（确定性，纯 Int/枚举，无 Set/Dictionary 迭代序、无时钟）：
- 英雄座 = 唯一 `holeCards == .known` 的座位（受支持类里恰一个；见 proposal 术语）。
- 逐街遍历：维护每座位「本街已投入」（`forcedPosts` 先于翻前自主行动计入盲注座）与「累计已投入」；`priorRaiseCount` = 英雄该行动之前本街出现的 `raiseTo`/`bet` 次数 → `FacingAction(priorRaiseCount:)`。
- **effectiveStack 口径**：英雄该决策点的剩余筹码 = `startingStackCentiBB − 英雄在此行动之前累计已投入`，与 M2A `HandState.decisionContext` 用 `stacks[seat]` 一致 → `StackBucket(effectiveStack:)`。
  - 附录 A：翻前 10000；翻牌 9700（翻前投入 300）；转牌/河牌 9300（翻牌再投入 400）。
  - 但附录 A 这四个 effectiveStack 全落在同一 `deep` 桶，只钉它们无法证伪一个「恒返回同一桶」的实现；因此另加专用跨桶夹具 `sample-ps-6max-short-crossing.txt`（英雄起始 4000 → `medium`，逐街投入后转牌剩余 1600 → `short`），断言 `Set(stackBucket).count >= 2` 才真正击穿常量实现。
- `isAllIn` = 该行动后英雄累计已投入 == 其 `startingStackCentiBB`。

`handClass = HandClass(hero.holeCards)`。附录 A：`Ah Kd` → `AKo`，四个决策点同一 handClass。

## 决断 2：签名的规范序列化与跨进程黄金

`hand-model-writer` 加 `--signatures`：解析 `--fixture` → `heroDecisionSignatures()` → 对该数组 `JSONEncoder([.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])` 输出。附录 A 的输出提交为黄金 `Tests/Fixtures/sample-ps-6max-nlhe.signatures.json`。跨进程测试复用 slice 1 的 `WriterBinary`：两进程各跑一次 `--signatures`，比对字节相等且等于黄金。`HeroDecisionSignature` 全 `Codable`，金额字段（`SpotSignature` 里已是枚举 `StackBucket`，无裸金额）无需额外单位命名。

## 决断 3：App 层匹配、选择与协调器

- `ImportedHandContentMatcher`（`Infrastructure/HandLab/`，仿 `SessionContentMatcher`）：对一个 `HeroDecisionSignature`，用 `signature.coverageKey` 找命中的已安装场景；命中则查该场景范围表对 `handClass` 所取 `action` 的权重（基点）→ `covered(scenarioID, weight)`；否则 `uncovered`。范围表权重查找复用 `StrategyContent`/`RangeBaseline` 既有通路（与 M2A `heroActionWeightBasisPoints` 同源）。
- `ImportedHandKeyNodeSelection`：
  - 节点 = `HeroDecisionSignature` + 其覆盖结果。
  - `deviation` 当且仅当 `covered` 且 `weight < 5000`（`偏离幅度 = 10000 − weight > 5000`）；`偏离幅度` 纯函数 `10000 − weight`（仅 covered 有）。
  - `allIn` 当 `isAllIn`。
  - 一节点可能既偏离又全下 → 取 `deviation`（学习信号优先，与 M2A「一节点一理由、deviation 最高」一致）。
  - 关键节点 = 理由为 deviation/allIn 的节点；排序：deviation 按偏离幅度降序，再 allIn；`min(5, 数量)`；可为空。
- `HandAnalysisCoordinator`（`Infrastructure/HandLab/`）：持有 `any TrainingEventStore`（**从不写**，仿 `HandImportCoordinator` 的注释与理由）+ 库存储 + matcher；`analyze(identity:) -> [KeyNode]`（读库中已采纳牌谱，产出关键节点与逐节点对照）。隔离断言因此是关于一条够得到事件存储的真实路径。
- **翻后一律 uncovered（评审加固）**：`ImportedHandContentMatcher.classify` 首行 `guard signature.street == .preflop else { return .uncovered }`，与 `SessionContentMatcher` 同款——本项目无翻后手牌分类法，不把翻后决策对着某个牌包的翻牌场景显示为"已审内容答案"。这使"翻后节点无内容可对照"成为结构性保证，不依赖当前随包内容恰为纯翻前。**后果**：真实一手最多约两个被覆盖的翻前偏离节点，故"6 个偏离 → 上界 5"这一属性在 `selectKeyNodes(...)` 函数层用手搭的 6 个 `.covered` 偏离节点断言（cap/排序是选择逻辑的性质，与 matcher 是否覆盖翻后无关），而非经真实翻后覆盖路由。

## 决断 4：`32o` 权重实现期核实

偏离成对用 `32o`（附录 G，BTN 开池）与附录 A 的 `AKo`。实现期读已发布 `rfi-btn` 范围核实 `32o` 权重为 0（预期——它是最弱的非同花手，BTN 开池约 41% 不含它）；若非 0，改选一个该范围确以 0 权重对待的手，并同步夹具。`AKo` 是任何 BTN RFI 范围的高权重加注手，权重远高于 5000。两者权重都从 pack 读出比较，不在规格里钉死具体基点。

## Capability 覆盖

| Capability | 落点 | 关键测试 |
|---|---|---|
| imported-hand-signatures | `HandHistory`：`heroDecisionSignatures()`、`hand-model-writer --signatures` | 附录 A 四节点逐街 facing/stackBucket、附录 F 面对加注、跨进程黄金 |
| imported-hand-analysis | App `Infrastructure/HandLab`：matcher、selection、coordinator | 命中/未命中/空内容成对、偏离幅度纯函数单调、32o vs AKo、全下入选、上界5/可为空、不产生 TrainingEvent |

## 影响与不变量

### 新增
- `HandHistory`：`HeroDecisionSignature`、`ObservedHand.heroDecisionSignatures()`、`hand-model-writer --signatures`、黄金 `sample-ps-6max-nlhe.signatures.json`、附录 F/G/H 及一个 6-偏离构造夹具。
- App：`Infrastructure/HandLab/{ImportedHandContentMatcher,ImportedHandKeyNodeSelection,HandAnalysisCoordinator}`、`Features/HandLab/` 分析视图、App 单测、UI 可达（复盘→牌谱→分析）。
- `scripts/verify-m2b.sh` 增签名黄金门禁与新测试。

### 必须不变
- `ObservedHand` 及其第一切片黄金 `sample-ps-6max-nlhe.model.json`（本切片只**新增** `heroDecisionSignatures()`，不改 `ObservedHand` 存储字段）。
- `SessionSimulation`（只经 `SpotCoverageKey` 概念与 `deviationWeightThresholdBasisPoints` 常量复用，不 import 其 `KeyHandSelection`）。
- `Contracts/…v1`、`CoreStrategyPack.json` 与各自 `.sha256`。

## 风险
- **重建 effectiveStack/facing 出错** → 附录 A 四节点逐街钉死、附录 F 钉死面对加注。
- **偏离退化** → 偏离幅度纯函数单独断言单调 + 32o/AKo 成对。
- **英雄识别依赖唯一 .known 座位** → 记其依赖 slice 1「对手明牌暂不读取」；将来读摊牌明牌时加显式英雄座字段。
- **范围表权重查找与 M2A 漂移** → 与 `SessionContentMatcher` 走同一 `RangeBaseline` 通路并各自测试。

## 测试策略
- 包测试 Swift Testing；App 单测 XCTest；UI 可达 XCUITest。
- 附录 A（已提交）+ F/G/H + 6-偏离构造夹具 + 签名黄金随包提交。
- 跨进程签名用 `hand-model-writer --signatures` 双进程比对。
- 每条依赖夹具的断言前置「夹具确实产出了东西」的自检。
