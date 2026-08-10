# 评审报告：curriculum-m1c-adaptive-cash-20260810-01

日期：2026-08-10
方式：四个并行 agent（规格合规 / 代码质量 / 项目规范 / 对抗性「绿但空」）
范围：`cc19423^..HEAD`，25 个提交，88 个文件

## 结论

**不通过 — 不可归档。**

`verify-m1c.sh` 全绿、229 条 App 测试全绿、67 条领域测试全绿，但其中**三个能力在 App 里根本不可达**，两处领域逻辑使功能永远无法达成，多道门禁形同虚设。这与 M1B 那轮的失效形态相同：单元测试覆盖了组件，没有任何东西覆盖「组件是否接进了产品」。

两个 agent（规格合规、项目规范）因读入范围过大耗尽上下文，最终回复被截断，需以更窄范围重跑。这是我派发时的错误，不是它们的。

---

## A 类：测试全绿，产品里是死的

### A1. `ContentUpdateCoordinator` 零生产调用者（Critical）

130 行实现 + 9 条测试，`AppDependencies` 从不构造它，没有任何 `ContentUpdateSource` 的非测试实现，`checkForUpdate()` 从未被调用。

```
生产引用 0   测试引用 15
```

proposal 的 `内容随包交付与可选更新` 挂了 5 个场景，全绿，**没有一个能在运行中的 App 里发生**。

### A2. 诊断被计算但从未渲染（Critical）

提交 2b39687 标题是「surface the diagnostic ... on Today」。`TodayViewModel` 暴露了
`diagnostic`、`showsDiagnosticEntry`、`showsDiagnosticPrompt`、`diagnosticProgressText`、
`skipDiagnostic()`；`TodayView` **一个都没读**。没有入口、没有提示、没有跳过按钮、
没有进度文本。`TodayDiagnosticTests` 六条断言全绿，无一可观测。

次生问题：即便渲染了，`DiagnosticBlueprint.cash6MaxDefault` 声明 4 个维度 12 题，而
随包核心集的每个场景 `abilityDimension` 都是 `preflop-range`。商店频道的诊断会是
6 道翻前题、覆盖 4 个声明维度中的 1 个。那条断言维度全覆盖的测试之所以通过，
是因为 `DiagnosticFixture` 合成了一个四维度的包，与任何随包内容都不像。

### A3. 复练调度在 App 里恒不触发（Critical）

```swift
// TodayViewModel.swift:163  传的是 curriculum 节点 ID
dueRepetitions(...).map(\.nodeID)        // {preflop-rfi, preflop-vs-3bet}
// TrainingPlanner.swift:85  比的是能力维度
dueRepetitionDimensions.contains($0.abilityDimension)   // {preflop-range}
```

两个命名空间不相交，`contains()` 恒为 false。`+10` 的到期加权与
`PlanItemReason.repetitionDue` 在 Debug / Dogfood / Release 三个频道下都不可达。

**测试为何抓不到**：两个 fixture 都把这两个字段设成同一个值
（`CurriculumFixture.swift:113`、`DiagnosticContentFixture.swift:104`），
而 `TrainingPlanPriorityTests` 直接传字面量 `["alpha"]`——它验证的是 planner 对自己
契约的遵守，看不见调用方违反了这个契约。`grep repetitionDue PokerCoachTests` 无结果。

---

## B 类：领域逻辑使功能永远无法达成

### B1. 从不犯错的用户永远无法掌握任何节点（Critical）

`completedRepetitionCount` 以「历史中第一次 improvable/blunder」为阶梯起点，
无错误则返回 0；而 `repetitionRequirement = 2`。

失败输入：某节点 20 个不同场景全部 excellent → 样本 20/20 ✓、稳定性 10/9 ✓、
校准 ✓、迁移 3/3 ✓、**复练 0/2 ✗**，永不掌握。

`MasteryFixture` 自己印证了这一点：它的「五项齐备」必须以第 0 天一次 `blunder` 开头
才能让测试通过。

### B2. 单场景节点永不可掌握，却计入进度分母（Critical）

`preflop-vs-3bet` 只有 1 个场景，而迁移要求 3 个此前未作答的 scenario ID。
`firstEncounters.count == 1`，迁移信号封顶 1/3。该节点 `practisableScenarioCount == 1`
故不算「暂无内容」，仍在分母里——学习页进度**硬封顶在 1/2**。

