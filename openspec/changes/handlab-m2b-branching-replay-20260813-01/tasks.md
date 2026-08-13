---
name: handlab-m2b-branching-replay-20260813-01
status: planned
---

# 执行计划：M2B 第五切片（逐街回放与内容反事实）

铁律：先写红测试再实现。依赖夹具断言前置"确有产出"自检。

## Capability 追溯
| Requirement | Scenario | Task |
|---|---|---|
| 按到达的街正确回放 | 附录 A 四街牌面+行动数 | T1 |
| 按到达的街正确回放 | 翻前结束单街不补空 | T1 |
| 逐节点反事实/不重模拟/不产事件 | 命中反事实/未命中 uncovered 成对 | T2 |
| 逐节点反事实/不重模拟/不产事件 | 逐街行动==记录，不重模拟 | T1 |
| 逐节点反事实/不重模拟/不产事件 | 回放不产事件、命中补救+1 | T3 |

## T1 — HandReplayPresentation（逐街）
`covers:` hand-lab-replay
`PokerCoach/Features/HandLab/HandReplayPresentation.swift`：`ReplayStreet{street:Street; board:[Card]; actions:[ObservedAction]}`；`func replayStreets(of hand: ObservedHand) -> [ReplayStreet]`（board=该街 `ObservedStreet.board`、actions=该街 `actions` 逐字复制、只出到达的街）。无派生底池。
测试 `PokerCoachTests/HandReplayTests`：附录 A（`HandImportFixtureText.appendixA` 解析）→ 4 街、street 序 [preflop,flop,turn,river]、翻牌 board `[Ac,7h,2s]`/转牌 +Td/河牌 +9c、各街 actions.count `[6,3,2,3]`；每街 actions 与 `hand.streets[i].actions` 逐一相同（座位/种类/金额）。附录 I（`coOpenTrash`）→ 1 街、board 空。自检非空。**红灯**：每街塞最终 board → 翻牌 board 断言红；只取英雄行动 → 行动数断言红。

## T2 — 逐英雄节点反事实
`covers:` hand-lab-replay
`PokerCoach/Features/HandLab/HandReplayPresentation.swift`（或同 Feature 文件）+ VM：对 `hand.heroDecisionSignatures()` 每项调 `ImportedHandContentMatcher.classify(signature:action:)` 得 `NodeCoverage`；covered → 暴露 weight + coveringScenarioID（供补救），uncovered → 无 weight。
测试 `PokerCoachTests/HandReplayCounterfactualTests`：用 `HandLabContentFixture` 造覆盖附录 A 翻前节点、权重 6234 → 该节点反事实 weight==6234==`scenario.rangeWeightBasisPoints(...)`、暴露补救 scenarioID；翻后节点 `NodeCoverage.uncovered`、无 weight；空内容 → 全 uncovered（成对）。**红灯**：恒 covered → 空内容断言红。

## T3 — 可达 + 隔离 + 补救+1
`covers:` hand-lab-replay
`HandReplayView` 逐街展示 + 每英雄节点"你的行动 vs 内容频率" + 命中处"练这个漏洞"（复用第三切片 `makeRemediationSession`）。复盘→Hand Lab→某手→回放 可达。
测试 `PokerCoachTests/HandReplayIsolationTests`：种非空事件存储；回放附录 A 并浏览节点不发起训练 → 事件不变；从命中节点完成一道补救（注入固定 makeEventID/now）→ +1。`PokerCoachUITests/M2BReplaySurfaceTests`：复盘→Hand Lab→采纳附录 A→回放→见逐街与某节点反事实。**红灯**：回放写事件 → 不变断言红；补救入口断链 → +1 断言红。

## T4 — verify-m2b.sh
`covers:` 全部
UI 可达行加 `M2BReplaySurfaceTests`；新 App 单测随 `-only-testing:PokerCoachTests` 自动跑。

## 不变量
- `ObservedHand`/matcher/补救/契约语义未变；不触碰结算；不用 SessionSimulation 对手。
- `bash scripts/verify-m2b.sh` 通过。
