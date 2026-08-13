---
name: tournament-m3-structure-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：M3 锦标赛扩展（第一切片：盲注结构与筹码模型）

## Why

M3 把训练从现金局扩到锦标赛。锦标赛与现金的根本差别是**盲注/ante 随级别上升、筹码是绝对值、深度以"当前大盲的倍数"衡量**——这套结构是 M3 一切（push/fold 阈值、ICM、泡沫期）的地基。本切片只建这套**内容无关的结构**：盲注/ante 级别表与递进、锦标赛整数筹码模型、以及"相对当前大盲的有效深度"。push/fold 与 ICM 的**策略内容**不能编造（需真实来源与人工审核），留待后续切片与你提供的内容。

与路线图一致：M3 是"锦标赛扩展：短码、赛事路线、泡沫期和 ICM"（`docs/product/scope-and-milestones.md` 的 M3 行）；CLAUDE.md 关于 M3 的既有约定是位置表示的跨切片复用（`SolverAssumptions.tableSize` + `heroSeatOffsetFromButton`）。本切片只新增锦标赛专属结构（盲注级别、筹码），不引入位置、不碰现金局、不改历史评分。

## 为什么不用 `BBAmount`（现金的 centi-BB）

现金局大盲固定，故 `BBAmount`（centi-BB）能既表金额又表深度。锦标赛**大盲逐级上升**：同样的筹码在不同级别是不同的 BB 深度。因此锦标赛筹码是**绝对整数筹码**（`chips: Int`），与 `BBAmount` 分开；"有效深度（大盲数）"由 `筹码 ÷ 当前大盲` 据算。混用会让"深度"变成一个随级别漂移的伪金额。这条与精确数据规则一致：筹码是整数真值，深度是据算量。

## What Changes

### New Capabilities

- `tournament-structure` — 锦标赛盲注/ante 级别表与递进（级别校验、按手数取当前级别）、整数筹码模型、以及相对当前大盲的有效深度据算。纯整数、内容无关，落新包 `TournamentEngine`（只依赖 PokerCore）。

### Modified Capabilities

无。新增锦标赛专属状态，不改现金局的任何能力或评分。

### Removed Capabilities

无。

## 术语

- **`BlindLevel`**：一个级别的结构：`level`（1 起）、`smallBlindChips`、`bigBlindChips`、`anteChips`，均为整数筹码、非负、`bigBlindChips > 0`。
- **`BlindSchedule`**：有序的 `[BlindLevel]`，非空；`level` 从 1 连续递增；`bigBlindChips` 逐级**严格递增**（盲注只升不降）；`smallBlindChips ≤ bigBlindChips`；`anteChips ≥ 0`。非法结构以明确、可判等的原因被拒。
- **当前级别**：锦标赛按固定手数升盲——`level(atHandIndex:handsPerLevel:)` 返回第 `(handIndex / handsPerLevel)` 个级别（0 起的手序映射到 1 起的级别），超出最后一个级别则停在最后一个级别（不再升）。`handIndex ≥ 0`、`handsPerLevel ≥ 1` 是被守卫的前置条件（precondition，仿 M2A `TableRules.buttonSeat` 对 handIndex 的守卫），从而 `handIndex / handsPerLevel` 不会除零。
- **有效深度（大盲数）**：`effectiveBigBlinds(chips:atLevel:) = chips / bigBlindChips`（整数除，向下取整），一个据算量，不作为存储真值。同样筹码在更高级别得到更小的 BB 深度。

## Capabilities Detail

### Capability: tournament-structure

#### Requirement: 盲注级别表被校验且按手数递进

The system SHALL accept a blind schedule only when its levels are sequentially numbered from 1, its big blinds strictly increase level over level, its small blind never exceeds its big blind, and its antes are non-negative; it SHALL reject any other schedule with a specific, equatable reason; and it SHALL map a hand index to the current level by a fixed hands-per-level cadence, clamping at the final level.

##### Scenario: 合法递进结构被接受并可按手数取级别（含两处级别边界）

- GIVEN 一个三级结构：L1 (SB50/BB100/ante0)、L2 (SB75/BB150/ante0)、L3 (SB100/BB200/ante25)，每级 10 手
- WHEN 构造 `BlindSchedule` 并查手序 0、9、10、19、20、100 的当前级别
- THEN 结构被接受
- AND 手 0 与 9 → L1、手 10 → L2（L1/L2 边界）、手 19 → L2、手 20 → L3（L2/L3 边界）、手 100（超出）→ 停在 L3（不越界、不再升）

