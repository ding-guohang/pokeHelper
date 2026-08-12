# 审需报告：handlab-m2b-hand-analysis-20260812-01

日期：2026-08-12
方式：派两个窄范围 agent（可测试性、架构一致性）独立审，逐条对代码复核，据此重写 proposal 并收窄范围。

## 结论

**初稿不通过，需重大修改。已按审出问题重写并收窄范围，重写后有条件通过——可进入 plan。**

## 一、结构性问题（复核成立，导致收窄）

| 指控 | 复核 | 结果 |
|---|---|---|
| `KeyHandSelection` 是手粒度，不适用于节点 | 读 `KeyHandSelection.swift`：`KeyHandFacts` 一手一条、`select` 从**手列表**选、`.bigPot`="session 五大底池之一" | 成立。一手 `ObservedHand` 只映射一条 facts → 引擎只吐 1 项，撑不起"节点 3–5" |
| `bigSwing` 算不了 | 读 `ObservedHand.swift:149-157`：`ObservedResult` 只有 `rakeCentiBB`，grep `payout/winner/collected` 于 HandHistory 源为空 | 成立。英雄净额需派彩，模型没有；`bigSwing` 无法计算 |
| 派彩要补进 `ObservedHand` | 同上 | 属第一切片模型改动（会重生成其黄金），本切片不碰 |

据此**收窄**：节点粒度分析，关键节点理由只保留 `deviation` 与 `allIn`（均可从 `ObservedHand` 算出），不复用 `KeyHandSelection`，不做 `bigSwing`/`bigPot`。

架构复核同时确认可行的部分：`SpotSignature`/`SpotCoverageKey`/`FacingAction`/`StackBucket`/`HandClass` 均在 PokerCore，`HandHistory`（仅依赖 PokerCore）可产出签名；`ObservedHand` 的逐街到位额 + `forcedPosts` + `startingStackCentiBB` 足以重建每个英雄决策点的 `facing` 与 `stackBucket`；App 层内容匹配仿 `SessionContentMatcher`、`check-package-layering.sh` 无需改（只查 `Packages/*`）；隔离协调器模式已存在（`HandImportCoordinator` 持有事件存储却不写），只需加分析入口；`FacingAction(priorRaiseCount:)`/`StackBucket(effectiveStack:)` 均 public，可作测试参考值。

一个新记的缺口：`ObservedHand` 无显式英雄座字段——术语已定"英雄座 = 唯一 `.known` 座位"，并记其依赖第一切片"对手明牌暂不读取"的限制。

## 二、可测试性问题（重写已修）

| 初稿问题 | 重写对策 |
|---|---|
| 关键节点计数依赖不存在的节点适配、`bigPot` 手粒度 | 节点粒度选择；上界 5、下界可为 0（附录 A 空内容为空集）、6-偏离构造牌谱恰取 5 |
| 偏离单调性无牙口（恒定幅度可蒙混）、"偏离幅度"未定义 | 定义 `偏离幅度=10000−w`，单独断言其严格随 w 递减（纯函数）；再用 `32o`(权重0) vs `AKo`(高权重) 成对断言 flag 两向 |
| "两个独立进程"没钉 harness | 加 `hand-model-writer --signatures` + 黄金 `sample-ps-6max-nlhe.signatures.json`，跨进程字节比对 |
| 三个 GIVEN 夹具未提交 | 附录 F（面对加注）、G（`32o` 开池）、H（英雄全下）随本切片提交并钉死；复用已提交的附录 A |
| 只断言翻前 facing/stackBucket，stackBucket 恒 10000 可蒙混 | 附录 A 四节点逐街断言 facing 与随街变化的 stackBucket（10000/9700/9300/9300） |
| "无内容可对照""偏离幅度"是软标签 | 给出具体表示：节点 `covered(scenarioID, weight)`/`uncovered`；偏离幅度仅 covered 有 |

审需认可的范本（未动）：隔离场景成对"确有产出 + 存储不变"、覆盖 vs 未覆盖成对、不钉脆弱的基点魔数（只断言取自范围表 + 结构性 covered/flagged/monotonic）。

## 三、规格完整性

| Capability | Requirements | Scenarios |
|---|---|---|
| imported-hand-signatures | 1 | 3 |
| imported-hand-analysis | 2 | 8 |
| **合计** | **3** | **11** |

3 个 Requirement 全含 SHALL，11 个 Scenario 全含 GIVEN/WHEN/THEN，无 TODO/TBD；`Modified: 无`，与现有 24 个 spec 无冲突。

## 四、留给 plan 阶段的决断

1. 签名序列规范序列化的确切字段与 `--signatures` 输出形态（钉黄金 `sample-ps-6max-nlhe.signatures.json`）。
2. 英雄决策点的下注状态重建放 `HandHistory` 的哪个类型；`facing`/`stackBucket` 的 effective-stack 口径与 M2A `HandState` 对齐。
3. `ImportedHandContentMatcher` 与分析协调器在 App 层的落点（`Infrastructure/HandLab` vs `Features/HandLab`）。
4. `32o` 在已发布 rfi-btn 范围中的实际权重需在实现期对着 pack 核实（预期 0）；若非 0，改选一个范围确实以 0 权重对待的手。
