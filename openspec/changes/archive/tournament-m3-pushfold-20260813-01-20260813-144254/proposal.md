---
name: tournament-m3-pushfold-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：短筹码 Push/Fold 决策上下文（引擎，范围留作内容）

## Why

锦标赛短筹码的实战决策常被简化为「全下或弃牌」（jam-or-fold）。要为将来接入
（经审核的）push/fold 范围留出地基，先需要一个**内容无关**的决策上下文：它精确回答
「以某个有效深度阈值衡量，此刻算不算短筹码 push/fold 局面」，并给出这个简化模型下的
两个候选动作，但**不主张**哪些手该全下、也不主张这个简化在任何深度是最优或穷尽合法。

三条边界必须钉死，否则就把策略真值编进了引擎：

1. **不是合法性断言**。「短筹码只有全下/弃牌」在扑克规则上是**假**的——跛入、最小加注
   都合法（现金侧 `BettingDecisionContext.legalActions()` 已正确返回更宽的合法集）。
   jam-or-fold 是调用方**选用的简化模型**，本切片如实披露为「模型的两个候选」，不冒充
   合法动作全集。
2. **不编造阈值**。「10bb 以下才 push/fold」是策略启发式，不是事实。阈值一律由调用方
   传入；引擎只做精确算术，不内置也不背书任何阈值。
3. **不编造范围**。「该 jam 哪些手」是策略真值，需真实来源与人工审核，留作内容，本切片
   结构上不含 range 字段/评分 API。

另外，现金侧 `BettingDecisionContext`/`DecisionAction` 是 **centi-BB（现金单位，1BB=100）**
denominated；锦标赛筹码不整除 BB，强行塞进 centi-BB 会 floor 丢精度，违反精确数据铁律。
故本切片**有意不复用**这两个现金类型，改用**筹码计（`Int`）的锦标赛原生**上下文
（这修正了任务初拟时「复用 BettingDecisionContext」的设想——当时尚未发现其现金单位耦合）。

## What Changes

### New Capabilities

- `tournament-pushfold` — 筹码计的短筹码 push/fold 决策上下文：按调用方传入的 BB 阈值
  精确判定是否处于该深度（整数比较，无 floor 损失），并给出 jam-or-fold 简化模型的两个
  候选动作（全下=提交全部有效筹码 / 弃牌）；含非法输入的可判等校验与阈值溢出保护。
  不含范围、不评分。

### Modified Capabilities

无。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-pushfold

`TournamentEngine` 包（只依赖 PokerCore）新增：

- **`PushFoldOption`**：`Hashable, Sendable`，两个 case `fold` 与 `jam(toChips: Int)`
  （全下提交的筹码，即全部有效筹码）。锦标赛原生、筹码计，不用 `BBAmount`。
- **`PushFoldError`**：`Error, Equatable, Sendable`，含 `nonPositiveEffectiveStack`、
  `nonPositiveBigBlind`、`negativeThreshold`、`thresholdOverflow` 四个可判等 case。
- **`PushFoldContext`**：`Hashable, Sendable`，持有 `effectiveChips: Int` 与
  `level: BlindLevel`。throwing `init` 校验 `effectiveChips > 0`、`level.bigBlindChips > 0`
  （`BlindLevel` 单行无自校验，直接构造可能为 0，是 `effectiveBigBlinds` 除零来源）。
  - `effectiveBigBlinds: Int`：复用 slice-1 的 `effectiveBigBlinds(chips:atLevel:)`
    （向下取整），供展示。
  - `isAtOrBelow(thresholdBigBlinds:) throws -> Bool`：**精确**判定
    `effectiveChips <= thresholdBigBlinds × level.bigBlindChips`（整数比较，含等号边界，
    无 floor 损失）；`thresholdBigBlinds < 0` 抛 `negativeThreshold`；
    `thresholdBigBlinds × bigBlindChips` 溢出抛 `thresholdOverflow`。
  - `options() -> [PushFoldOption]`：返回 `[.fold, .jam(toChips: effectiveChips)]`——
    该简化模型的两个候选（披露式，不主张合法穷尽或最优）。**与深度无关**（不看阈值）：
    它只是模型的动作集，不是推荐，也不是合法集；调用方应以 `isAtOrBelow` 决定是否
    呈现，并且 `.fold` 假定英雄面对下注（免费过牌时弃牌无意义，不在本切片建模）。

#### Requirement: 有效深度的精确阈值判定

The system SHALL classify a short-stack push/fold spot by a caller-supplied big-blind
threshold using exact integer arithmetic (no floor loss), and SHALL expose the floored
effective depth for display, without endorsing any particular threshold.

##### Scenario: 阈值判定精确且含等号边界

