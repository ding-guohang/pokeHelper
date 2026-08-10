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
| 8 节点归属与版本回退 | 完成 | | |
| 9 复练间隔阶梯 | 完成 | | 偏离 6：拆成两个类型 |
| 10 五项掌握信号 | 完成 | | 骨架实证见下 |
| 11 计划优先级与入选原因 | 完成 | | 偏离 7：不用严格字典序 |
| 12 诊断蓝图与进度 | 完成 | | |
| 13 生成核心集导出 | 完成 | | 6 个节点，等待人工审核 |
| 14 人工审核闸门 | **等待所有者签字** | | 见 Content/review/ |
| 15 生成未审核深度内容 | 完成 | | 5 个节点 |
| 17 随包内容加载 | 完成 | | 见下方说明 |
| 18 内容更新机制 | 完成 | | 服务端端点按 design 推迟 |
| 19 能力树界面 | 完成 | | UI 测试留到 Task 23 |
| 21 三种构建类别 | 完成 | | |
| 22 内容审核状态门禁 | 完成 | | **store 频道当前为红，等签字** |
| 20 今日接入诊断与复练 | 完成 | | |
| 23 一键验证与文档订正 | 完成 | | |

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

### 6. 复练调度拆成两个类型

计划里 `RepetitionSchedule` 同时承载「阶梯折叠结果」和「今日该出哪道题」。拆成
`RepetitionSchedule`（nodeID / intervalDays / nextDueAt，纯折叠结果）与
`RepetitionPlanItem`（附带 scenarioID? 与 isContentLimited）。前者是对事件历史的
确定性归约，后者依赖「当前包里还有哪些没做过的题」，两者的输入不同，混在一起会让
纯折叠函数被迫接受一个它用不到的包参数。

### 7. 裁决顺序用权重量级实现，不是严格字典序

proposal 写「按弱项 → 高信心错误 → 距上次练习 → 复练到期 → 学习路径的顺序裁决冲突」。
严格字典序会让弱项彻底压倒其余：meanScore 61 且零高信心错误的维度，永远排在
meanScore 62 且有 5 次高信心错误的维度之前。这与 `docs/product/learning-rules.md:22`
「高信心且明显亏损的错误优先进入后续训练」相抵触——那条要求高信心错误真的影响排序，
而不只是在平局时起作用。

改为保留既有的加权和，新增复练到期（+10）与学习路径（+5）两项，权重量级满足
声明的先后关系。所有「其余输入相同、只变一项」的场景仍然成立。

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


### 掌握判定：骨架实证证明了「否定场景约束不住实现」，而且比预想更彻底

按计划先只写恒返回 `isMastered == false` 的骨架，跑五条否定测试与一条正向测试。结果：

**五条否定测试里，没有一条是因为 `#expect(mastery.isMastered == false)` 而失败的。**
那句断言在恒假实现下全部通过。它们能失败，只是因为我额外断言了每项信号的
`actual` 与 `required` 数值。

最尖锐的一条是「高信心错误阻止掌握」：连
`#expect(mastery.signal(.confidenceCalibration).satisfied == false)` 都在骨架下通过了
（骨架的所有信号都是 0/1，全不满足）。抓住它的是那条交叉断言
`#expect(mastery.signal(.recentStability).satisfied)`——要求「稳定性仍然满足」，
从而确认失败的确实是校准而不是别的。

结论：**判定类规格的否定场景必须断言判据的数值，而不只是断言结论。**
proposal 里那些「THEN 节点不标记为掌握」若照字面实现，整套测试对恒假实现无效。

### 掌握 fixture 的旋钮一开始控制不了它要控制的东西

`completedRepetitions` 旋钮本意是控制「完成了几次到期复练」，但普通练习一旦落在
到期日之后，它自己就算一次复练。原先 fixture 把练习按整天铺开，于是无论旋钮设几，
实际复练次数都由样本量决定。改成把练习放在最后一次复练之后、下一个到期日之前
（+0.01 天步进），旋钮才真正独立。

