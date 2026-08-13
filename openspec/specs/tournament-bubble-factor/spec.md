# Capability: tournament-bubble-factor

## Requirement: 精确泡沫系数

The system SHALL compute the per-opponent bubble factor as an exact reduced rational via ICM equities, handling all-in eliminations exactly (the short/equal stack that loses is knocked out and takes the tail payout while the survivors contest the places above), and it SHALL equal 1 exactly when the prize structure is winner-take-all.

### Scenario: 三家等筹码、阶梯派彩产生大于 1 的泡沫系数

- GIVEN 三家等筹码 `[1000, 1000, 1000]`，派彩 `[500, 300, 200]`，hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(4, 3)`（equityNow=`1000/3`；赢局 opp 出局领 `200`、`{2000,1000}` 争 `[500,300]` → `1300/3`；输局 hero 出局领 `200`；`(1000/3 − 200)/(1300/3 − 1000/3) = (400/3)/100 = 4/3`）
- AND 严格大于 `Fraction(1, 1)`（ICM 对筹码征税）

### Scenario: 赢家通吃时泡沫系数恰为 1

- GIVEN 三家等筹码 `[1000, 1000, 1000]`，派彩仅 `[1000]`（赢家通吃），hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(1, 1)`（equityNow=`1000/3`；赢局 `{2000,1000}` 争 `[1000]` → `2000/3`；输局 hero 出局领 `0`；`(1000/3 − 0)/(2000/3 − 1000/3) = 1`）

### Scenario: 大码 hero 对短码（赢则对手出局、输则双方存活）

- GIVEN 三家 `[3000, 1000, 2000]`，派彩 `[500, 300, 200]`，hero=0（大码）、opp=1（短码）
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(31, 29)`（`r=1000`；equityNow=`385`；赢局 opp 出局、`{4000,2000}` 争 `[500,300]` → `1300/3`；输局双方存活 `[2000,2000,2000]` → `1000/3`；`(155/3)/(145/3) = 31/29`）
- AND 严格大于 `Fraction(1, 1)`

### Scenario: 单挑无阶梯，泡沫系数恰为 1

- GIVEN 两家 `[3000, 1000]`，派彩 `[100, 60]`，hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(1, 1)`（单挑无名次阶梯可爬）

## Requirement: 无增益与非法输入的确定性拒绝

The system SHALL reject a bubble-factor query it cannot form as an exact ratio, and reject ill-formed seat selection, each with a distinct equatable error, never dividing by zero.

### Scenario: 平坦派彩无权益增益时拒绝

- GIVEN 三家 `[1000, 1000, 1000]`，派彩 `[300, 300, 300]`（平坦），hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 以 `ICMError.noEquityGain` 拒绝（赢局与当前权益相等，分母为 0，绝不除零）
- AND 同筹码换非平坦派彩 `[500, 300, 200]` 能返回泡沫系数（配对成功）

### Scenario: 同座与越界座位被分别拒绝

- GIVEN 三家 `[1000, 1000, 1000]`，派彩 `[500, 300, 200]`
- WHEN `heroIndex == opponentIndex` → 抛 `ICMError.sameSeat`
- AND `heroIndex` 或 `opponentIndex` 超出 `0..<count`（含负数）→ 抛 `ICMError.seatOutOfRange`
- AND 合法不同座位（0、1）能返回泡沫系数（配对成功）

### Scenario: 沿用 ICM 的输入校验

- GIVEN 空筹码 / 空派彩 / 非正筹码 / 负派彩 / 名次多于座位 / >64 座位
- WHEN 计算泡沫系数
- THEN 分别以 ICM 既有的 `noPlayers`/`emptyPayouts`/`nonPositiveStack`/`negativePayout`/`morePayoutsThanPlayers`/`tooManySeats` 拒绝（校验先于取权益）

## Requirement: Fraction 精确取负、相减、倒数、相除

The system SHALL extend `Fraction` with exact negation, subtraction, reciprocal, and division, each reduced and each trapping `Int` overflow as `ICMError.overflow` rather than approximating.

### Scenario: 相减精确

- GIVEN `Fraction(1300, 3)` 与 `Fraction(1000, 3)`
- WHEN 相减
- THEN 精确等于 `Fraction(100, 1)`

### Scenario: 相除等于乘倒数

- GIVEN `Fraction(400, 3)` 除以 `Fraction(100, 1)`
- WHEN 相除
- THEN 精确等于 `Fraction(4, 3)`

### Scenario: 对零取倒数触发前置崩溃（编程错误）

- GIVEN `Fraction(0)`
- WHEN 取 `reciprocal()`
- THEN 以 precondition 崩溃（零无倒数是编程错误；泡沫系数路径已先以 `noEquityGain` 挡住）
