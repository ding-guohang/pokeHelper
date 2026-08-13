---
name: tournament-m3-icm-20260813-01
status: designed
---

# 设计：锦标赛 ICM 权益计算器（精确、内容无关）

## 概述

在 `TournamentEngine`（只依赖 PokerCore，实际只用标准库）加一个纯数学的 ICM 计算器。
核心难点是**精确表示**：ICM 权益是算出来的有理数商（如三家等筹码各 `10000/3`），
定点刻度必舍入，故用约分有理数 `Fraction`，运算溢出即抛错。ICM 是模型化数学、
不是策略真值，属引擎不属内容。

## 详细设计

### 1. `Fraction`（`Fraction.swift`）

精确有理数，`Sendable, Hashable, Comparable`。

- 存储 `numerator: Int`、`denominator: Int`；构造即规范化：约分（除以
  `gcd(|n|,|d|)`）、分母恒正（符号并入分子）、`0` → `0/1`。
- `init(numerator:denominator:)`：`denominator == 0` 走 `precondition` 崩溃
  （编程错误，非可恢复输入；ICM 永不喂它）。
- `init(_ whole: Int)` 便捷构造 `whole/1`。
- 算术为**具名 throwing 方法**（不用 throwing 运算符，避免 `try a + b`）：
  - `adding(_ other: Fraction) throws -> Fraction`
    ：`d = lcm(d1,d2)`，分子对齐后相加，全程 `multipliedReportingOverflow` /
    `addingReportingOverflow`，任一溢出抛 `ICMError.overflow`，结果再规范化。
  - `multiplied(by other: Fraction) throws -> Fraction`
    ：**先交叉约分**（`gcd(n1,d2)`、`gcd(n2,d1)`）再相乘，降低溢出概率。
  - `multiplied(byInteger k: Int) throws -> Fraction`：`n*k / d`，交叉约分 `k` 与 `d`。
- `Comparable`：`a<b` ⟺ `a.n*b.d < b.n*a.d`（分母恒正，方向不翻；同样 overflow-check，
  但比较仅用于测试/排序，必要时用 `adding` 差值判号——本切片比较用不到大数，直接
  交叉乘并在内部溢出时 precondition，因为比较不在 ICM 主算路径上）。
- gcd 用 `Int` 的欧几里得实现；注意 `Int.min` 取绝对值溢出——ICM 输入非负故不可达，
  加一行注释说明，不为它写测试。

### 2. `PayoutStructure`（`PayoutStructure.swift`）

`Hashable, Sendable`。持有 `amounts: [Int]`（cents，名次序）。校验放 `ICMCalculator`
入口统一做（非空、非负），保持与 slice-1「单行不自校验、聚合处校验」一致；这里做成
轻结构体或直接用 `[Int]` 传参。**决定用 `[Int]` 直接传参**，避免多一层类型；校验在
计算器入口。（若评审要求强类型再收敛。）

### 3. `ICMError`（`ICMError.swift`）

`Error, Equatable, Sendable`：`noPlayers`、`emptyPayouts`、`nonPositiveStack`、
`negativePayout`、`morePayoutsThanPlayers`、`tooManySeats`（>64 座位，位掩码限制）、
`overflow`。

### 4. `ICMCalculator`（`ICMCalculator.swift`）

`public enum ICMCalculator`（无状态，纯函数容器，仿 stdlib 风格）：

```
static func equities(chipStacks: [Int], payouts: [Int]) throws -> [Fraction]
```

入口校验（固定优先级）：
1. `chipStacks` 空 → `noPlayers`
2. `payouts` 空 → `emptyPayouts`
3. 任一 stack ≤ 0 → `nonPositiveStack`
4. 任一 payout < 0 → `negativePayout`
5. `payouts.count > chipStacks.count` → `morePayoutsThanPlayers`

**归一**：`g = gcd(all stacks)`；`normalized = stacks.map { $0 / g }`。ICM 只依赖比例，
归一后中间分母显著变小（`[5000,3000,2000]`→`[5,3,2]`），真实九人桌不虚假溢出。

