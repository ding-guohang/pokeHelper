---
name: tournament-m3-icm-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：锦标赛 ICM 权益计算器（精确、内容无关）

## Why

M3 第一切片给了锦标赛的结构地基（升盲表、整数筹码、有效深度）。要谈锦标赛决策，
下一块地基是把「筹码栈」翻译成「奖金期望」——这就是 ICM（Independent Chip
Model）。ICM 是纯数学（由各家筹码与派彩结构推出各家夺得每个名次的概率，再乘以
该名次派彩求和），**不是策略真值**：它不告诉你该怎么打，只回答「按 Malmuth-Harville
模型，此刻我的筹码折合多少奖金」。因此它属于引擎、不属于内容，可以在没有任何范围/
求解器数据的前提下交付。

ICM 有一个绕不开的设计点：Malmuth-Harville 名次概率是**有理数**（如三家等筹码
各得总奖金的 1/3），而项目的精确数据铁律禁止用浮点作为领域真值（浮点只用于展示），
且 ICM 权益是**算出来的商**（分母不整除任何十的幂），任何定点刻度（cents、
milli-cents）都会被迫舍入即「悄悄算错」。本切片必须给出一个**精确**表示（约分有理数），
并且在超出精确能力时**报错而非悄悄近似**。

## What Changes

### New Capabilities

- `tournament-icm` — 给定各家整数筹码与整数派彩结构，用 Malmuth-Harville 精确
  计算每家的 ICM 权益（以约分后的精确有理数表示，不引入浮点真值）；含派彩结构与
  非法输入的可判等校验（固定优先级），支持派彩名次少于座位数（未入钱名次派彩为 0），
  以及超出精确能力时的确定性报错。

### Modified Capabilities

无。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-icm

`TournamentEngine` 包（只依赖 PokerCore，实际只用 Swift 标准库）新增四个文件：

- **`Fraction`**（精确有理数）：`numerator`/`denominator` 均为 `Int`，构造即约分、
  分母恒正、`0` 规范化为 `0/1`；`Fraction(numerator:_, denominator: 0)` 以
  precondition 崩溃（分母为 0 是编程错误，不是可恢复输入——ICM 永不喂它）。
  声明 `Sendable, Hashable, Comparable`（有理数天然可比，权益要排序/比较）。
  算术为**具名 throwing 方法**（不是 throwing 运算符，避免 `try a + b` 噪声）：
  `adding(_:) throws -> Fraction`、`multiplied(by:) throws -> Fraction`、
  `multiplied(byInteger:) throws -> Fraction`；每步**先约分再相乘**（gcd/lcm）、
  每步之后再 gcd 约分，任一分子/分母超出 `Int` 范围即抛 `ICMError.overflow`，
  绝不回退浮点或截断。`Fraction` 是精确真值（有理数，非浮点），符合精确数据铁律。
  若 `Codable`，`init(from:)` 须重新规范化（仿 `BBAmount` 的校验式解码）。
- **`PayoutStructure`**：有序整数派彩数组（第 1 名到第 k 名，单位为最小货币整数
  单位如 cents）。校验：非空、每项非负。
- **`ICMError`**：`Error, Equatable, Sendable`，含 `noPlayers`、`emptyPayouts`、
  `nonPositiveStack`、`negativePayout`、`morePayoutsThanPlayers`、`tooManySeats`
  （>64 座位，名次递归用 `Int` 位掩码，超 64 位会丢位悄悄算错，故拒绝）、`overflow`
  七个可判等 case。
- **`ICMCalculator.equities(chipStacks:payouts:) throws -> [Fraction]`**：按座位
  顺序返回每家的 ICM 权益（单位同派彩，均为 `Fraction`）。算法 Malmuth-Harville：
  权益_i = Σ_k P(第 i 家名列第 k) × payoutAt(k)，其中 `payoutAt(k)` 在 k <
  派彩名次数时取 `payouts[k]`、否则取 `0`（**未入钱名次派彩为 0**）；名次概率按
  「当前筹码占剩余总筹码之比」逐名次递归展开。**先按各家筹码的最大公约数归一**
  （ICM 只依赖筹码比例，归一后中间分母显著变小，真实决赛桌不会虚假溢出）。
  Malmuth-Harville **假设不存在同名次同时淘汰**；等筹码由标准递归自然处理，无需
  也不得加特判分支。