另有一层：一旦用户见过节点内所有场景，首次遭遇集合就永久冻结。最后三次首见里错两次，
之后再怎么练也恢复不了这个信号。

---

## C 类：门禁形同虚设

### C1. `check-release-content.sh` 从不校验策略包与其 checksum 是否一致

agent 实测：把 `scenarios[0].options[0].ev.milliBB` 改成 `999999`，保留原
`.sha256` 不动，门禁 `exit=0` 通过。一个会把所有作答判错的篡改包能过发布门禁，
故障要到 App 启动时 `BundledContentLoader` 抛错才暴露。

### C2. 排除机制与门禁共用同一个「按文件名」的判据

`Release.xcconfig` 按文件名排除未审核内容，门禁也按文件名 `*StrategyPack.json` 发现违规。
agent 实测：把未审核包改名为 `depth-6max-100bb.json`（它在 `Content/exports/` 里本来
就叫这个名字），排除和门禁**一起失效**，`exit=0`。

### C3. 没有任何东西断言「某配置产出了它应有的频道」

`verify-m1c.sh:93-98` 的 store 分支两条臂都只 `echo`、都 exit 0，且 `if` 条件不受
`set -e` 约束。把 `Release.xcconfig` 的 `PC_CONTENT_CHANNEL` 改成 `dogfood` 或整行删掉，
脚本照样绿并打印一条令人安心的消息。后面两个探针都在**副本**上
`plutil -replace ... -string store`，覆盖掉真实构建产出的值——它们测的是脚本，不是构建。

### C4. 冻结契约检查只看未提交的改动

```bash
git diff --quiet HEAD -- Contracts/
```
这是工作树对 HEAD。一旦提交，永远为真。正确的比较是 `cc19423^..HEAD`。

### C5. `check-proposal-completeness.sh` 有三条静默通过路径

agent 实测：
- 把每个 Requirement/Scenario 的**正文**全替换成「(内容删除)」、只留标题 → 通过。
  脚本只比标题名，而归档替换的是整块。它自己的注释指出「降级会丢掉 binding 的部分」，
  然后从不检查 binding 的部分。
- 把 `` - `name` `` 改成 `- **name**` → 「nothing to check」，exit 0。
- 把 `### Modified Capabilities` 移到文件末尾 → 前瞻断言不匹配 → 「nothing to check」，
  同时真删一个 Requirement 也不报。

三条都被 `verify-m1c.sh:150` 的 `>/dev/null` 掩盖。另：注释里写的 `ALLOW_REMOVED`
逃生舱**不存在**。

---

## D 类：审计规则自身的漏洞

`ContentAuditTests` 八条规则，agent 逐条构造了可绕过的输入。最要紧的三条：

### D1. 规则 8（最小防守频率）删一个可选字段即可关闭

`facingRaiseTo` 是 `BBAmount?`，有默认值，无校验器要求，且**不会被写进随包策略包**
（导出里 1 处，`CoreStrategyPack.json` 里 0 处）。从导出里删掉这个 key：
规则 8 检查零个节点并报「通过」，而重新导入的包**逐字节不变**，`verify-m1c.sh` 的
`cmp` 照样绿。这个字段唯一的作用就是喂它自己那道门禁，删掉它没有任何其它可观测后果。

第二种绕过：`attacked = pot - risked`，没有任何东西交叉校验 `pot`。把 `pot` 设成等于
`facingRaiseTo` → 要求防守 0%。

### D2. 规则 7（位置单调性）漏掉 SB

`seatOrder = ["UTG", "HJ", "CO", "BTN"]`，而导出里有 **5 个** RFI 节点。
把 SB 开池设成 5%（比 UTG 还窄，正是这条规则要防的倒置）——规则不报。

### D3. 规则 2（声明频率 vs 组合加权）容差过松，且可被静默跳过

实测漂移只有 1–6 bp，容差却是 100 bp，留了约 94 bp 无人看管的余量。
agent 实测：给 `rfi-utg` 加一行 `72o 100% raise`，范围从 15.59% 变 16.50%，
漂移 90 ≤ 100 → **通过**。「UTG 百分之百开 72o」能过全部八条规则。