写 fixture 时要问一句：这个旋钮改变的，是不是正好就是它名字说的那一件事。


### 计划从「固定取前三项」改成按时长填充，会静默改变既有断言的含义

`plannerPrioritizesHighConfidenceWeakness` 断言 `items.count == 3`。catalog 是三个
5 分钟项，共 15 分钟，超过 10 分钟上限，所以新实现只取 2 项。这不是回归——旧的
`prefix(3)` 从不看时长，那条断言编码的是「取前三」而不是任何产品意图。改断言并
补上总时长断言。

同理 `TodayViewModelTests` 断言「刷新后 reason 变了」。reason 现在是枚举，前后
都合理地停在 `.weakness`；真正变化的是它背后的数字。改成断言 `reasonDetail`。

两处都是先判断「断言和实现哪个是错的」，再动手。


### `hashValue` 不能用来生成 fixture 数据

`DiagnosticFixture` 最初用 `abs(id.hashValue % 6)` 决定发哪几张公共牌。Swift 每进程
随机化哈希种子，所以同一个 id 在不同进程会得到不同的牌面。同进程内的确定性测试
照样通过——这是 Task 6 里让我白验两次的同一个东西。改成字符码求和。

fixture 里任何「看起来随机但需要稳定」的取值，都不能来自 `hashValue`、
`Math.random`、`Date()` 或字典迭代顺序。


### 两个只在实际用起来才暴露的缺陷

1. `--print-range-tables` 原本仍然要求 `--content-version` 与 `--review-status`。
   打印范围表不写任何文件，却要求审核人在审核之前先声明一个审核状态。
2. `padding(toLength:)` 会**截断**超长字符串。范围表把 `AKo-AQo` 打印成 `AKo-AQ`
   ——那是另一个范围。审核人照着这份文本签字，签的就是错的东西。

第一次生成时我把 stderr 重定向到 `/dev/null`，于是 CLI 的用法错误被吞掉，
产出了一个**空文件**而命令看起来成功。这与本轮反复出现的失效模式同源：
不要把可能携带失败原因的输出丢掉。


### `reviewedContentAvailable` 目前仍然构造不出来，这是对的

Task 17 打通了随包加载，但 `CoreStrategyPack` 的状态仍是 `unverifiedDraft`，
所以 `BundledContentLoader` 给出的是 `.unverifiedContentAvailable`。
AC 1（Release 构建走通 `reviewedContentAvailable`）**在 Task 14 人工签字之前
无法满足，也不应该满足**。

`testPrefersTheMostTrustedStatusPresent` 写成条件断言而不是硬断言 reviewed：
它在签字前后都成立，签字后自动开始检查 reviewed 分支。


### 发布门禁当前是红的，而且这正是它该有的状态

`bash scripts/check-release-content.sh <Release 产物>` 现在输出：

```
FAIL: channel 'store' forbids 'unverifiedDraft' but cash-6max-100bb-core carries it
```

因为 `CoreStrategyPack` 还是 `unverifiedDraft`，等 Task 14 人工签字。Debug 与
Dogfood 两个频道通过，商店发布被挡住——AC 1 与 AC 10 在签字前本来就不该同时成立。

三条探针都实测过：store 塞未审核内容 → 拒绝；缺 `PCContentChannel` → 失败而非放行；
全 reviewed → 通过。只有通过路径的门禁与恒真无异，所以失败路径必须被真实触发过一次。


### verify-m1c.sh 对 store 频道断言的是「具体结果」而不是「通过」

核心集签字前 store 频道必然失败，签字后必然通过。脚本不能简单地要求它通过
（签字前会永久红），也不能忽略它（那就等于没检查）。做法是两个分支都打印明确结论：

```
==> Content gate: store channel correctly blocked (core content is not yet reviewed)
```

签字后同一行会变成 `store channel passes (reviewed content is installed)`。
绿色的运行不会静默地意味着「没人看过」。

另外脚本重新导入一次核心集并与随包文件逐字节比对，防止有人直接手改生成的策略包
——那样包与导出就不再对应，Task 6 的确定性测试也随之失效。