- GIVEN 有效筹码 `850`、级别 BB=`100`
- WHEN 分别以阈值 `10`、`8` 判定 `isAtOrBelow`
- THEN 阈值 `10` → `true`（`850 <= 1000`），阈值 `8` → `false`（`850 > 800`）
- AND 展示用 `effectiveBigBlinds` 为 `8`（`850 / 100` 向下取整）

##### Scenario: 等号边界计入（≤ 而非 <）

- GIVEN 有效筹码 `800`、级别 BB=`100`
- WHEN 以阈值 `8` 判定 `isAtOrBelow`
- THEN 结果为 `true`（`800 <= 800`，边界含等号；这是整数精确比较而非 floor 后再比）

##### Scenario: 负阈值与阈值溢出被分别拒绝

- GIVEN 合法上下文（有效筹码 `1000`、BB=`100`）
- WHEN 以阈值 `-1` 判定 → 抛 `PushFoldError.negativeThreshold`
- AND 以阈值 `Int.max`（`Int.max × 100` 溢出）判定 → 抛 `PushFoldError.thresholdOverflow`
- AND 以合法阈值 `10` 判定能返回布尔（配对成功，防门禁永假）

#### Requirement: Jam-or-fold 简化动作模型（内容无关）

The system SHALL present exactly the two options of the disclosed jam-or-fold model —
fold, or jam committing the entire effective stack — as a caller-opted modeling
restriction, and SHALL NOT assert which holdings jam, score any action, or claim the
model is legally exhaustive or optimal.

##### Scenario: 候选动作为弃牌与全下全部有效筹码

- GIVEN 有效筹码 `1200`、级别 BB=`100`
- WHEN 取 `options()`
- THEN 恰为 `[.fold, .jam(toChips: 1200)]`（全下提交全部有效筹码 `1200`）
- AND 与传入阈值无关（不同深度返回同一动作集，证明它是模型动作集而非深度相关推荐）

#### Requirement: 输入校验

The system SHALL reject an ill-formed context on construction with distinct equatable
errors.

##### Scenario: 非正有效筹码与非正大盲被分别拒绝

- GIVEN 有效筹码 `0` 或负数（其余合法）→ 构造抛 `PushFoldError.nonPositiveEffectiveStack`
- AND 级别 `bigBlindChips == 0`（其余合法）→ 构造抛 `PushFoldError.nonPositiveBigBlind`
- WHEN 各自单独违规构造
- THEN 两种错误可判等且互不相同；各自去掉该违规后能成功构造

## Impact

- **Code:** `Packages/TournamentEngine/Sources/TournamentEngine/`（新增
  `PushFoldContext.swift`、`PushFoldOption.swift`、`PushFoldError.swift`）；测试位于
  `Packages/TournamentEngine/Tests/`。
- **Interfaces:** 纯 Swift API，无 UI/网络/存储变更；不入 App target。
- **Dependencies:** 仅 PokerCore（复用 slice-1 `effectiveBigBlinds` 与 `BlindLevel`）；
  `check-package-layering.sh` 现有门禁按目录 glob 自动覆盖。

## Risks

- **把简化模型误当合法/最优**：→ 类型名与文档明确「披露式简化模型的两个候选」，不叫
  legalActions、不评分；现金侧真实合法集仍在 `BettingDecisionContext`。
- **把阈值误当事实**：→ 阈值一律调用方传入，引擎不内置不背书。
- **精度损失**：→ 阈值判定用整数比较 `chips ≤ threshold×BB`（精确），不走 floor 后的
  `effectiveBigBlinds`；`effectiveBigBlinds` 仅供展示。阈值×BB 溢出报错不静默。

## Non-Goals

- 不做 push/fold **范围**（该 jam/该 call 哪些手 = 策略真值，需真实来源与人工审核）。
- 不背书任何具体阈值；不做 jam EV/ICM 压力下的开牌评分。
- 不按（位置, 面对情形, 深度）做范围查表——留待内容切片。
- 不复用现金 `BettingDecisionContext`/`DecisionAction`（centi-BB 会 floor 丢精度）。

## Acceptance Criteria

1. `swift test --package-path Packages/TournamentEngine` 全绿，含上述所有 Scenario。
2. `850` chips @ BB`100`：阈值 `10`→`true`、`8`→`false`；`effectiveBigBlinds==8`。
3. 等号边界：`800` chips @ BB`100`、阈值 `8` → `true`。
4. `options()` 恰 `[.fold, .jam(toChips: effectiveChips)]`，无 range/评分 API。
5. 四种非法输入（nonPositiveEffectiveStack/nonPositiveBigBlind/negativeThreshold/
   thresholdOverflow）各以**不同且可判等**的 `PushFoldError` 被拒，各配「去掉违规后成功」。
6. `bash scripts/check-package-layering.sh` 通过：只依赖 PokerCore。
