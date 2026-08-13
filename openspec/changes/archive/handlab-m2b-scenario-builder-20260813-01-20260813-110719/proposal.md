---
name: handlab-m2b-scenario-builder-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：M2B 个人牌局实验室（第四切片：手动场景构建器）

## Why

前三切片处理**导入的真实牌**：导入→冲突预览→分析→补救。M2B 路线图还有一项——**手动场景构建器**：让用户不必打过某手，也能直接手搭一个翻前决策局面（"我在 BTN 拿 A5s 未面对下注该怎么打？"），看已安装内容怎么说，并据此训练。把"看清并练习漏洞"从"等它在真实牌里出现"扩展到"主动构造想研究的局面"。

关键原则（沿用全项目）：**用户手搭的 spot 没有策略真值**——除非命中已审核内容，否则系统只呈现它、绝不为它编造频率/EV、也不给它评分。命中内容时，对照与补救都借用既有已审核内容的真值。

## 复用与两处必要的加法（据审需修正）

- 复用 `PokerCore.SpotSignature`/`HandClass`/`TablePosition`/`FacingAction`/`StackBucket` 据算签名（纯扑克事实）；第二切片 `ImportedHandContentMatcher` 判覆盖；第三切片补救训练（从 `scenarioID` 起既有训练管线）；仿 `FileHandLibraryStore` 的版本化存储。
- **加法 1**：`ImportedHandContentMatcher` 现只接 `HeroDecisionSignature`。抽出核心 `classify(signature: SpotSignature, action: DecisionAction) -> NodeCoverage`，既有的 `HeroDecisionSignature` 版转调它。构造 spot 直接用 `(SpotSignature, DecisionAction)` 判覆盖。加法，不改既有行为。
- **加法 2**：`ConstructedSpot` 的合法性由它自己负责——审需查明 PokerCore **不**拒绝重复牌与非正筹码（`HandClass(Ah,Ah)` 静默得 `AA`；`BBAmount(centiBB:0)` 不报错），只有座位越界由 `TablePosition.init` 抛错。故 `ConstructedSpot` 必须自校验"两张牌互不相同且可解析、有效筹码为正"，座位越界借 `TablePosition`。它还实现 `Codable` + 确定性规范编码 + 以规范编码的 SHA-256 为身份，供版本化存储。

## What Changes

### New Capabilities

- `manual-scenario-builder` — 用户手动构造一个翻前决策 spot；系统据此确定性形成 `SpotSignature`、判定已安装内容覆盖并给对照（命中查范围表权重，未命中记 `NodeCoverage.uncovered`、绝不编造）、命中时可在覆盖场景上发起补救训练；构造的 spot 作为版本化个人资源本地保存，可查看与删除。构造与保存本身不产生 `TrainingEvent`。

### Modified Capabilities

无。抽出 matcher 核心是加法（既有入口转调）；不改 `SpotSignature`/matcher 判定/补救/训练管线的语义。

### Removed Capabilities

无。

## 术语

- **构造 spot（`ConstructedSpot`）**：用户提供的翻前决策局面：`heroSeatOffsetFromButton`、两张英雄底牌、`FacingAction`、有效筹码（centi-BB）、英雄拟采取的 `DecisionAction`。`SpotSignature` 据此算出（`street == .preflop`）。
- **合法 spot**：两张底牌可解析且互不相同；`heroSeatOffsetFromButton` 在 `0..<tableSize`（tableSize 固定 6）；有效筹码为正。非法输入以**各自明确的、可判等的原因**被拒，不产出被猜测的 spot。
- **无内容可对照**：`SpotCoverageKey` 未命中任何已安装场景，判定为 `NodeCoverage.uncovered`——只呈现构造，不显示任何频率/EV。

## Capabilities Detail

### Capability: manual-scenario-builder

#### Requirement: 从用户输入确定性地构造合法 spot 与其签名

The system SHALL build a `SpotSignature` from a user-provided preflop spot (hero seat offset, two hole cards, facing action, effective stack), deterministically, and SHALL reject an illegal spot with a specific, equatable reason per illegality rather than fabricating one.

##### Scenario: 两个不同的合法构造得到各自据算的签名

- GIVEN 构造甲：offset 0、底牌 `Ah 5h`、未面对下注、筹码 10,000；构造乙：offset 5、底牌 `7c 2d`、面对一次加注、筹码 1,600
- WHEN 各自形成签名
- THEN 甲的签名 `handClass == HandClass(Card(code:"Ah")!, Card(code:"5h")!)`（`A5s`）、`heroSeatOffsetFromButton == 0`、`facing == FacingAction(priorRaiseCount: 0)`、`stackBucket == StackBucket(effectiveStack: BBAmount(centiBB: 10_000))`
- AND 乙的签名 `handClass == HandClass(Card(code:"7c")!, Card(code:"2d")!)`（`72o`）、`heroSeatOffsetFromButton == 5`、`facing == FacingAction(priorRaiseCount: 1)`、`stackBucket == StackBucket(effectiveStack: BBAmount(centiBB: 1_600))`
- AND 甲乙签名在 handClass、offset、facing、stackBucket 上均不相同（排除"恒返回同一签名"的实现）；且同一构造两次形成的签名逐字段相等（确定性）

##### Scenario: 每种非法构造以各自明确原因被拒

- GIVEN 四个非法构造：重复底牌 `Ah Ah`；无法解析的牌（如 `"Zx"`）；座位偏移 6（越出 tableSize 6）；有效筹码 0
- WHEN 尝试各自形成 spot
- THEN 四者分别以可判等的不同原因失败（重复牌 / 无法解析 / 座位越界 / 筹码非正），彼此不相等
- AND 不产出任何被猜测或被默认的 spot 或签名

