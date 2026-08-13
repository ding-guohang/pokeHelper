---
name: tournament-m3-icm-calc-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：锦标赛 ICM 计算器工具面（复盘下，内容无关）

## Why

M3 锦标赛引擎的内容无关地基已建完（结构、ICM 权益、push/fold 上下文、泡沫系数），
但全都还只是包里的纯函数，用户看不到。可玩的锦标赛**训练**要等经审核的策略内容
（范围/打法），是硬阻塞；但引擎里已有的**纯数学**可以先做成一个用户可见的分析工具
——「锦标赛 ICM 计算器」：输入各家筹码与派彩结构，算出每家的 ICM 权益，并可选算某对
座位间的泡沫系数。这是描述性计算器，不推荐打法、不含范围，符合「不编造策略真值」，
也让职业向用户先用上真实有用的 ICM 工具（产品最高宗旨）。

它作为**复盘时的工具**嵌在「复盘」标签下（仿牌局实验室），**不动**四个核心标签
（今日/学习/训练/复盘）。精确 `Fraction` 全程保真，**只在展示层**用整数长除法转小数
（不引入 `Double`/`NumberFormatter`，沿用 `StrategyNumberText` 的「整数一次性成文本」纪律）。

## What Changes

### New Capabilities

- `tournament-icm-calculator` — 复盘下可达的 ICM 计算器：把用户输入（各家筹码、派彩、
  可选的 hero/opp 座位）解析为整数，调用引擎 `ICMCalculator.equities` 与
  `ICMPressure.bubbleFactor`，把结果 `Fraction` 在展示层用整数长除法转定点小数呈现；
  非法输入映射为可读中文错误，绝不静默出错或编造。

### Modified Capabilities

无（`adaptive-native-shell` 的四个核心标签不变，`AdaptiveNavigationTests` 仍断言
`[今日,学习,训练,复盘]`；本工具是复盘下的入口，不新增主标签）。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-icm-calculator

- **工程接线**：`project.yml` 的 `packages:` 与 `PokerCoach` target `dependencies:`
  各加 `TournamentEngine`；`xcodegen generate` 重生成。App 首次 `import TournamentEngine`。
- **展示层精确转换**（新，纯整数、无浮点）：`TournamentICMPresentation.decimalString(
  _ fraction: Fraction, places: Int) -> String`——用逐位整数长除法（`magnitude` 运算避免
  `Int.min` 与溢出）产出四舍五入到 `places` 位的定点小数字符串（含进位传播与符号）。
  这是 `Fraction` 唯一转小数的地方，符合「浮点只用于展示、且只成文本一次」。
- **ViewModel**：`@MainActor @Observable final class TournamentICMViewModel`，持
  `stacksInput`/`payoutsInput`/`heroSeat`/`opponentSeat` 输入与 `private(set)` 结果/错误
  状态；`compute()` 解析输入（逗号分隔整数）→ 调 `ICMCalculator.equities`（必要时
  `ICMPressure.bubbleFactor`）→ 结果转字符串或把抛出的 `ICMError`/解析错误映射为中文。
- **View**：`TournamentICMView`，两处文本输入（筹码、派彩）+ 计算按钮（复用
  `ActionButton`）+ 结果列表（每家权益）+ 可选泡沫系数 + 错误行；leaf `Text/Button` 带
  `icm.*` accessibility id。
- **入口**：`ReviewView` 在 `handLabEntry` 旁加 `NavigationLink`（id `review.tournamentICM`）。

#### Requirement: 复盘下可达并算出精确 ICM 权益（展示为定点小数）

The system SHALL, from within the 复盘 tab, let the user enter chip stacks and a payout
structure and display each seat's ICM equity as a fixed-point decimal derived from the
exact `Fraction` by integer arithmetic only.

##### Scenario: 输入等筹码与阶梯派彩得到各家权益

- GIVEN 在复盘下打开锦标赛 ICM 计算器，筹码输入 `1000,1000,1000`、派彩输入 `5000,3000,2000`
- WHEN 点计算
- THEN 三家权益各显示为 `3333.33`（`10000/3` 四舍五入到两位，整数长除法所得，非浮点）
- AND 页面经「复盘」标签（iPhone）或侧栏（iPad）→ `review.tournamentICM` 可达

##### Scenario: 展示层小数转换精确且四舍五入（单元级）

