# Capability: tournament-structure

## Requirement: 盲注级别表被校验且按手数递进

The system SHALL accept a blind schedule only when its levels are sequentially numbered from 1, its big blinds strictly increase level over level, its small blind never exceeds its big blind, and its antes are non-negative; it SHALL reject any other schedule with a specific, equatable reason; and it SHALL map a hand index to the current level by a fixed hands-per-level cadence, clamping at the final level.

### Scenario: 合法递进结构被接受并可按手数取级别（含两处级别边界）

- GIVEN 一个三级结构：L1 (SB50/BB100/ante0)、L2 (SB75/BB150/ante0)、L3 (SB100/BB200/ante25)，每级 10 手
- WHEN 构造 `BlindSchedule` 并查手序 0、9、10、19、20、100 的当前级别
- THEN 结构被接受
- AND 手 0 与 9 → L1、手 10 → L2（L1/L2 边界）、手 19 → L2、手 20 → L3（L2/L3 边界）、手 100（超出）→ 停在 L3（不越界、不再升）

### Scenario: 各类非法结构以各自原因被拒

- GIVEN 七个非法结构：空级别列表；级别号不从 1 开始（首级为 2）；级别号不连续（1,3）；大盲未严格递增（BB100 后又 BB100）；某级 SB 大于 BB；某级 `bigBlindChips == 0`；某级 `anteChips < 0`
- WHEN 尝试构造 `BlindSchedule`
- THEN 各以可判等的不同原因失败（空 / 未从 1 开始 / 级别号不连续 / 大盲未递增 / 小盲超大盲 / 大盲为零 / ante 为负），两两不相等
- AND 不产出任何被默认修正过的结构（尤其 `bigBlindChips == 0` 必须被拒，因为它正是有效深度除法的除零来源）

## Requirement: 锦标赛筹码为整数，有效深度随级别据算

The system SHALL represent tournament stacks as non-negative integer chips (never as `BBAmount`), and SHALL derive a stack's effective depth in big blinds as integer chips divided by the level's big blind (floored), so the same chip count yields a smaller depth at a higher level.

### Scenario: 同样筹码在更高级别得到更小的有效深度

- GIVEN 3000 筹码
- WHEN 在 L1（BB100）与 L3（BB200）分别求有效深度
- THEN L1 得 30 BB、L3 得 15 BB（`chips / bigBlindChips` 向下取整）
- AND 深度是据算量：模型里存的是整数筹码 3000，不存 BB 深度、不存任何浮点

### Scenario: 有效深度向下取整且非负

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