#### Requirement: 精确 ICM 权益计算

The system SHALL compute each player's ICM equity as an exact reduced rational
number via the Malmuth-Harville model, never as a floating-point value, treating
finish places beyond the payout structure as paying zero.

##### Scenario: 三家等筹码、部分派彩产生非整数权益（浮点判别关卡）

- GIVEN 三家筹码均为 `1000`，派彩结构为 `[5000, 3000, 2000]`（cents）
- WHEN 计算 ICM 权益
- THEN 由对称性每家权益精确等于 `Fraction(numerator: 10000, denominator: 3)`
- AND 三家权益用 `Fraction` 精确相加等于 `Fraction(numerator: 10000, denominator: 1)`
  （浮点实现会把 `3 × 3333.33…` 加成 `9999.99…` 而失败——这是最强的浮点判别）

##### Scenario: 两家不等筹码、多名次派彩

- GIVEN 两家筹码分别为 A=`3000`、B=`1000`，派彩为 `[100, 60]`（cents）
- WHEN 计算 ICM 权益
- THEN A 的权益精确等于 `Fraction(90, 1)`（A 夺冠 `3/4`×100 + A 亚军 `1/4`×60）
- AND B 的权益精确等于 `Fraction(70, 1)`（`1/4`×100 + `3/4`×60）

##### Scenario: 三家不等筹码的经典分布（逐家精确值）

- GIVEN 三家筹码 A=`5000`、B=`3000`、C=`2000`，派彩 `[500, 300, 200]`
- WHEN 计算 ICM 权益
- THEN A 的权益精确等于 `Fraction(5375, 14)`
- AND B 的权益精确等于 `Fraction(655, 2)`（即 `4585/14`）
- AND C 的权益精确等于 `Fraction(2020, 7)`（即 `4040/14`）
- AND 三家之和精确等于 `Fraction(1000, 1)`

##### Scenario: 派彩名次少于座位数，未入钱名次派彩为 0（常规锦标赛）

- GIVEN 四家筹码 `[4000, 3000, 2000, 1000]`，派彩仅两个名次 `[500, 300]`
- WHEN 计算 ICM 权益
- THEN 每家权益按第 3、4 名派彩为 `0` 的 Malmuth-Harville 展开求得（精确有理数）
- AND 四家权益之和精确等于 `Fraction(800, 1)`（只有前二入钱，总额 800）

##### Scenario: 单人剩余

- GIVEN 一家筹码 `[1000]`，派彩 `[500]`
- WHEN 计算 ICM 权益
- THEN 该家权益精确等于 `Fraction(500, 1)`（P(第 1 名)=1）

#### Requirement: 派彩结构、输入校验与守恒

The system SHALL validate stacks and payout structure in a fixed precedence,
reject each illegal condition in isolation with a distinct equatable error, and
guarantee that the equities sum exactly to the total awarded payout.

校验优先级（每个错误的测试用**恰好一个**违规输入，避免误归因）：
`noPlayers` → `emptyPayouts` → `nonPositiveStack` → `negativePayout` →
`morePayoutsThanPlayers` → `tooManySeats`。

##### Scenario: 权益之和等于派彩总额（含未入钱尾）

- GIVEN 一组不对称筹码 `[4000, 3000, 2000, 1000]`、派彩 `[500, 300]`
- WHEN 计算 ICM 权益并用 `Fraction` 精确相加
- THEN 各家权益之和精确等于 `Fraction(800, 1)`（守恒对未入钱名次为 0 的尾同样成立）

##### Scenario: 空筹码被拒（且合法输入成功）

- GIVEN 空筹码数组 `[]`、派彩 `[100]`
- WHEN 计算
- THEN 以 `ICMError.noPlayers` 拒绝（优先级高于 `morePayoutsThanPlayers`）
- AND 同派彩配上非空合法筹码 `[100]` 能返回权益（配对成功断言，防门禁永假）

