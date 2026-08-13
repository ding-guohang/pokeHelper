---
name: tournament-m3-structure-20260813-01
status: designed
---

# 技术方案：M3 第一切片（盲注结构与筹码模型）

审需已定行为；这里写结构与决断。

## 结构
```
PokerCore（不变）
   │
TournamentEngine（新增，只依赖 PokerCore）
   BlindLevel{level,smallBlindChips,bigBlindChips,anteChips}  Hashable/Sendable/Codable
   BlindSchedule  throwing init 校验 → BlindScheduleError(Equatable)
     level(atHandIndex:handsPerLevel:) -> BlindLevel   (precondition handIndex>=0, handsPerLevel>=1；末级 clamp)
   effectiveBigBlinds(chips:Int, level:BlindLevel) -> Int   (= chips / level.bigBlindChips, 向下取整; precondition chips>=0)
```

## 决断
1. **新包 TournamentEngine（PokerCore-only）**，`Package.swift` 仿 SessionSimulation（warnings-as-errors + strict-concurrency=complete）。
2. **整数 chips，非 BBAmount**：锦标赛 BB 逐级升，深度据算 `chips / bigBlindChips` 向下取整；模型只存整数 chips。
3. **校验集中在 `BlindSchedule.init`（throwing）**，`BlindScheduleError` 为 `Equatable` 枚举：`empty`、`levelsNotStartingAtOne`、`levelsNotConsecutive`、`bigBlindNotStrictlyIncreasing(level:)`、`smallBlindExceedsBigBlind(level:)`、`nonPositiveBigBlind(level:)`、`negativeAnte(level:)`。逐个可判等、互不相等。
4. **level 查询与深度的输入守卫用 precondition**（handIndex>=0、handsPerLevel>=1、chips>=0），仿 M2A `TableRules` 风格；`bigBlindChips>0` 由校验保证故深度不除零。
5. **门禁与文档同步**：`check-package-layering.sh` 加 `TournamentEngine may only see PokerCore`；`docs/architecture/layering.md` 层图纳入。

## Capability 覆盖
| Capability | 落点 | 关键测试 |
|---|---|---|
| tournament-structure | `TournamentEngine`：BlindSchedule/BlindLevel/effectiveBigBlinds | 合法接受+级别查询(0/9/10/19/20/100)；7 类非法各因；深度 30 vs 15/250→2/0→0 |

## 不变量
- 不依赖/不改 SessionSimulation、StrategyContent、TrainingEvent、Scorer；无位置、无现金评分变化。
- `check-package-layering.sh` 通过（含新条目）；`bash scripts/verify-m2b.sh` 仍通过（它兜底 m1a/m1c/m2a；本切片不影响它们）。