- GIVEN `Fraction(10000, 3)`
- WHEN `TournamentICMPresentation.decimalString(_, places: 2)`
- THEN 得 `"3333.33"`
- AND `Fraction(2, 3)` places 2 → `"0.67"`（进位四舍五入）、`Fraction(1, 1)` places 2 → `"1.00"`、
  `Fraction(-4, 3)` places 2 → `"-1.33"`（符号保留）

#### Requirement: 可选泡沫系数

The system SHALL, when the user supplies a hero seat and a distinct opponent seat,
display the bubble factor between them as a fixed-point decimal, and otherwise show
only per-seat equities.

##### Scenario: 选定 hero/opp 显示泡沫系数

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`、hero=`0`、opp=`1`
- WHEN 点计算
- THEN 显示泡沫系数 `1.33`（`4/3` 两位）
- AND 各家权益仍同时显示

#### Requirement: 非法输入映射为可读错误，绝不静默或编造

The system SHALL map malformed input and every engine error to a readable message and
show no numeric result in that case, never crashing or fabricating a value.

##### Scenario: 非整数/空筹码输入报解析错误

- GIVEN 筹码输入 `1000,abc`（含非整数）
- WHEN 点计算
- THEN 显示解析错误（`icm.error`），不显示任何权益数字

##### Scenario: 引擎错误被映射（名次多于座位 / 平坦无增益）

- GIVEN 筹码 `1000,1000`、派彩 `100,60,40`（名次多于座位）
- WHEN 点计算
- THEN 显示对应中文错误（源自 `ICMError.morePayoutsThanPlayers`），无权益数字
- AND 泡沫系数选定平坦派彩 `300,300,300` 时显示无增益错误（源自 `noEquityGain`）

## Impact

- **Code:** 新增 `PokerCoach/Features/TournamentICM/`（`TournamentICMView.swift`、
  `TournamentICMViewModel.swift`、`TournamentICMPresentation.swift`）；改
  `PokerCoach/Features/Review/ReviewView.swift`（加入口）、`project.yml`（加依赖）；
  新增 `PokerCoachUITests/TournamentICMSurfaceTests.swift`。
- **Interfaces:** 复盘下多一个工具入口；无网络/存储/契约变更；不产生 `TrainingEvent`。
- **Dependencies:** App 首次依赖 `TournamentEngine`（只依赖 PokerCore，层次合法）。

## Risks

- **展示层混入浮点**：→ `decimalString` 全整数长除法（`magnitude` 防溢出/`Int.min`），
  单元测试钉死 `3333.33`/`0.67`/`1.00`/`-1.33`；不使用 `Double`/`NumberFormatter`。
- **被误当训练/策略**：→ 明确是「计算器/分析工具」，无评分、无范围、无打法推荐；不产生
  训练事件；文案中性。
- **改动波及四标签**：→ 只在 `ReviewView` 加 `NavigationLink`，不碰 `AppDestination`；
  `AdaptiveNavigationTests` 继续断言四标签。
- **xcodegen 未重生成**：→ 提交前 `xcodegen generate`，UI 测试在 iPhone/iPad 模拟器跑通。

## Non-Goals

- 不做 push/fold 或 ICM 压力下的**范围/打法建议**（策略真值，待审核内容）。
- 不做多路同池泡沫系数、赛事推进、对手模型。
- 不持久化计算历史、不跨设备同步、不产生训练事件。
- 展示层只做定点小数，不做货币符号/本地化格式（沿用项目手写整数格式惯例）。

## Acceptance Criteria

1. `xcodegen generate` 后，App target 依赖并 `import TournamentEngine` 编译通过。
2. `TournamentICMPresentation.decimalString` 单元测试：`10000/3`→`"3333.33"`、`2/3`→`"0.67"`、
   `1/1`→`"1.00"`、`-4/3`→`"-1.33"`（全整数、无浮点）。
3. UI 测试 `TournamentICMSurfaceTests`：经复盘（tab 或侧栏）→ `review.tournamentICM`
   打开；输入 `1000,1000,1000` + `5000,3000,2000` 计算 → 见 `3333.33`；选 hero0/opp1 +
   `500,300,200` → 见泡沫系数 `1.33`；非整数输入 → 见 `icm.error`。
4. `AdaptiveNavigationTests` 仍绿（四标签不变）。
5. Release 模拟器构建通过（工具不含 fixture/未审核内容，纯数学，不触发内容门禁）。
