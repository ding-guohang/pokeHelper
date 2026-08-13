---
name: tournament-m3-icm-20260813-01
status: planned
---

# 任务计划：锦标赛 ICM 权益计算器

TDD：每个 Task 先写失败测试 → 最小实现 → 目标测试通过 → 全包测试。

## Capability 追溯

| Task | covers |
|---|---|
| 1 | tournament-icm / 精确性与溢出保护（Fraction 规范化 + 溢出） |
| 2 | tournament-icm / 派彩结构、输入校验与守恒（错误 + 优先级） |
| 3 | tournament-icm / 精确 ICM 权益计算（MH、零尾、逐家精确值、守恒） |
| 4 | tournament-icm / 精确性与溢出保护（溢出/阈值下/真实九人桌） |

## Task 1 — `Fraction` 精确有理数
covers: 精确性与溢出保护
- RED：`FractionTests` —
  - `Fraction(6, -3)` → `numerator == -2, denominator == 1`；`Fraction(0, 5)` → `0/1`。
  - `Fraction(10000, 3)` 保持 `10000/3`（gcd=1）。
  - `Fraction(1,2).adding(Fraction(1,3))` == `Fraction(5,6)`。
  - `Fraction(3,4).multiplied(byInteger: 100)` == `Fraction(75,1)`。
  - `Fraction(2,3).multiplied(by: Fraction(3,2))` == `Fraction(1,1)`（交叉约分）。
  - `Fraction(1,1).multiplied(byInteger: Int.max).adding(Fraction(1,1)) ...` 造溢出 →
    `#expect(throws: ICMError.overflow)`（用 `Fraction(3,1).multiplied(byInteger: Int.max)`）。
- GREEN：实现 `Fraction`（规范化、gcd、`adding`/`multiplied(by:)`/`multiplied(byInteger:)`
  用 `*ReportingOverflow` 抛 `ICMError.overflow`），`Sendable,Hashable,Comparable`。

## Task 2 — `ICMError` + 入口校验
covers: 派彩结构、输入校验与守恒
- RED：`ICMValidationTests` —
  - `[]` + `[100]` → `noPlayers`；`[100]` + `[100]` 成功。
  - `[1000,1000]` + `[]` → `emptyPayouts`；配 `[100]` 成功。
  - `[0,1000]`/`[-1,1000]` + `[100]` → `nonPositiveStack`；`[1,1000]` 成功。
  - `[1000,1000]` + `[100,-1]` → `negativePayout`；`[100,1]` 成功。
  - `[1000,1000]` + `[100,60,40]` → `morePayoutsThanPlayers`；`[100,60]` 成功。
- GREEN：`ICMError`（6 case，`Error,Equatable,Sendable`）+ `ICMCalculator.equities` 入口
  五级校验（顺序：noPlayers→emptyPayouts→nonPositiveStack→negativePayout→morePayoutsThanPlayers）。

## Task 3 — Malmuth-Harville 精确权益
covers: 精确 ICM 权益计算
- RED：`ICMEquityTests` —
  - `[1000,1000,1000]` + `[5000,3000,2000]` → 每家 `Fraction(10000,3)`，和 `Fraction(10000,1)`。
  - `[3000,1000]` + `[100,60]` → `[Fraction(90,1), Fraction(70,1)]`。
  - `[5000,3000,2000]` + `[500,300,200]` → `[Fraction(5375,14), Fraction(655,2), Fraction(2020,7)]`，和 `Fraction(1000,1)`。
  - `[4000,3000,2000,1000]` + `[500,300]` → 和 `Fraction(800,1)`（零尾）。
  - `[1000]` + `[500]` → `[Fraction(500,1)]`。
- GREEN：gcd 归一 + `payoutAt` 零尾 + 递归 `finishProbabilities` + 权益累加。

## Task 4 — 溢出保护与真实规模
covers: 精确性与溢出保护
- RED：`ICMOverflowTests` —
  - `[3000,1000]` + `[Int.max,0]` → `#expect(throws: ICMError.overflow)`。
  - `[3000,1000]` + `[Int.max/4,0]` → 成功（不抛）。
  - 九家 `[125000,98000,76000,61000,45000,33000,22000,14000,8000]` + `[50000,30000,20000]`
    → 成功、九个 `Fraction`、和 `Fraction(100000,1)`、不抛 overflow。
- GREEN：确认归一 + 交叉约分使九人桌在 `Int` 内；溢出路径冒泡。

## Task 5 — 门禁与回归
covers: 全部
- `swift test --package-path Packages/TournamentEngine` 全绿。
- `bash scripts/check-package-layering.sh` 通过。
- 更新 `openspec/changes/archive/index.md`（归档时）。
