# Capability: tournament-icm-calculator

## Requirement: 复盘下可达并算出精确 ICM 权益（展示为定点小数）

The system SHALL, from within the 复盘 tab, let the user enter chip stacks and a payout structure and display each seat's ICM equity as a fixed-point decimal derived from the exact `Fraction` by integer arithmetic only.

### Scenario: 输入等筹码与阶梯派彩得到各家权益

- GIVEN 在复盘下打开锦标赛 ICM 计算器，筹码输入 `1000,1000,1000`、派彩输入 `5000,3000,2000`
- WHEN 点计算
- THEN 三家权益各显示为 `3333.33`（`10000/3` 四舍五入到两位，整数长除法所得，非浮点）
- AND 页面经「复盘」标签（iPhone）或侧栏（iPad）→ `review.tournamentICM` 可达

### Scenario: 展示层小数转换精确且四舍五入（单元级）

- GIVEN `Fraction(10000, 3)`
- WHEN `TournamentICMPresentation.decimalString(_, places: 2)`
- THEN 得 `"3333.33"`
- AND `Fraction(2, 3)` places 2 → `"0.67"`（进位四舍五入）、`Fraction(1, 1)` places 2 → `"1.00"`、`Fraction(-4, 3)` places 2 → `"-1.33"`（符号保留）、`Fraction(1999, 1000)` places 2 → `"2.00"`（进位入整数位）

## Requirement: 显示英雄对每位对手的泡沫系数

The system SHALL, when a valid hero seat is provided, display the bubble factor between the hero and each other seat as a fixed-point decimal, one row per opponent, and show a readable reason in place of a number for any opponent whose factor cannot be formed.

### Scenario: 英雄座位下显示对每位对手的泡沫系数

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`、英雄座位 `0`
- WHEN 点计算
- THEN 显示两行泡沫系数：「对 座位 1：1.33」「对 座位 2：1.33」（等筹码下对称，均 `4/3`）
- AND 各家权益仍同时显示

### Scenario: 非对称筹码下各对手泡沫系数可不同

- GIVEN 筹码 `3000,1000,2000`、派彩 `500,300,200`、英雄座位 `0`
- WHEN 点计算
- THEN 显示对 座位 1 的泡沫系数为 `1.07`（`31/29`）
- AND 显示对 座位 2 的泡沫系数（另一行，独立计算，可与对座位 1 不同）

### Scenario: 平坦派彩下每行显示无增益原因而非数字

- GIVEN 筹码 `1000,1000,1000`、派彩 `300,300,300`（平坦）、英雄座位 `0`
- WHEN 点计算
- THEN 每行泡沫系数处显示无增益的可读原因（源自 `noEquityGain`），不显示数字
- AND 各家权益仍显示（平坦派彩下权益本身合法：各 `300`）

### Scenario: 非法或空英雄座位

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`
- WHEN 英雄座位为 `9`（越界）或 `abc` → 显示顶层错误 `icm.error`，无泡沫系数行
- AND 不填英雄座位 → 只显示各家权益、无泡沫系数行

## Requirement: 非法输入映射为可读错误，绝不静默或编造

The system SHALL map malformed input and every engine error to a readable message and show no numeric result in that case, never crashing or fabricating a value.

### Scenario: 非整数/空筹码输入报解析错误

- GIVEN 筹码输入 `1000,abc`（含非整数）
- WHEN 点计算
- THEN 显示解析错误（`icm.error`），不显示任何权益数字

### Scenario: 引擎错误被映射（名次多于座位 / 平坦无增益）

- GIVEN 筹码 `1000,1000`、派彩 `100,60,40`（名次多于座位）
- WHEN 点计算
- THEN 显示对应中文错误（源自 `ICMError.morePayoutsThanPlayers`），无权益数字
- AND 泡沫系数选定平坦派彩 `300,300,300` 时显示无增益错误（源自 `noEquityGain`）
