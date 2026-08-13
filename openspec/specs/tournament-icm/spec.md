# Capability: tournament-icm

## Requirement: 精确 ICM 权益计算

The system SHALL compute each player's ICM equity as an exact reduced rational number via the Malmuth-Harville model, never as a floating-point value, treating finish places beyond the payout structure as paying zero.

### Scenario: 三家等筹码、部分派彩产生非整数权益（浮点判别关卡）

- GIVEN 三家筹码均为 `1000`，派彩结构为 `[5000, 3000, 2000]`（cents）
- WHEN 计算 ICM 权益
- THEN 由对称性每家权益精确等于 `Fraction(numerator: 10000, denominator: 3)`
- AND 三家权益用 `Fraction` 精确相加等于 `Fraction(numerator: 10000, denominator: 1)`（浮点实现会把 `3 × 3333.33…` 加成 `9999.99…` 而失败——这是最强的浮点判别）

### Scenario: 两家不等筹码、多名次派彩

- GIVEN 两家筹码分别为 A=`3000`、B=`1000`，派彩为 `[100, 60]`（cents）
- WHEN 计算 ICM 权益
- THEN A 的权益精确等于 `Fraction(90, 1)`（A 夺冠 `3/4`×100 + A 亚军 `1/4`×60）
- AND B 的权益精确等于 `Fraction(70, 1)`（`1/4`×100 + `3/4`×60）

### Scenario: 三家不等筹码的经典分布（逐家精确值）

- GIVEN 三家筹码 A=`5000`、B=`3000`、C=`2000`，派彩 `[500, 300, 200]`
- WHEN 计算 ICM 权益
- THEN A 的权益精确等于 `Fraction(5375, 14)`
- AND B 的权益精确等于 `Fraction(655, 2)`（即 `4585/14`）
- AND C 的权益精确等于 `Fraction(2020, 7)`（即 `4040/14`）
- AND 三家之和精确等于 `Fraction(1000, 1)`

### Scenario: 派彩名次少于座位数，未入钱名次派彩为 0（常规锦标赛）

- GIVEN 四家筹码 `[4000, 3000, 2000, 1000]`，派彩仅两个名次 `[500, 300]`
- WHEN 计算 ICM 权益
- THEN 每家权益按第 3、4 名派彩为 `0` 的 Malmuth-Harville 展开求得（精确有理数）
- AND 四家权益之和精确等于 `Fraction(800, 1)`（只有前二入钱，总额 800）

### Scenario: 单人剩余

- GIVEN 一家筹码 `[1000]`，派彩 `[500]`
- WHEN 计算 ICM 权益
- THEN 该家权益精确等于 `Fraction(500, 1)`（P(第 1 名)=1）

## Requirement: 派彩结构、输入校验与守恒

The system SHALL validate stacks and payout structure in a fixed precedence, reject each illegal condition in isolation with a distinct equatable error, and guarantee that the equities sum exactly to the total awarded payout.

校验优先级：`noPlayers` → `emptyPayouts` → `nonPositiveStack` → `negativePayout` → `morePayoutsThanPlayers` → `tooManySeats`。

### Scenario: 权益之和等于派彩总额（含未入钱尾）

- GIVEN 一组不对称筹码 `[4000, 3000, 2000, 1000]`、派彩 `[500, 300]`
- WHEN 计算 ICM 权益并用 `Fraction` 精确相加
- THEN 各家权益之和精确等于 `Fraction(800, 1)`（守恒对未入钱名次为 0 的尾同样成立）

### Scenario: 空筹码被拒（且合法输入成功）

- GIVEN 空筹码数组 `[]`、派彩 `[100]`
- WHEN 计算
- THEN 以 `ICMError.noPlayers` 拒绝（优先级高于 `morePayoutsThanPlayers`）
- AND 同派彩配上非空合法筹码 `[100]` 能返回权益（配对成功断言，防门禁永假）

### Scenario: 空派彩被拒（且合法输入成功）

