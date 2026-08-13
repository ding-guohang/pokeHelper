# 审需报告：handlab-m2b-branching-replay-20260813-01

日期：2026-08-13
方式：可测试性 agent 深审；架构 agent 中途失败未出结论，其检查点已在起草阶段实测确认（`ObservedHand.streets` 为数据源、`ObservedResult` 仅有 rake 故无底池字段、`classify(signature:action:)`/`heroDecisionSignatures()` 可复用、HandHistory 无对手模型、回放在 App 层），并与可测试性 F4 相互印证。

## 结论
初稿方向对但底池断言过弱且暗含"重实现结算"的坑，已重写：**去掉派生底池**、钉逐街牌面与行动数、成对反事实、经回放自身入口验证补救 +1。重写后有条件通过——可进入 plan。

## 关键修正（据审需）
| 问题 | 对策 |
|---|---|
| F1(高) potAtEnd 需为导入牌重实现结算；附录 A 转/河底池恰等最终底池，"非递减+非最终"既被常量也被"未跟注重复计数(2250)"蒙混 | **不显示派生底池**（Non-Goal），回放只呈现每街牌面+行动；避免触碰结算与显示错误底池 |
| F3 只回放英雄行动可蒙混 | 钉各街自主行动数 `[6,3,2,3]`（含所有玩家；与 slice-2 已提交的"合计 14"一致；审员的 [3,3,2,2] 系误算） |
| F2 "不产生事件"与"补救 +1"仅口头复用 | 新增：经**回放自身**补救入口完成一道 → 事件恰 +1，证明入口是活的、"不变"非断链 |
| F5 输入未点名 | 附录 A（覆盖/未覆盖同存）、附录 I（翻前即结束）点名复用 |
| 完整性核心 | 断言回放逐街行动与 `ObservedHand.streets.actions` 逐一相同（座位/种类/金额），不发明对手后续 |

认可范本：反事实权重 6234 钉到 `rangeWeightBasisPoints(...)` 非整值、covered/uncovered 成对、逐街牌面钉死、翻前单街不补空、非空存储播种。

## 规格完整性
1 capability、2 requirements（全 SHALL）、5 scenarios（全 GWT），无 TODO；`Modified: 无`。
