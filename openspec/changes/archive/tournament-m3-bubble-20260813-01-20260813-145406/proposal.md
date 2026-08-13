---
name: tournament-m3-bubble-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：ICM 风险溢价 / 泡沫系数（精确、内容无关）

## Why

有了精确 ICM 权益（切片二），锦标赛决策地基还差一块**描述性**度量：泡沫系数
（bubble factor）/ 风险溢价——「为了赢得 1 筹码的权益，我要拿多少筹码的权益去冒险」。
它把「同样的筹码在锦标赛里输比赢更疼」这一 ICM 事实量化成一个精确比率：

`BF = (当前权益 − 输光该次全下的权益) / (赢下该次全下的权益 − 当前权益)`

在纯筹码博弈（赢家通吃）里 `BF = 1`（筹码线性等于权益）；在有阶梯派彩时 `BF > 1`
（ICM 对筹码征税）。这是**关于派彩结构与筹码的事实**，和 ICM 权益本身一样是纯数学，
**不是策略**：它只量化 ICM 压力，**不**推荐该跟该弃、也不给任何范围（那是策略真值，
留作审核内容）。

## What Changes

### New Capabilities

- `tournament-bubble-factor` — 在 ICM 权益之上，精确计算英雄对某个特定对手做一次
  全下时的泡沫系数（约分 `Fraction`）；正确处理全下导致的淘汰（短/等筹码方输则出局、
  按名次领取尾部派彩，剩余牌手竞争其上派彩），并在权益无增益（平坦派彩）时以可判等
  错误拒绝而非除零。内容无关（不含范围、不评分、不推荐）。

### Modified Capabilities

- `tournament-icm` — `Fraction` 追加精确的取负 / 相减 / 倒数 / 相除（`negated`、
  `subtracting`、`reciprocal`、`divided(by:)`），同样约分且溢出即抛 `ICMError.overflow`。
  纯加法，不改既有语义。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-bubble-factor

`TournamentEngine` 包新增 `ICMPressure`（无状态纯函数容器）：

```
static func bubbleFactor(
    chipStacks: [Int], payouts: [Int], heroIndex: Int, opponentIndex: Int
) throws -> Fraction
```

- 复用 `ICMCalculator` 的输入校验（noPlayers/emptyPayouts/nonPositiveStack/
  negativePayout/morePayoutsThanPlayers/tooManySeats）；另校验 `heroIndex`、
  `opponentIndex` 在界内且不相等（否则 `sameSeat` / 越界 `seatOutOfRange`）。
- 全下有效额 `r = min(chipStacks[hero], chipStacks[opp])`（整数，精确）。
- **当前权益** `equityNow = ICM(全场)[hero]`。
- **赢局权益** `equityWin`：hero += r、opp −= r。
  - 若 `opp − r == 0`（对手出局）：对手领第 N 名派彩、退出牌桌；剩余 N−1 人竞争
    `payouts.prefix(N−1)`，`equityWin = ICM(去掉对手的场, 缩减派彩)[hero 的新序]`。
  - 否则（均存活）：`equityWin = ICM(更新后的全场, 原派彩)[hero]`。
- **输局权益** `equityLose`：hero −= r、opp += r。
  - 若 `hero − r == 0`（英雄出局）：英雄名列第 N 名，`equityLose = payoutAt(N−1)`
    （`payoutAt(k) = k < payouts.count ? payouts[k] : 0`，确定值，非 ICM）。
  - 否则（均存活）：`equityLose = ICM(更新后的全场, 原派彩)[hero]`。
- `denominator = equityWin − equityNow`；若为 `0`（平坦派彩等无增益）抛
  `ICMError.noEquityGain`（新增 case，避免除零）；否则
  `BF = (equityNow − equityLose) / denominator`。
- 全程精确 `Fraction`，溢出冒泡 `ICMError.overflow`。

`Fraction` 追加：`negated`、`subtracting(_:) throws`、`reciprocal()`（前置非零）、
`divided(by:) throws`（= `multiplied(by: divisor.reciprocal())`）。

#### Requirement: 精确泡沫系数

The system SHALL compute the per-opponent bubble factor as an exact reduced rational
via ICM equities, handling all-in eliminations exactly (the short/equal stack that
loses is knocked out and takes the tail payout while the survivors contest the places
above), and it SHALL equal 1 exactly when the prize structure is winner-take-all.

##### Scenario: 三家等筹码、阶梯派彩产生大于 1 的泡沫系数

- GIVEN 三家等筹码 `[1000, 1000, 1000]`，派彩 `[500, 300, 200]`，hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(4, 3)`
  （equityNow=`1000/3`；赢局 opp 出局领 `200`、`{2000,1000}` 争 `[500,300]` → `1300/3`；
  输局 hero 出局领 `200`；`(1000/3 − 200) / (1300/3 − 1000/3) = (400/3)/100 = 4/3`）
- AND 严格大于 `Fraction(1, 1)`（ICM 对筹码征税）

##### Scenario: 赢家通吃时泡沫系数恰为 1

- GIVEN 三家等筹码 `[1000, 1000, 1000]`，派彩仅 `[1000]`（赢家通吃），hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(1, 1)`
  （equityNow=`1000/3`；赢局 `{2000,1000}` 争 `[1000]` → `2000/3`；输局 hero 出局领 `0`；
  `(1000/3 − 0)/(2000/3 − 1000/3) = 1`）

##### Scenario: 大盘/短码不等筹码（英雄为大码，赢则对手出局、输则双方存活）