另：`guard let stated = ... else { continue }` —— 结论里没有 `%` 的节点根本不检查。
`vs3bet-co-vs-btn` 今天就是这种情况。

### D4. 审计只覆盖核心导出

`coreExport()` 只读 `core-6max-100bb.json`。`depth-6max-100bb.json`（5 个场景，
随 Debug 与 Dogfood 发布）**不受八条规则中的任何一条约束**。

另：`rangeCells` 会渲染给用户，但 `StrategyPackValidator` 从不检查它——没有任何地方
校验一个范围格子的权重是否总和 10000、行动键是否合法、`handClass` 是否可解析。

---

## E 类：其它需要修的

| # | 位置 | 问题 |
|---|---|---|
| E1 | `ContentAudit.swift:117` | `reach / 10_000 * continuing` 先除后乘。4 组合 × 3000bp 的手牌少算 17%。当前内容恰好不受影响，但 MDF 这道门禁读的是一个系统性低估的数 |
| E2 | `LearnView.swift:85` | `guard viewModel == nil else { return }`，且不观察 `eventStoreRevision`。练 20 手回到学习页，掌握状态仍是首次出现时的 |
| E3 | `AppDependencies.swift:138` | 选中的包若为 `retired`，`availability` 为 `reviewedContentUnavailable`，随即撞上 `precondition(canStartTraining)` —— **启动即崩**，而那个「未安装已审核内容」界面本来就是为这种情况准备的 |
| E4 | `BundledContentLoader.swift:79` | 没有 `.sha256` 旁文件即静默跳过校验。`DevStrategyPack.json` 今天就没有 |
| E5 | `ContentUpdateCoordinator.swift:66` | 版本新旧只看**来源声明**的 `offer.contentVersion`，从不与校验后的 `manifest.contentVersion` 对照。另：`.retired` 可被采纳，会把可用内容替换成不可训练状态 |
| E6 | `TrainingPlanner.swift:69` | `targetMinutes.lowerBound`（5）全仓无人读取，只有上限被执行 |
| E7 | `TodayViewModel.swift:157` | 诊断进度用全部事件的 scenarioID，不分 pack/版本；跳过诊断后正常训练会静默「完成」诊断 |
| E8 | `verify-m1c.sh:36` | `-only-testing:PokerCoachTests` 排除了全部 UI 测试。M1C 没有任何东西驱动真实 UI——这正是 A2 得以存活的原因 |
| E9 | `verify-m1c.sh` | 只对核心导出做重新导入比对，depth 导出可以自由漂移 |

---

## 已确认为好的部分

- **非确定性：干净。** 专门查过 `ContentAudit.continuationBasisPoints`（字典迭代但求和，与顺序无关）与 `DiagnosticBlueprint.draw`（Set/Dictionary 仅用于 contains/下标，候选表按 ID 预排序，比较键为全序）。`PackBuilder` 用 `.sortedKeys`，`firstCycle` 与 `dueRepetitions` 都以全序排序。
- **Swift 6 严格并发：干净。** 无 `@unchecked Sendable`、`nonisolated(unsafe)`、可变静态。
- **整数溢出：干净。** 最坏约 1.3e11，64 位安全。E1 是截断不是溢出。
- **`swift test` 确实跑了全部测试。** 静态与执行双向核对：磁盘上 146 个 `@Test` + 3 个 XCTest 方法，执行 146 + 3。无 `.disabled`、`XCTSkip`、空 `arguments:`。
- **`LearnView` 真的接进了导航**（`AdaptiveRootView.swift:152`）。
- **`DeterminismTests` 找不到可执行文件时抛错而非跳过**，是这类测试应有的写法。

---

## 处置顺序

1. **A1 / A2 / A3** —— 三个能力在产品里不可达。要么接上，要么从本次交付范围移除并如实记录。
2. **B1 / B2** —— 掌握判定的两处设计缺陷，会让功能永远无法达成。
3. **C1–C5** —— 门禁修好之前，「全绿」这件事不具备意义。
4. **D1–D4** —— 审计规则的漏洞。规则 8 尤其要紧：它是上一轮人工审核的头号发现，现在删一个字段就能关掉。
5. **E 类** —— 逐条修。

重跑规格合规与项目规范两个 agent，范围收窄到单个包／单份文档。
