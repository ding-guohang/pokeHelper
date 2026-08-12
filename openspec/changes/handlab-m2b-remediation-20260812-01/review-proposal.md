# 审需报告：handlab-m2b-remediation-20260812-01

日期：2026-08-12
方式：派可测试性与架构一致性两个 agent 独立审，逐条对代码复核，据此重写。

## 结论

**初稿有一处阻塞性事实错误，已按审出问题重写，重写后有条件通过——可进入 plan。**

## 复核成立的问题

| # | 指控 | 复核 | 处置 |
|---|------|------|------|
| F1(阻塞) | `KeyNode` 并不携带覆盖 `scenarioID` | `ImportedHandKeyNodeSelection.swift:46` 把 `.covered(_, weight)` 的 id 丢弃；`KeyNode` 只有 signature/reason/deviationMagnitude | 本切片显式追加 `coveringScenarioID`（加法，不改 analysis 的 scenario）；补救场景 ID 据节点导出，用 BTN/CO 两覆盖场景防常量 |
| F2 | 场景 4 只断言 +1，未绑定事件到 S | 读原场景 | 改为断言新事件 `scenarioID == S` 并进维度 D |
| F3 | "逐字段相等"不能用 `TrainingEvent.==`（含 id/时间/设备），"同 grade" 欠明确 | `TrainingEvent.swift:40-60` `==` 含三者；`DecisionGrade` 有 9 字段 | 明确排除 id/occurredAt/deviceID、其余含**完整 grade** 逐字段比 |
| F4 | 新桥具写事件能力，slice-2 隔离测试不覆盖该路径 | slice-2 测的是 `HandImportCoordinator` | 新增场景：打开分析不发起训练则事件不变 |
| F5 | "未覆盖节点"不可作为 `KeyNode` 构造 | `selectKeyNodes` 只出 deviation/allIn 节点 | "不可补救"改用 `allIn` 关键节点（可构造）与 deviation 成对 |

架构复核确认：`DecisionSessionViewModel` 仅需 `scenarioID`（自行解析场景、构造事件），`AppDependencies.makeDecisionSessionViewModel(scenarioID:)` 已注入全部依赖；`TrainingEvent` 无编码来源的字段，补救事件与直接训练结构性无从区分；冻结契约无需改。

## 规格完整性

1 capability、2 requirements（全 SHALL）、5 scenarios（全 GIVEN/WHEN/THEN），无 TODO；`Modified: 无`（`KeyNode` 加法不改 analysis scenario，Impact 明记）。

## 留给 plan 的决断

1. `coveringScenarioID` 加在 `KeyNode` 上（App 层类型），`selectKeyNodes` 对 deviation 保留；确认不破坏 slice-2 的 cap/排序测试（加字段向后兼容）。
2. 补救桥的落点（`Features/HandLab` 呈现 + 复用 `makeDecisionSessionViewModel`）；附录 I（CO 开 32o）随本切片提交。
