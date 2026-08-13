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

## Requirement: 可选泡沫系数

The system SHALL, when the user supplies a hero seat and a distinct opponent seat, display the bubble factor between them as a fixed-point decimal, and otherwise show only per-seat equities.

### Scenario: 选定 hero/opp 显示泡沫系数

- GIVEN 筹码 `1000,1000,1000`、派彩 `500,300,200`（或同比例 `5000,3000,2000`）、hero=`0`、opp=`1`
- WHEN 点计算
- THEN 显示泡沫系数 `1.33`（`4/3` 两位）
- AND 各家权益仍同时显示

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