- GIVEN 三家 `[3000, 1000, 2000]`，派彩 `[500, 300, 200]`，hero=0（大码）、opp=1（短码）
- WHEN 计算泡沫系数
- THEN 精确等于 `Fraction(31, 29)`（`r=min(3000,1000)=1000`；equityNow=`385`；赢局 opp
  出局领第 3 名派彩、`{4000,2000}` 争 `[500,300]` → `1300/3`；输局双方存活
  `[2000,2000,2000]`（opp 1000+1000=2000）全场 ICM → `1000/3`；
  `(1155/3 − 1000/3)/(1300/3 − 1155/3) = (155/3)/(145/3) = 31/29`）
- AND 结果严格大于 `Fraction(1, 1)`

#### Requirement: 无增益与非法输入的确定性拒绝

The system SHALL reject a bubble-factor query it cannot form as an exact ratio, and
reject ill-formed seat selection, each with a distinct equatable error, never dividing
by zero.

##### Scenario: 平坦派彩无权益增益时拒绝

- GIVEN 三家 `[1000, 1000, 1000]`，派彩 `[300, 300, 300]`（平坦，处处权益相等），hero=0、opp=1
- WHEN 计算泡沫系数
- THEN 以 `ICMError.noEquityGain` 拒绝（赢局与当前权益相等，分母为 0，绝不除零）
- AND 同筹码换非平坦派彩 `[500, 300, 200]` 能返回泡沫系数（配对成功）

##### Scenario: 同座与越界座位被分别拒绝

- GIVEN 三家 `[1000, 1000, 1000]`，派彩 `[500, 300, 200]`
- WHEN `heroIndex == opponentIndex` → 抛 `ICMError.sameSeat`
- AND `heroIndex` 或 `opponentIndex` 超出 `0..<count` → 抛 `ICMError.seatOutOfRange`
- AND 合法不同座位（0、1）能返回泡沫系数（配对成功）

##### Scenario: 沿用 ICM 的输入校验

- GIVEN 空筹码 / 空派彩 / 非正筹码 / 负派彩 / 名次多于座位 / >64 座位
- WHEN 计算泡沫系数
- THEN 分别以 ICM 既有的 `noPlayers`/`emptyPayouts`/`nonPositiveStack`/`negativePayout`/
  `morePayoutsThanPlayers`/`tooManySeats` 拒绝（校验先于取权益）

#### Requirement: Fraction 精确取负、相减、倒数、相除

The system SHALL extend `Fraction` with exact negation, subtraction, reciprocal, and
division, each reduced and each trapping `Int` overflow as `ICMError.overflow` rather
than approximating.

##### Scenario: 相减与相除精确

- GIVEN `Fraction(1300, 3)` 与 `Fraction(1000, 3)`
- WHEN 相减
- THEN 精确等于 `Fraction(100, 1)`

##### Scenario: 相除等于乘倒数

- GIVEN `Fraction(400, 3)` 除以 `Fraction(100, 1)`
- WHEN 相除
- THEN 精确等于 `Fraction(4, 3)`

##### Scenario: 对零取倒数触发前置崩溃（编程错误）

- GIVEN `Fraction(0)`
- WHEN 取 `reciprocal()`
- THEN 以 precondition 崩溃（零无倒数是编程错误；泡沫系数路径已先以 `noEquityGain` 挡住）

## Impact

- **Code:** `Packages/TournamentEngine/Sources/TournamentEngine/`（新增
  `ICMPressure.swift`；`Fraction.swift` 追加取负/相减/倒数/相除；`ICMError.swift` 追加
  `noEquityGain`、`sameSeat`、`seatOutOfRange`）；测试在 `Tests/`。
- **Interfaces:** 纯 Swift API，无 UI/网络/存储变更；不入 App target。
- **Dependencies:** 仅 PokerCore；`check-package-layering.sh` 按目录 glob 自动覆盖。

## Risks

- **淘汰/派彩缩减算错**：全下必有一方（短/等码）出局，缩减派彩与重索引易错。→ 用手算
  钉死的 `4/3`、`1`（赢家通吃）双向例子，以及大码 hero 例子覆盖「赢则对手出局 / 输则
  双方存活」分支。
- **除零**：无增益（平坦派彩）→ 分母 0。→ 先判分母为零抛 `noEquityGain`，配对非平坦成功。
- **把度量误当策略**：→ 命名与文档明确「量化 ICM 压力的描述性比率，不推荐、不评分、
  不含范围」；泡沫系数驱动的跟注/开牌范围留作审核内容。
- **精度**：全程 `Fraction`，溢出冒泡 `overflow`；`reciprocal` 对零前置崩溃（编程错误）。

## Non-Goals

- 不做基于泡沫系数的跟注/开牌**范围**或 push/fold 决策（策略真值，待审核）。
- 不做多路（>2 人同池）全下的联合淘汰泡沫系数（本切片只做英雄 vs 单一对手的两分支）。
- 不做并列/同时淘汰、抽头；不做展示层（`Fraction`→小数留待接入特性时）。

## Acceptance Criteria

1. `swift test --package-path Packages/TournamentEngine` 全绿，含上述所有 Scenario。
2. 等筹码 `[1000,1000,1000]` + `[500,300,200]`、hero0/opp1 → 泡沫系数精确 `Fraction(4,3)` 且 `>1`。
3. 同筹码 + 赢家通吃 `[1000]` → 精确 `Fraction(1,1)`。
4. 平坦派彩 `[300,300,300]` → 抛 `ICMError.noEquityGain`；换 `[500,300,200]` 成功。
5. `sameSeat` / `seatOutOfRange` 各以可判等错误被拒，合法座位成功；沿用 ICM 六类输入校验。
6. `Fraction` 相减 `1300/3 − 1000/3 == 100/1`、相除 `(400/3)/(100/1) == 4/3`；对零取倒数崩溃。
7. `bash scripts/check-package-layering.sh` 通过：只依赖 PokerCore。
