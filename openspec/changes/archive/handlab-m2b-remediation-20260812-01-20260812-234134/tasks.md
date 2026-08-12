---
name: handlab-m2b-remediation-20260812-01
status: planned
---

# 执行计划：M2B 第三切片（补救训练）

铁律：先写红测试再实现。依赖夹具的断言前置"夹具确有产出"自检。

## Capability 追溯
| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| imported-hand-remediation | 偏离节点暴露覆盖场景并发起补救 | 覆盖场景就是分析判定的场景 | T1,T2 |
| imported-hand-remediation | 偏离节点暴露覆盖场景并发起补救 | 全下节点不提供补救 | T1,T2 |
| imported-hand-remediation | 补救事件与直接训练无从区分 | 事件按字段相等 | T3 |
| imported-hand-remediation | 补救事件与直接训练无从区分 | 事件绑定 S 进画像 | T3 |
| imported-hand-remediation | 补救事件与直接训练无从区分 | 打开分析不发起不产生事件 | T4 |

## T1 — KeyNode.coveringScenarioID（加法）
`covers:` imported-hand-remediation
`PokerCoach/Infrastructure/HandLab/ImportedHandKeyNodeSelection.swift`：`KeyNode` 加 `let coveringScenarioID: String?`；`selectKeyNodes` 对 `.covered` 的 deviation 保留其 scenarioID，allIn 置 nil。提交附录 I 文本 `HandImportFixtureText.coOpenTrash`（`32o` 从 CO 开池，其余同附录 A 结构）。
测试 `ImportedHandKeyNodeTests` 增：附录 G 偏离节点 `coveringScenarioID=="rfi-btn"`、附录 I 为 `"rfi-co"`、两者不同；附录 H 的 allIn 节点 `coveringScenarioID==nil`。**红灯**：常量返回 "rfi-btn" → 附录 I 断言红。确认 slice-2 既有测试仍绿（加字段向后兼容）。

## T2 — 补救桥
`covers:` imported-hand-remediation
`PokerCoach/Features/HandLab/HandRemediation.swift`：`func remediationScenarioID(for node: KeyNode) -> String?`（deviation 且有 coveringScenarioID 才返回，否则 nil）。分析视图模型据此对 deviation 行暴露"练这个漏洞"，点按经 `dependencies.makeDecisionSessionViewModel(scenarioID:)` 呈现既有训练。
测试 `PokerCoachTests/HandRemediationTests`：deviation 节点 → 返回其 coveringScenarioID；allIn 节点 → nil。**红灯**：恒返回非 nil → allIn 断言红。

## T3 — 补救事件 == 直接训练事件
`covers:` imported-hand-remediation
测试 `PokerCoachTests/HandRemediationEventTests`：以固定 `makeEventID`/`now`/`deviceID` 各构造两个 `DecisionSessionViewModel`——一个 scenarioID 来自附录 G 偏离节点的 coveringScenarioID（补救），一个直接传 `"rfi-btn"`（直接）；两者提交相同 action+confidence 完成。断言事件存储各 +1；两事件 `scenarioID`(=="rfi-btn")/`strategyPackID`/`strategyContentVersion`/`abilityDimension`/`submission`/完整 `grade` 逐字段相等；仅 id/occurredAt/deviceID 允许不同（不用 `TrainingEvent.==`）。再断言补救事件经 `PlayerModelReducer.reduce` 计入该场景维度。**红灯**：桥若自造事件路径改任一字段 → 相等断言红。

## T4 — 打开分析不写事件
`covers:` imported-hand-remediation
测试 `PokerCoachTests/HandRemediationIsolationTests`：种非空事件存储；走分析路径（`HandAnalysisCoordinator.analyze` + 桥）读取关键节点但不发起训练；断言事件存储条数与内容不变。**红灯**：桥在读取时写事件 → 断言红。

## T5 — UI 可达
`covers:` imported-hand-remediation
`HandAnalysisView` 为 deviation 行加"练这个漏洞"按钮 → 呈现既有 `DecisionSessionView`。`PokerCoachUITests/M2BRemediationSurfaceTests`：复盘→Hand Lab→采纳附录 G→分析→点"练这个漏洞"→出现训练界面→提交行动与信心→见反馈。**红灯**：不接入 → 找不到入口。

## T6 — verify-m2b.sh
`covers:` 全部
`scripts/verify-m2b.sh` 的 UI 可达行加 `M2BRemediationSurfaceTests`（新 App 单测随 `-only-testing:PokerCoachTests` 自动跑）。

## 不变量
- `TrainingEvent`/契约/`DecisionSessionViewModel`/`imported-hand-analysis` scenario 未变。
- `bash scripts/verify-m2b.sh` 通过。
