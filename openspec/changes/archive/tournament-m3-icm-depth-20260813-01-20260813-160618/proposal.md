---
name: tournament-m3-icm-depth-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：ICM 计算器显示有效深度与 push/fold 区（内容无关）

## Why

M3 引擎的两块地基——升盲结构的**有效深度**（slice 1 `effectiveBigBlinds`）与**短筹码
push/fold 上下文**（slice 3 `PushFoldContext`）——至今没有任何界面。ICM 计算器已经拿到
各家筹码，只要再给一个大盲（筹码/BB），就能顺带显示每家的**有效深度（BB）**；再给一个
push/fold 阈值（BB），就能标出哪些座位落在短筹码 push/fold 区。这把两块引擎地基暴露给
用户，且完全内容无关：阈值由用户传入、jam-or-fold 是披露式简化模型、不含任何范围或建议。

## What Changes

### Modified Capabilities

- `tournament-icm-calculator` — 新增两个可选输入：大盲（筹码/BB）与 push/fold 阈值（BB）。
  填了大盲即显示每家有效深度（向下取整 BB）；再填阈值即标出哪些座位「≤ 阈值，属 push/fold
  区（模型：全下或弃牌）」。加法式，不改既有权益/泡沫系数行为。

## Capabilities Detail

### Capability: tournament-icm-calculator（新增：有效深度与 push/fold 区）

- 输入：`bigBlindInput`（每 BB 多少筹码，正整数）、`pushFoldThresholdInput`（BB，非负整数），
  均可选。
- 大盲有效时，对每家用 slice-1 的 `effectiveBigBlinds(chips:atLevel:)`（以
  `BlindLevel(bigBlindChips: 大盲)`）算**向下取整**的 BB 深度，显示「座位 k：X BB」。
- 阈值也有效时，对每家用 slice-3 的 `PushFoldContext.isAtOrBelow(thresholdBigBlinds:)`
  （整数精确比较 `chips ≤ 阈值 × 大盲`，无 floor 损失）判定是否属 push/fold 区，标注
  「push/fold 区（全下/弃牌模型）」。**不主张**该区必须 push/fold、不给范围、不评分。
- 校验：大盲非正 / 阈值非整数或负 → 顶层可读错误；阈值×大盲溢出映射为可读错误
  （源自 `PushFoldError.thresholdOverflow`）。大盲留空则不显示深度区（既有行为不变）。
- accessibility：每家深度 `icm.depth.k`，push/fold 标注并入该行文本。

#### Requirement: 显示每家有效深度与 push/fold 区

The system SHALL, when a positive big blind (in chips) is provided, display each seat's
effective depth in big blinds (floored), and, when a non-negative push/fold threshold
(in big blinds) is also provided, flag which seats sit at or below it as a disclosed
jam-or-fold zone — endorsing no threshold and offering no range.

##### Scenario: 填大盲显示每家有效深度

- GIVEN 计算器筹码 `12000,3000`、大盲 `1000`
- WHEN 点计算
- THEN 显示「座位 0：12 BB」「座位 1：3 BB」（`chips / bigBlind` 向下取整）

##### Scenario: 填阈值标出 push/fold 区（精确整数比较）

- GIVEN 筹码 `12000,3000`、大盲 `1000`、push/fold 阈值 `10`
- WHEN 点计算
- THEN 座位 1（`3000 ≤ 10×1000`）标为 push/fold 区（全下/弃牌模型）；座位 0
  （`12000 > 10000`）不标
- AND 标注是披露式模型，不主张该座位必须 push/fold、不给范围

##### Scenario: 大盲非正与阈值非法被拒

- GIVEN 筹码 `12000,3000`
- WHEN 大盲填 `0` 或负数 → 显示可读错误，不显示深度区
- AND 大盲 `1000` 且阈值填 `-1` 或非整数 → 显示可读错误
- AND 大盲 `1000`、阈值留空 → 只显示深度、不显示 push/fold 标注（配对成功）

## Impact

- **Code:** 改 `PokerCoach/Features/TournamentICM/TournamentICMViewModel.swift`、
  `TournamentICMView.swift`；扩 `PokerCoachTests/TournamentICMViewModelTests.swift`、
  `PokerCoachUITests/TournamentICMSurfaceTests.swift`。
- **Interfaces:** 计算器多两个可选输入与一个深度区；无网络/存储/契约变更；不产生
  `TrainingEvent`；四核心标签不变。
- **Dependencies:** 无新增（复用 TournamentEngine 的 `effectiveBigBlinds`/`PushFoldContext`）。

## Risks

- **把 push/fold 区误当建议**：→ 文案明确「披露式全下/弃牌模型，不主张必须如此、不含范围」。
- **精度**：→ 深度用向下取整（展示口径），push/fold 判定用整数精确比较 `chips ≤ 阈值×大盲`
  （非 floor 后再比）；阈值×大盲溢出报错不静默。
- **回归**：→ 大盲留空时既有权益/泡沫系数行为完全不变；`AdaptiveNavigationTests` 不受影响。

## Non-Goals

- 不做完整升盲表输入 / 逐级推进（本切片只取单个大盲求当下深度）。
- 不背书任何 push/fold 阈值；不做 push/fold 范围或打法建议（策略真值）。
- 不做 ante 对有效深度/M 值的换算。

## Acceptance Criteria

1. 筹码 `12000,3000` + 大盲 `1000` → 深度「座位 0：12 BB」「座位 1：3 BB」。
2. 加阈值 `10` → 座位 1 标 push/fold 区、座位 0 不标。
3. 大盲 `0`/负 → 报错无深度区；阈值 `-1`/非整数 → 报错；阈值留空 → 只深度无标注。
4. ViewModel 单测 + UI 测试覆盖上述；`AdaptiveNavigationTests` 绿；Release 构建通过；层禁通过。
