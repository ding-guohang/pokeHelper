---
name: handlab-m2b-remediation-20260812-01
status: designed
---

# 技术方案：M2B 第三切片（补救训练）

审需已把行为定死；这里写结构与决断。

## 结构

```
KeyNode (App/Infrastructure/HandLab)  ← 加法：coveringScenarioID: String?（deviation 保留，allIn 为 nil）
   │
Features/HandLab/HandAnalysisView  ← deviation 行加"练这个漏洞"入口
   │ coveringScenarioID
AppDependencies.makeDecisionSessionViewModel(scenarioID:)  ← 既有工厂，产出既有训练流程
   │
DecisionSessionViewModel → DecisionScorer → TrainingEvent(scenarioID:…) → eventStore.append  ← 既有管线，事件天然普通
```

## 决断
1. **`coveringScenarioID` 加在 `KeyNode`**（App 层类型）。`selectKeyNodes` 对 `.covered` 的 deviation 节点保留 `scenarioID`，allIn 节点为 `nil`。加法，slice-2 的 cap/排序/理由测试不受影响（不断言字段集）。
2. **补救就是既有训练**。桥只做：deviation 节点 → 取 `coveringScenarioID` → `dependencies.makeDecisionSessionViewModel(scenarioID:)`。不新造事件路径，故补救事件与直接训练同场景的事件除 id/时间/设备外结构性相等。
3. **打开分析不写事件**：分析读取只经 `HandAnalysisCoordinator`（slice-2，持有存储不写）；写事件只发生在用户完成一道经既有管线的补救训练。
4. **附录 I**（CO 开 `32o`，被 `rfi-co` 覆盖）随本切片提交，与附录 G（BTN→`rfi-btn`）构成不同覆盖场景，防"写死常量"。

## Capability 覆盖
| Capability | 落点 | 关键测试 |
|---|---|---|
| imported-hand-remediation | `ImportedHandKeyNodeSelection`(+coveringScenarioID)、`Features/HandLab` 桥与视图 | coveringScenarioID BTN≠CO/allIn 为 nil；补救 vs 直接训练事件逐字段相等；事件绑定 S 进画像 D；打开分析不写事件；UI 可达 |

## 不变量
- 不改 `TrainingEvent`/契约/`DecisionSessionViewModel` 语义；`imported-hand-analysis` 的 scenario 不变（KeyNode 加字段是加法）。
- `bash scripts/verify-m2b.sh` 通过（含 m1a/m1c/m2a）。