##### Scenario: 各类非法结构以各自原因被拒

- GIVEN 七个非法结构：空级别列表；级别号不从 1 开始（首级为 2）；级别号不连续（1,3）；大盲未严格递增（BB100 后又 BB100）；某级 SB 大于 BB；某级 `bigBlindChips == 0`；某级 `anteChips < 0`
- WHEN 尝试构造 `BlindSchedule`
- THEN 各以可判等的不同原因失败（空 / 未从 1 开始 / 级别号不连续 / 大盲未递增 / 小盲超大盲 / 大盲为零 / ante 为负），两两不相等
- AND 不产出任何被默认修正过的结构（尤其 `bigBlindChips == 0` 必须被拒，因为它正是有效深度除法的除零来源）

#### Requirement: 锦标赛筹码为整数，有效深度随级别据算

The system SHALL represent tournament stacks as non-negative integer chips (never as `BBAmount`), and SHALL derive a stack's effective depth in big blinds as integer chips divided by the level's big blind (floored), so the same chip count yields a smaller depth at a higher level.

##### Scenario: 同样筹码在更高级别得到更小的有效深度

- GIVEN 3000 筹码
- WHEN 在 L1（BB100）与 L3（BB200）分别求有效深度
- THEN L1 得 30 BB、L3 得 15 BB（`chips / bigBlindChips` 向下取整）
- AND 深度是据算量：模型里存的是整数筹码 3000，不存 BB 深度、不存任何浮点

##### Scenario: 有效深度向下取整且非负

- GIVEN 250 筹码在 BB100
- WHEN 求有效深度
- THEN 得 2 BB（250/100 向下取整），不是 2.5，也不四舍五入为 3
- AND 0 筹码得 0 BB（下界样例；`chips` 非负、`bigBlindChips > 0` 已由类型/校验保证，故深度结构性非负，无需再以负深度断言测不可达输入）

## Impact

- **Code:** 新增包 `TournamentEngine`（只依赖 PokerCore）：`BlindLevel`、`BlindSchedule`（校验 + `level(atHandIndex:handsPerLevel:)`）、`TournamentChips`/有效深度据算（`effectiveBigBlinds(chips:atLevel:)`）。`scripts/check-package-layering.sh` 增一条 `TournamentEngine may only see PokerCore`（仿 HandHistory 的 `check_manifest`/`check_imports`）；并更新 `docs/architecture/layering.md` 的层图与依赖清单纳入 `TournamentEngine`（文档与门禁同步）。
- **Interfaces:** 无 UI、无服务端变更（本切片是引擎结构，尚无可玩赛事——赛事推进需对手打法=内容，推后）。
- **Dependencies:** 只依赖 `PokerCore`；无第三方；不依赖 `SessionSimulation`（现金引擎）与 `StrategyContent`（内容）。

## Risks

- **把锦标赛筹码塞进 `BBAmount`** → 明确用整数 `chips`，深度据算；断言"同筹码不同级别深度不同"，混用会让该断言无意义。
- **升盲边界差一** → 手序→级别的边界（手 9→L1、手 10→L2）与超界 clamp 逐个钉死。
- **非法结构被静默修正** → 四类非法各返回可判等的不同原因，不默认修补。
- **有效深度用浮点/四舍五入** → 整数除向下取整，250/100→2 而非 2.5/3，钉死。

## Non-Goals

- push/fold 与 ICM 的**策略内容/范围**——策略真值，不能编造，留待你提供来源与审核。
- 可玩的赛事推进（发牌打完一手、对手决策）——对手打法需范围=内容；本切片只做结构与筹码。
- ICM 计算器（下一切片，含精确有理/整数表示的设计）；泡沫期/决赛桌状态。
- 改动现金局（`SessionSimulation`）或历史评分。

## Acceptance Criteria

1. 合法递进结构被接受、按固定手数取当前级别并在末级 clamp；四类非法结构各以可判等的不同原因被拒、不静默修正。
2. 锦标赛筹码为非负整数 `chips`（非 `BBAmount`）；有效深度 = `chips / bigBlindChips` 向下取整，同筹码在更高级别更小、0 筹码为 0、无负、无浮点。
3. 分层不破坏：`TournamentEngine` 只依赖 PokerCore 并被 `check-package-layering.sh` 显式覆盖；不依赖 `SessionSimulation`/`StrategyContent`；不改现金局与历史评分。