**Malmuth-Harville，只枚举入钱名次**：未入钱名次派彩为 0、对权益无贡献，故只需
计算前 `K = payouts.count` 个名次的概率 `P[i][k]`（k∈0..<K），无需 O(n!) 全排列。
这是**正确性与溢出的关键**：全枚举到所有名次的中间分母是「剩余筹码总和」的 n-1
连乘（归一后九人桌仍 ~482⁸≈6.5e19，溢出 Int64）；只到第 K 名则分母至多 K 个总和
连乘（K=3、S=482 → ~1e8，稳在 Int64 内）。

递归按名次序展开，只走 K 层：
```
// P[i][k]：玩家 i 名列第 k 的概率（k∈0..<K）
accumulate(usedMask, depth, probSoFar, removedSum):
    if depth == K { return }              // 只需前 K 名，其余派彩 0
    total = S - removedSum                 // S = Σ 归一后筹码
    for j not in usedMask:
        pj = Fraction(stacks[j]).multiplied(by: Fraction(1, total))   // s_j / total
        contribution = probSoFar.multiplied(by: pj)
        P[j][depth] = P[j][depth].adding(contribution)
        accumulate(usedMask | bit(j), depth + 1, contribution, removedSum + stacks[j])
accumulate(0, 0, Fraction(1), 0)
```
复杂度 O(n^K)（n=9,K=3 → 729）。K=0 不可达（`emptyPayouts` 已挡）。`usedMask`
用 `Int` 位掩码（n≤63 足够）。
- 权益_i = Σ_{k<K} `P[i][k].multiplied(byInteger: payouts[k])` 累加（`adding`）。

所有中间量走 `Fraction` throwing 方法，溢出即冒泡 `ICMError.overflow`。

**诚实的精确边界**：精确 `Int64` 有理数有真实上限——权益分母是各项分母的 LCM，
互质大筹码的满座赛场（如九家 gcd 仅 1000、归一后 `[125,98,76,...]`）其精确分母
超 `Int.max`，此时**报错是正确行为**（宁可报错不可悄悄算错），不是缺陷，也不是靠
换 `Int128`/大数就能消除（病态输入总会溢出，溢出路径必须存在）。现实决赛桌筹码
共用单位（如都是 10000 的倍数），归一后是小整数，落在精确范围内。归一 + 只枚举
入钱名次 + 交叉约分共同把现实规模压进 `Int`；派彩本身很大（如 `Int.max`）时最终乘
payout 仍会溢出 → 正确抛 `overflow`。

## Capability 覆盖

| Requirement | 实现 |
|---|---|
| 精确 ICM 权益计算（含零尾） | `equities` + `payoutAt` 零尾；`Fraction` 精确 |
| 派彩结构、输入校验与守恒 | 入口五级校验 + 隔离错误测试 + 守恒（概率行和=1） |
| 精确性与溢出保护 | `Fraction` 规范化 + reportingOverflow + 归一 + 交叉约分 |

## 影响范围

新增 4 源文件 + 1 测试文件，均在 `TournamentEngine`。无 App/UI/网络/契约变更。
`check-package-layering.sh` 按目录 glob 自动覆盖，无需改门禁。

## 风险与测试策略

- 溢出：`[3000,1000]+[Int.max,0]` 抛 overflow；`[..,Int.max/4,0]` 成功；真实九人桌
  `[125000,...,8000]+[50000,30000,20000]` 不溢出且和 `100000/1`。三面钉死。
- 浮点渗入：Scenario 1 `10000/3` + `3×(10000/3)==10000/1` 守恒断言判别 `Double`。
- 逐家精确值 `5375/14`、`655/2`、`2020/7` 已独立手算校验，和 `1000/1`。
- 每个错误配「去掉违规后成功」的对照断言，防门禁退化永假。

## 测试框架

Swift Testing（`@Test`/`#expect`），与 `BlindScheduleTests` 一致；错误断言用
`#expect(throws: ICMError.xxx)`。
