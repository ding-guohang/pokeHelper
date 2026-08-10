# 执行台账：curriculum-m1c-adaptive-cash-20260810-01

只记录**从代码和 tasks.md 读不出来**的东西：偏离计划的决策及其理由、跨任务承接的遗留项、
以及踩过一次不想再踩的坑。

## 进度

| Task | 状态 | 提交 | 备注 |
|---|---|---|---|
| 1 审核状态与审核元数据 | 完成 | `d96de5b` | |
| 2 能力树进入内容模型 | 完成 | 见下方偏离 1 | 合并了 Task 3 的部分内容 |
| 3 fixture 补齐新字段 | 完成 | 同上 | 实际涉及 6 处，计划只预估到 2 处 |
| 16 披露文案与可用性状态 | 完成 | 提前执行，见偏离 2 | |
| 4–15、17–23 | 未开始 | | |

## 偏离计划的决策

### 1. Task 2 与 Task 3 合并执行

计划把「fixture 补齐新字段」单列为 Task 3。实际上 `curriculum` 与 `curriculumNodeID`
设为必填后，Task 2 的测试在 fixture 补齐前根本无法运行——它们不是两个任务，是同一个
任务的两半。按计划顺序做会得到一个永远无法变绿的 Task 2。

### 2. Task 16（披露）被编译器提前逼出来

`ReviewStatus` 新增 case 后，`FeedbackPresentation` 的两处穷尽 switch 立即编译失败，
App 目标构建不过，任何 App 测试都跑不了。所以 Task 16 必须在 Phase B–E 之前完成。
这不是坏事：穷尽 switch 正是为此设计的，它替人工清点了所有展示点。

### 3. `contentDisclosure(for:)` 的判据从 pack ID 改为审核状态，且不再返回 nil

`ReviewViewModel.contentDisclosure(for:)` 原本比对开发包 ID 来决定是否显示「开发演示数据」。
这个判据在只有一种未审核内容时成立，加入 `unverifiedDraft` 后会让**未审核的历史记录
完全不显示任何提示**——恰好是这个状态被引入来避免的后果。

改为按 pack ID 查已安装内容的审核状态。查不到时返回「内容来源未知」而不是 nil：
历史条目的来源无法确认时必须说出来，渲染成空白读起来像「没什么要声明的」，与事实相反。

`ReviewViewModel` 因此新增 `installedContent: [String: ReviewStatus]` 参数。

### 4. `"开发/未审核"` 拆成两条文案

`FeedbackPresentation.reviewStatusText` 原本对 `testFixture` 显示「开发/未审核」，
把「开发演示数据」和「未经策略审核的策略内容」当成同一件事。这正是 `unverifiedDraft`
要拆开的混淆。改为 `testFixture → 开发演示`、`unverifiedDraft → 未经策略审核`，
并有测试断言两条文案不相同——共用一条横幅会让「显示了披露」这个断言通过，
却告诉用户错误的信息。

## 坑

### 手写 pack JSON 的 fixture 用 `preconditionFailure`，一处数据不全就打死整个测试进程

`FeedbackFixture`、`DecisionSessionFixture`、`ContractEventFixture` 三处都在 Swift 里
手写 pack JSON，解码失败时调用 `preconditionFailure`。给模型加必填字段后，它们不是
「三条测试失败」，而是**测试宿主进程崩溃**，xcodebuild 重试 15 次、每次约 25 秒，
并弹出 macOS「PokerCoach 意外退出」对话框——看起来像产品崩溃。

必填字段本身是对的（旧包应当解码失败而不是静默落进默认节点），但 fixture 用
`preconditionFailure` 把这个代价放大成了进程级中止。

**遗留项**：把这三个 fixture 改成 `throws`，让失败只影响用到它的测试。
未在本轮修，因为它跨多个测试文件的调用点，与当前 Task 无关。

### 加必填字段时要一次找全所有构造点

`grep -rln '"manifest"' --include="*.swift"` 加上 `find -name '*.json' | xargs grep -l '"manifest"'`
能一次列全（本次：3 个 Swift fixture + 3 个 JSON 资源）。分散地等编译器和运行时逐个报错，
每轮 App 测试要等 3–8 分钟。

## 承接给后续 Task 的遗留项

1. 三个手写 pack fixture 改 `throws`（见上）。
2. `AppDependencies` 尚未把 `installedContent` 传给 `ReviewViewModel`——目前生产路径
   下复盘界面对所有历史条目显示「内容来源未知」。Task 17 接入随包内容加载时必须一并接上，
   否则会把一个正确的兜底变成常态。
3. `valid-pack.json` 的黄金 checksum 硬编码在 `StrategyPackTests.matchingChecksumAllowsLoading`
   里（现为 `54ce4ff0…`）。改动该 fixture 字节必须同步更新。
