---
name: handlab-m2b-branching-replay-20260813-01
status: designed
---

# 技术方案：M2B 第五切片（逐街回放与内容反事实）

审需已定行为；这里写结构与决断。

## 结构
```
HandHistory: ObservedHand.streets（每街 board+voluntary actions）、heroDecisionSignatures()
App Infrastructure/HandLab: ImportedHandContentMatcher.classify(signature:action:)（第四切片）
App Features/HandLab:
  HandReplayPresentation  ← 新增：ObservedHand → [ReplayStreet{street,board,actions}]（无派生底池）
  逐英雄节点反事实：heroDecisionSignatures() → classify → covered(weight)/uncovered
  HandReplayView          ← 新增：逐街展示 + 每英雄节点"你的行动 vs 内容频率" + 命中处"练这个漏洞"（复用第三切片入口）
```

## 决断
1. **不派生底池**：`ReplayStreet` 只含 `street`、`board`（该街可见牌）、`actions`（该街 `ObservedStreet.actions`，逐字复制）。不算 potAtEnd（避免为导入牌重实现结算/边池/未跟注返还，防显示错误底池）。
2. **逐街构造仿 M2A 语义**：board 是该街期间可见的牌（= `ObservedStreet.board`），actions 只含该街、按记录序、含所有玩家；只出实际到达的街，不补空街。
3. **反事实复用**：对每个 `HeroDecisionSignature` 调 `classify(signature:action:)`；`covered(scenarioID, weight)` → 显示 weight（内容对该 handClass+行动的频率）+ 可补救；`uncovered` → "无内容可对照"、不显频率。命中节点的 scenarioID 交第三切片 `makeRemediationSession` 起既有训练。
4. **可达**：复盘→Hand Lab→某手→回放（与"分析"并列的 NavigationLink）。

## Capability 覆盖
| Capability | 落点 | 关键测试 |
|---|---|---|
| hand-lab-replay | App Features/HandLab 回放呈现+视图 | 附录 A 四街牌面/行动数 [6,3,2,3]；附录 I 单街；行动逐街==记录；covered 6234/uncovered 成对；回放不产事件、命中补救+1；UI 可达 |

## 不变量
- `ObservedHand`/matcher/补救/`DecisionSessionViewModel`/契约语义未变；不触碰结算；不用 `SessionSimulation` 对手。
- `bash scripts/verify-m2b.sh` 通过。