##### Scenario: 空派彩被拒（且合法输入成功）

- GIVEN 合法筹码 `[1000, 1000]`、空派彩 `[]`
- WHEN 计算
- THEN 以 `ICMError.emptyPayouts` 拒绝
- AND 同筹码配上非空派彩 `[100]` 能返回权益

##### Scenario: 非正筹码与负派彩被分别拒绝

- GIVEN 筹码含 `0` 或负数（其余合法）→ 以 `ICMError.nonPositiveStack` 拒绝
- AND 派彩含负数（其余合法）→ 以 `ICMError.negativePayout` 拒绝
- WHEN 各自单独违规计算
- THEN 两种错误可判等且互不相同；各自去掉该违规后能返回权益

##### Scenario: 名次数超过座位数被拒（且相等/更少时成功）

- GIVEN 两家筹码 `[1000, 1000]`、派彩三名次 `[100, 60, 40]`
- WHEN 计算
- THEN 以 `ICMError.morePayoutsThanPlayers` 拒绝
- AND 派彩降到 `[100, 60]`（名次数 = 座位数）能返回权益

##### Scenario: 超过 64 座位被拒（64 座位成功）

- GIVEN 65 家筹码（名次递归用 `Int` 位掩码，65 位会丢位）
- WHEN 计算
- THEN 以 `ICMError.tooManySeats` 拒绝（宁可拒绝不可悄悄算错）
- AND 64 家能返回权益（边界内成功，防门禁永假）

#### Requirement: 精确性与溢出保护

The system SHALL keep all intermediate arithmetic exact and, when an exact result
would exceed the representable integer range, fail deterministically rather than
return an approximate value. Exact `Int64`-rational ICM has a real ceiling — a
field of large coprime stacks has an equity denominator (the LCM of products of
running totals) beyond `Int.max` — so the calculator computes exactly for tables
whose stacks share a chip unit (reducing to small integers, the realistic case)
and reports `overflow` beyond, never approximating.

##### Scenario: Fraction 构造即约分且分母恒正

- GIVEN 用 `numerator = 6`、`denominator = -3` 构造 `Fraction`
- WHEN 读取其分子分母
- THEN 得到约分且分母恒正的规范形 `-2/1`
- AND `0` 值规范化为 `0/1`

##### Scenario: 中间运算溢出时报错而非近似（固定输入）

- GIVEN 两家筹码 `[3000, 1000]`、派彩 `[Int.max, 0]`
- WHEN 计算 ICM 权益（A 夺冠 `3/4` × `Int.max` 使分子 `3 × Int.max` 溢出）
- THEN 抛出 `ICMError.overflow`
- AND 绝不返回浮点近似或被截断的整数结果

##### Scenario: 恰在阈值之下时成功（防溢出关卡退化为永抛）

- GIVEN 两家筹码 `[3000, 1000]`、派彩 `[Int.max / 4, 0]`
- WHEN 计算 ICM 权益（`3 × (Int.max / 4)` < `Int.max`）
- THEN 返回精确 `Fraction` 权益，不抛错

##### Scenario: 共用筹码单位的现实决赛桌精确算出

- GIVEN 六家筹码共用 10000 单位 `[120000, 90000, 70000, 50000, 40000, 30000]`
  （归一为 `[12,9,7,5,4,3]`），派彩三名次 `[50000, 30000, 20000]`
- WHEN 计算 ICM 权益
- THEN 成功返回六个精确 `Fraction` 权益且不抛 `overflow`
- AND 六家权益之和精确等于 `Fraction(100000, 1)`（先按筹码 gcd 归一使中间分母收缩）

##### Scenario: 超出精确 Int 范围的赛场报溢出而非近似

- GIVEN 九家几乎互质的大筹码（gcd 仅 1000 → `[125,98,76,61,45,33,22,14,8]`），
  派彩 `[50000, 30000, 20000]`
- WHEN 计算 ICM 权益
- THEN 精确权益分母超出 `Int.max`，抛 `ICMError.overflow`
- AND 绝不返回近似或截断值（精确数据铁律的落地：宁可报错不可悄悄算错）