#### Requirement: 命中内容给对照与补救，未命中记 uncovered、不编造、不评分

The system SHALL classify a constructed spot as covered or uncovered by installed content via the same `SpotCoverageKey` path, present the content's basis-point weight for the hero's action on a covered spot (taken from the covering scenario's range table) and offer a remediation drill on that covering scenario, and SHALL classify an uncovered spot as `NodeCoverage.uncovered` — never fabricating a weight and never scoring a spot with no covering content.

##### Scenario: 命中内容的构造 spot 给出范围表权重并可补救

- GIVEN 一个命中场景 S 的构造 spot（用 `HandLabContentFixture` 构造覆盖该 (位置,面对,筹码) 且对该 `handClass`+行动权重为非整值 `6234` 基点的内容）
- WHEN 分析该 spot
- THEN 判定为 `NodeCoverage.covered(scenarioID: S, weightBasisPoints: 6234)`，且该权重等于对 S 的范围表按 `handClass`+行动查得（`scenario.rangeWeightBasisPoints(...)`），非编造的整值
- AND 该 spot 可在场景 S 上发起补救训练（`scenarioID` 相同）

##### Scenario: 未命中内容的构造 spot 记 uncovered、不编造、不评分

- GIVEN 一个未被任何已安装内容覆盖的构造 spot（内容为空）
- WHEN 分析该 spot
- THEN 判定为 `NodeCoverage.uncovered`，不显示任何频率或 EV
- AND 不提供补救训练（无覆盖场景可练）；与上一场景成对，排除"恒 covered / 恒 uncovered"的实现

#### Requirement: 构造 spot 版本化保存，保存不产生事件

The system SHALL store a constructed spot as a versioned personal resource — retrievable, deletable, with re-saving the same spot keeping the prior version byte-for-byte — and building or saving SHALL NOT produce any `TrainingEvent`.

##### Scenario: 保存可取回、重存保留旧版本字节、删除不影响其余

- GIVEN 用户保存了构造 spot 甲与身份不同的构造 spot 乙
- WHEN 取回甲；在第二次保存甲之前记下其版本 1 的规范编码字节，再次保存甲后比对；随后删除甲
- THEN 取回的甲与保存者逐字段相等；再次保存后甲的版本为 `[1, 2]`，且版本 1 的规范编码字节与记下的完全相同（未被就地改写）
- AND 删除甲后库中恰剩乙、其内容逐字段不变，甲及其各版本移除

##### Scenario: 构造与保存不产生 TrainingEvent

- GIVEN 一条持有非空训练事件存储（before.count ≥ 1）的构造/保存路径
- WHEN 用户构造并保存一个 spot，但不发起补救训练
- THEN 训练事件存储的条数与内容不变（after == before）
- AND 只有用户在命中 spot 上发起并完成补救训练才 +1（复用第三切片，事件为普通训练事件）

## Impact

- **Code:** 新增 `ConstructedSpot`（`HandHistory`，只依赖 PokerCore；据算 `SpotSignature`、自校验重复牌/可解析/正筹码、`Codable`+规范编码+身份）及其版本化存储 `FileConstructedSpotStore`（`HandHistoryPersistence`，仿 `FileHandLibraryStore`）。`ImportedHandContentMatcher` 抽出 `classify(signature:action:)` 核心（加法）。App 层 `Features/HandLab` 新增构造界面与结果视图，复用覆盖判定与第三切片补救入口。
- **Interfaces:** 复盘→Hand Lab 增"构造场景"入口；无服务端接口变更。
- **Dependencies:** 复用 `PokerCore`/`StrategyContent`/既有训练与补救；无第三方。

## Risks

- **为无真值的 spot 编造频率/评分** → 未命中一律 `uncovered`、不评分；命中才用已审核真值；covered/uncovered 成对且 covered 权重钉到范围表非整值。
- **构造被静默猜测** → `ConstructedSpot` 自校验（PokerCore 不管重复牌/非正筹码），四类非法各返回可判等的不同原因。
- **恒返回同一签名** → 两个不同合法构造断言不同的据算签名。
- **重存就地改写旧版本 / 删除误伤** → 捕获 v1 字节比对、双 spot 删除断言，仿已验证的 `FileHandLibraryStore` 测试。
- **保存路径误产生事件** → 非空存储下构造/保存不 +1，只有完成补救才 +1。

## Non-Goals

- 翻后构造（内容只有翻前）；分支重放/反事实（第五切片）；漏洞标签聚合。
- 为用户 spot 生成/声明策略真值；对无覆盖 spot 评分；新事件字段或契约变更。
- 校验用户所选行动的下注合法性（本切片只据 facing/stack 算签名并按行动查表；行动无范围表动词者归 uncovered）。

## Acceptance Criteria

1. 两个不同合法构造算出各自正确且互不相同的 `SpotSignature`，确定性一致；四类非法构造各以可判等的不同原因被拒、不产出猜测。
2. 命中 spot 判定 `covered(S, 6234)` 且权重等于 S 范围表查得（非整值），可在 S 上补救；未命中判定 `uncovered`、不显频率、不训练、不评分（成对）。
3. 构造 spot 版本化保存：可取回、重存后版本 1 字节不变、删除不影响其余；构造/保存不产生 `TrainingEvent`，只有完成补救才 +1。
4. 分层不破坏：`ConstructedSpot`→`HandHistory`、其存储→`HandHistoryPersistence`（脚本已覆盖）；matcher 核心抽取是加法；对照/补救在 App 层；不改 `SpotSignature`/matcher/训练管线/契约语义。
