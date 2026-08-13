---
name: tournament-m3-icm-bf-row-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：ICM 计算器显示英雄对每位对手的泡沫系数（内容无关）

## Why

现有 ICM 计算器只算英雄对**单一**对手的泡沫系数（要填两个座位）。但职业玩家读 ICM
压力的方式是「我对**每一位**对手分别能不能对拼」——同一手筹码，对短码对手的泡沫系数
可能接近 1（可放手打），对大码对手可能很高（要极度谨慎）。把单对手升级为**英雄对
全场每位对手**的一排泡沫系数，才是真正有用的 ICM 压力视图。仍是纯 `ICMPressure` 数学，
不含任何范围/打法建议。

## What Changes

### New Capabilities

无。

### Modified Capabilities

- `tournament-icm-calculator` — 泡沫系数从「英雄 vs 单一对手（需填两个座位）」改为
  「填英雄座位 → 显示英雄对**每位**其他座位的泡沫系数」（各为定点小数）。移除对手座位
  输入。单个对手的组合仍是其中一行，能力不减。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-icm-calculator（修改：泡沫系数视图）

- **View/ViewModel**：移除 `opponentSeatInput`；保留 `heroSeatInput`。填了英雄座位并算完
  各家权益后，对每个 `j != hero` 调 `ICMPressure.bubbleFactor(chipStacks:payouts:
  heroIndex:opponentIndex:)`，渲染一行「对 座位 j：X.XX」。
- **每对手错误就地渲染**：某个 `(hero, j)` 抛 `ICMError`（如平坦派彩的 `noEquityGain`）
  时，该行显示可读原因而非数字，不影响其他行与各家权益。
- **英雄座位非法**：非整数或越界 → 顶层错误 `icm.error`，不显示泡沫系数行。
- accessibility：每行 `icm.bubbleFactor.j`（j 为对手座位号）。

#### Requirement: 显示英雄对每位对手的泡沫系数

The system SHALL, when a valid hero seat is provided, display the bubble factor between
the hero and each other seat as a fixed-point decimal, one row per opponent, and show a
readable reason in place of a number for any opponent whose factor cannot be formed.

##### Scenario: 英雄座位下显示对每位对手的泡沫系数

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`、英雄座位 `0`
- WHEN 点计算
- THEN 显示两行泡沫系数：「对 座位 1：1.33」「对 座位 2：1.33」（等筹码下对称，均 `4/3`）
- AND 各家权益仍同时显示

##### Scenario: 非对称筹码下各对手泡沫系数可不同

- GIVEN 筹码 `3000,1000,2000`、派彩 `500,300,200`、英雄座位 `0`
- WHEN 点计算
- THEN 显示对 座位 1 的泡沫系数为 `1.07`（`31/29`）
- AND 显示对 座位 2 的泡沫系数（另一行，独立计算，可与对座位 1 不同）

##### Scenario: 平坦派彩下每行显示无增益原因而非数字

- GIVEN 筹码 `1000,1000,1000`、派彩 `300,300,300`（平坦）、英雄座位 `0`
- WHEN 点计算
- THEN 每行泡沫系数处显示无增益的可读原因（源自 `noEquityGain`），不显示数字
- AND 各家权益仍显示（平坦派彩下权益本身合法：各 `300`）

##### Scenario: 非法英雄座位报错

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`、英雄座位 `9`（越界）或 `abc`
- WHEN 点计算
- THEN 显示顶层错误 `icm.error`，不显示任何泡沫系数行
- AND 不填英雄座位时只显示各家权益、不显示泡沫系数行（配对成功）

## Impact

- **Code:** 改 `PokerCoach/Features/TournamentICM/TournamentICMViewModel.swift`、
  `TournamentICMView.swift`；更新 `PokerCoachUITests/TournamentICMSurfaceTests.swift`；
  可加 `PokerCoachTests/TournamentICMViewModelTests.swift`。
- **Interfaces:** 复盘下计算器交互略变（少一个输入框，多一排结果）；无网络/存储/契约变更；
  不产生 `TrainingEvent`；四核心标签不变。
- **Dependencies:** 无新增（仍用 TournamentEngine）。

## Risks

- **某对手不可算**：→ 就地渲染 `noEquityGain` 原因，不崩、不编造、不影响其他行。
- **被误当训练/策略**：→ 仍是描述性度量，无范围/评分/建议。
- **回归**：→ 更新既有 UI 测试从单对手断言改为行断言；`AdaptiveNavigationTests` 不受影响。

## Non-Goals

- 不做对手两两之间（非英雄视角）的泡沫系数矩阵。
- 不做基于泡沫系数的打法建议/范围（策略真值）。
- 不做多路同池联合淘汰泡沫系数。

## Acceptance Criteria

1. 英雄座位 `0`、`1000,1000,1000`+`500,300,200` → 两行 `对 座位 1：1.33`、`对 座位 2：1.33`。
2. `3000,1000,2000`+`500,300,200`、英雄 `0` → 对 座位 1 行含 `1.07`（`31/29`）。
3. 平坦 `300,300,300`、英雄 `0` → 每行显示无增益原因，不显示数字，权益仍显示。
4. 英雄座位越界/非整数 → `icm.error`，无泡沫系数行；不填英雄座位 → 无泡沫系数行、权益仍显示。
5. UI 测试与 ViewModel 单测覆盖上述；`AdaptiveNavigationTests` 绿；Release 构建通过；层禁通过。