## Impact

- **Code:** `Packages/TournamentEngine/Sources/TournamentEngine/`（新增
  `Fraction.swift`、`PayoutStructure.swift`、`ICMError.swift`、`ICMCalculator.swift`）；
  测试位于 `Packages/TournamentEngine/Tests/`。
- **Interfaces:** 纯 Swift API，无 UI/网络/存储变更；不入 App target（本切片只做引擎）。
- **Dependencies:** 仅 PokerCore（`Fraction`/ICM 只用标准库）；
  `check-package-layering.sh` 现有的「TournamentEngine 只见 PokerCore」门禁按目录
  glob 自动覆盖新文件，无需新增门禁。

## Risks

- **精确表示溢出**：Malmuth-Harville 递归分母是「剩余筹码总和」之积；只枚举入钱
  名次把它压到至多 K 个总和连乘。→ (1) 先按各家筹码 gcd 归一（ICM 只依赖比例），
  (2) 先约分再相乘、每步 gcd 约分，(3) 仍超出 `Int` 即抛 `ICMError.overflow`。
  **诚实边界**：互质大筹码的满座赛场其精确分母本就超 `Int64`，此时报错是正确行为
  （宁可报错不可悄悄算错），非缺陷；现实决赛桌筹码共用单位、归一后很小，落在精确
  范围内。用固定溢出输入（payout=`Int.max`）+ 阈值下成功 + 共用单位六人桌精确 +
  互质九人桌报溢出四面钉死。
- **把 ICM 误当策略**：ICM 是模型化数学不是打法。→ 文档措辞「按 Malmuth-Harville
  模型的权益」而非「真实现金价值」；不引入任何范围/频率/求解器字段，layering 门禁
  保证不依赖内容。
- **浮点渗入**：图省事用 `Double` 算概率。→ 领域层只存/比 `Fraction`；Scenario 1 的
  `10000/3` 与 `3×(10000/3)==10000/1` 守恒断言是浮点判别关卡，`Double` 会失败。

## Non-Goals

- 不做 push/fold 范围、ICM 压力下的开牌/跟注范围等**策略内容**（策略真值，需真实
  来源与人工审核，另行处理）。
- 不做泡沫/决赛桌的具体决策建议或可玩推进（对手打法=内容）。
- 不做 ICM 的近似加速算法（大规模场景的采样/近似）——本切片只保证精确或报错。
- 不建模同名次同时淘汰、抽头/返还等；不做 UI 展示（`Fraction`→百分比/货币的展示
  层留待后续接入锦标赛特性时）。

## Acceptance Criteria

1. `swift test --package-path Packages/TournamentEngine` 全绿，含上述所有 Scenario。
2. 三家等筹码 `[1000,1000,1000]`、派彩 `[5000,3000,2000]` 每家权益精确为
   `Fraction(10000, 3)`，且三者之和精确 `Fraction(10000, 1)`（浮点判别）。
3. 三家 `[5000,3000,2000]`、派彩 `[500,300,200]` 逐家精确为 `5375/14`、`655/2`、
   `2020/7`，和为 `1000/1`。
4. 四家 `[4000,3000,2000,1000]`、派彩 `[500,300]`（名次<座位）权益和精确 `800/1`。
5. 六种非法输入（noPlayers/emptyPayouts/nonPositiveStack/negativePayout/
   morePayoutsThanPlayers/tooManySeats）按固定优先级各以**不同且可判等**的
   `ICMError` 在**隔离**下被拒，每个都配「去掉该违规后成功」的对照断言。
6. 固定输入 `[3000,1000]` + `[Int.max,0]` 抛 `ICMError.overflow`；
   `[3000,1000]` + `[Int.max/4,0]` 成功返回精确 `Fraction`。
7. 共用单位的六人桌（`[120000,…,30000]`）不抛 `overflow`、权益和精确 `100000/1`；
   互质大筹码的九人桌超出 `Int` 范围时抛 `ICMError.overflow`（不近似）。
8. `bash scripts/check-package-layering.sh` 通过：ICM 代码只依赖 PokerCore/标准库。
