# 审需报告：tournament-m3-structure-20260813-01

日期：2026-08-13
方式：可测试性与架构一致性两个 agent 独立审，逐条复核，据此重写。

## 结论
初稿方向对，但有三个未测的校验守卫、一处边界未钉、一处不可证伪断言，及一处**误引用**（把不存在的"CLAUDE.md M3 gate"当逐字引用）。已全部修正，重写后有条件通过——可进入 plan。

## 修正（据审需）
| 问题 | 对策 |
|---|---|
| 误引 CLAUDE.md M3 gate（该句不存在） | 改为据 `scope-and-milestones.md` M3 行 + CLAUDE.md 位置复用约定的转述，不加伪引号 |
| `bigBlindChips > 0` 未测（除零守卫） | 非法枚举加 `BB==0`，明确它是有效深度除零来源 |
| 负 ante 未测 | 非法枚举加 `anteChips < 0` |
| 级别"从 1 开始"未测 | 非法枚举加"首级为 2" |
| `handsPerLevel`/`handIndex` 无下界（除零/负） | 术语声明为被守卫的 precondition（仿 M2A handIndex 守卫） |
| L2→L3 边界未钉 | 级别查询加 19→L2、20→L3 |
| "不出现负深度"不可证伪 | 删除该恒真断言，保留 0→0 下界样例并说明结构性非负 |
| 新包只提脚本、未提层图文档 | Impact 补：同步更新 `docs/architecture/layering.md` |

架构复核确认：新包 `TournamentEngine`（PokerCore-only）与层图一致、脚本仿 HandHistory 加一条即可；不用 `BBAmount`（centi-BB 是现金单位，锦标赛 BB 逐级升，故用整数 chips + 据算深度）；不碰 TrainingEvent/Scorer/SessionSimulation/StrategyContent，结构性无法改现金评分；`tournament-structure` 系全新能力，`Modified: 无` 准确；本切片无位置内容，无需现在兑现 tableSize+offset 约定。

## 规格完整性
1 capability、2 requirements（全 SHALL）、4 scenarios（全 GWT），无 TODO；`Modified: 无`。
