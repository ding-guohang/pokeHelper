# 执行台账：curriculum-m1c-adaptive-cash-20260810-01

只记录**从代码和 tasks.md 读不出来**的东西：偏离计划的决策及其理由、跨任务承接的遗留项、
以及踩过一次不想再踩的坑。

## 进度

| Task | 状态 | 提交 | 备注 |
|---|---|---|---|
| 1 审核状态与审核元数据 | 完成 | `d96de5b` | |
| 2 能力树进入内容模型 | 完成 | 见下方偏离 1 | 合并了 Task 3 的部分内容 |
| 3 fixture 补齐新字段 | 完成 | 同上 | 实际涉及 6 处，计划只预估到 2 处 |
| 16 披露文案与可用性状态 | 完成 | `9a7c0b3` + 接线提交 | 提前执行，见偏离 2 |
| 4 建立 StrategyTooling 包 | 完成 | | 未加入 project.yml，不进 App |
| 5 导入的输入输出对应 | 完成 | | 偏离 5：不重述频率规则 |
| 6 跨进程导入确定性 | 完成 | | 反例已实证，见下方「假红」 |
| 7 内容升级黄金回归 | 完成 | | |
| 8–15、17–23 | 未开始 | | |

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

### 5. 导入工具不重述内容规则

计划让 `PackBuilder` 抛 `frequencyTotalMismatch(scenarioID:actual:)`。改为
`invalidPack(StrategyPackValidationError)`——直接透出 `StrategyPackValidator`
的 typed error。频率总和等于 10,000 这类规则只应有一份实现；导入器抄一份，
就多了一处会与 App 实际加载的模型漂移的地方。错误里仍然带场景 ID 与实际总和。

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

## 已验证

`bash scripts/verify-m1a.sh` 通过（含 iPhone 与 iPad UI 测试、Release 构建、
`DevStrategyPack.json` 排除断言）。App 单元测试 193 条全绿。

## 承接给后续 Task 的遗留项

1. 三个手写 pack fixture 改 `throws`（见上）。
2. ~~`AppDependencies` 尚未把 `installedContent` 传给 `ReviewViewModel`~~ —— 已接上。
   这条遗留项是被 `CashCoachHappyPathTests` 抓出来的：单元测试全绿，但 UI 测试走真实
   依赖组装，复盘页显示「内容来源未知」而不是「开发演示数据」。**这正是把兜底写成
   显式文案而不是 nil 的价值**——若返回 nil，界面只是少一行字，UI 测试的
   `waitForExistence` 也会失败，但看日志无法一眼判断是「渲染慢」还是「逻辑错」。
3. `valid-pack.json` 的黄金 checksum 硬编码在 `StrategyPackTests.matchingChecksumAllowsLoading`
   里（现为 `54ce4ff0…`）。改动该 fixture 字节必须同步更新。

### 同一轮里被「假红」骗了两次

验证确定性测试能否抓到字典乱序时，我摘掉 `.sortedKeys` 跑了 10 次，10 次全「过」。
结论看起来是「这条测试没用」，实际上：

1. **第一次假红**：`swift test --filter 跨进程字节一致` 用的是 `@Test` 的显示名，
   而 `--filter` 匹配的是函数名。输出是 `warning: No matching test cases were run`
   加上 `Executed 0 tests ... passed`——我的 `grep -q passed` 把它读成了成功。
2. **第二次假红**：换成函数名后 8/8 失败，看起来对了。但失败原因是
   `strategy-import 不在 ...`——`Bundle.main.bundleURL` 在 `swift test` 下指向
   工具链的测试运行器目录，不是构建产物目录。测试从没真正跑过导入。

两次都得到了「符合预期」的结论，两次都什么都没验证。

**规避方式**：验证一条测试的红/绿时，不要只看退出码或 `passed` 字样，必须断言
**执行数**，并且**读失败信息本身**确认失败原因就是你想要的那个原因。本次最终的
判据是：反例下第二个进程的 sha256 每次都不同（`7077…`/`e6ad…`/`7c36…`），
而设了 `SWIFT_DETERMINISTIC_HASHING=1` 的第一个进程稳定不变——这才是
「字典顺序随哈希种子漂移」的直接证据。

`DeterminismTests.importerBinary()` 因此在找不到可执行文件时**抛错而不是跳过**。