- GIVEN 合法筹码 `[1000, 1000]`、空派彩 `[]`
- WHEN 计算
- THEN 以 `ICMError.emptyPayouts` 拒绝
- AND 同筹码配上非空派彩 `[100]` 能返回权益

### Scenario: 非正筹码与负派彩被分别拒绝

- GIVEN 筹码含 `0` 或负数（其余合法）→ 以 `ICMError.nonPositiveStack` 拒绝
- AND 派彩含负数（其余合法）→ 以 `ICMError.negativePayout` 拒绝
- WHEN 各自单独违规计算
- THEN 两种错误可判等且互不相同；各自去掉该违规后能返回权益

### Scenario: 名次数超过座位数被拒（且相等/更少时成功）

- GIVEN 两家筹码 `[1000, 1000]`、派彩三名次 `[100, 60, 40]`
- WHEN 计算
- THEN 以 `ICMError.morePayoutsThanPlayers` 拒绝
- AND 派彩降到 `[100, 60]`（名次数 = 座位数）能返回权益

### Scenario: 超过 64 座位被拒（64 座位成功）

- GIVEN 65 家筹码（名次递归用 `Int` 位掩码，65 位会丢位）
- WHEN 计算
- THEN 以 `ICMError.tooManySeats` 拒绝（宁可拒绝不可悄悄算错）
- AND 64 家能返回权益（边界内成功，防门禁永假）

## Requirement: 精确性与溢出保护

The system SHALL keep all intermediate arithmetic exact and, when an exact result would exceed the representable integer range, fail deterministically rather than return an approximate value. Exact `Int64`-rational ICM has a real ceiling — a field of large coprime stacks has an equity denominator (the LCM of products of running totals) beyond `Int.max` — so the calculator computes exactly for tables whose stacks share a chip unit (reducing to small integers, the realistic case) and reports `overflow` beyond, never approximating.

### Scenario: Fraction 构造即约分且分母恒正

- GIVEN 用 `numerator = 6`、`denominator = -3` 构造 `Fraction`
- WHEN 读取其分子分母
- THEN 得到约分且分母恒正的规范形 `-2/1`
- AND `0` 值规范化为 `0/1`

### Scenario: 中间运算溢出时报错而非近似（固定输入）

- GIVEN 两家筹码 `[3000, 1000]`、派彩 `[Int.max, 0]`
- WHEN 计算 ICM 权益（A 夺冠 `3/4` × `Int.max` 使分子 `3 × Int.max` 溢出）
- THEN 抛出 `ICMError.overflow`
- AND 绝不返回浮点近似或被截断的整数结果

### Scenario: 恰在阈值之下时成功（防溢出关卡退化为永抛）

- GIVEN 两家筹码 `[3000, 1000]`、派彩 `[Int.max / 4, 0]`
- WHEN 计算 ICM 权益（`3 × (Int.max / 4)` < `Int.max`）
- THEN 返回精确 `Fraction` 权益，不抛错

### Scenario: 共用筹码单位的现实决赛桌精确算出

- GIVEN 六家筹码共用 10000 单位 `[120000, 90000, 70000, 50000, 40000, 30000]`（归一为 `[12,9,7,5,4,3]`），派彩三名次 `[50000, 30000, 20000]`
- WHEN 计算 ICM 权益
- THEN 成功返回六个精确 `Fraction` 权益且不抛 `overflow`
- AND 六家权益之和精确等于 `Fraction(100000, 1)`（先按筹码 gcd 归一使中间分母收缩）

### Scenario: 超出精确 Int 范围的赛场报溢出而非近似

- GIVEN 九家几乎互质的大筹码（gcd 仅 1000 → `[125,98,76,61,45,33,22,14,8]`），派彩 `[50000, 30000, 20000]`
- WHEN 计算 ICM 权益
- THEN 精确权益分母超出 `Int.max`，抛 `ICMError.overflow`
- AND 绝不返回近似或截断值（精确数据铁律的落地：宁可报错不可悄悄算错）
