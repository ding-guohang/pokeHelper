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


### SB 修正：我先用错了一个自己没搞清楚含义的数字

我最初报告「SB 40% 比公开基准 62.3% 少了 22 个百分点」。这个对比是错的。
62.3% 是 SB 的**总参与率**（跛入 + 加注），而本内容没有跛入分支。三个数字对应
三棵不同的博弈树：

| 数值 | 含义 |
|---|---|
| ~62% | 含跛入解的总参与率 |
| ~24% | 同一个解里的纯加注部分 |
| 35–45% | 把跛入从树里移除后重解的加注范围 |

40% 落在第三个区间内，本来就没错。**拿一个语义没核实的数字去「修」内容，
与直接爬别人的数据填进去是同一类错误。**

查证过程中确实找到三处实错，已修：

1. **SB 尺度**：raise-only 的 SB 标准是 3BB（OOP 需要更大尺度压低 BB 跟注频率），
   原内容全表统一用了 2.5BB。
2. **SB 的 amountToCall**：SB 已投 0.5BB，补齐只需再投 0.5BB（50 centiBB），
   原内容按非盲注位写了 100。
3. **SB 范围组合与频率对不上**：写着 40%，但清单里 offsuit 下段（A2o–A6o、
   K8o–K9o、Q9o、J9o、T9o、98o、87o）全缺。

其余四个位置的频率校准到公开基准（17.6 / 21.4 / 27.8 / 43.5）。

**校准不是审核。** 内容仍然是 `unverifiedDraft`，商店门禁仍然是红的。


### 人工审核发现的六类缺陷，五类是机器本该查出来的

Codex 对核心集内容做了人工审核，判定不通过。我逐条独立复算，**全部成立**，
组合数连小数点后两位都对得上（LJ 7.36%、HJ 9.41%、CO 13.54%、BTN 26.09%）。

问题不在内容错了，在于**这份内容根本不该以那个形态走到「请人审核」这一步**：

| 缺陷 | 机器可查？ |
|---|---|
| `options` 频率写成了整段范围频率，而非英雄手牌那一格 | 是 |
| 范围表组合加权只有声明频率的一半 | 是 |
| 标题写的位置与 `heroSeatOffsetFromButton` 解析结果不符（4/6 节点错） | 是 |
| 场景尺度不在声明的下注树里 | 是 |
| 后续节点引用了前序开池范围到不了的手牌 | 是 |
| EV 精度声称到 0.001BB 但无求解器可追溯 | 否 |

前五类**全部通过了** `StrategyPackValidator` 与发布门禁——校验器只管
「频率总和 10000、行动合法」这类窄义自洽，不管内容是不是它自己声称的那个东西。
等于我让人去做本该由机器做的算术。

**处置**：新增 `ContentAuditTests`（7 条规则），把这五类连同另外两类写成机械检查：

6. 混合策略手牌的各行动 EV 差不得超过 acceptable 的上限（100 bp）——否则评分器
   会把混合里的一支判成错误，而范围表说两支都对。
7. 越靠后的位置开池必须越宽——位置是翻前范围的第一驱动因素，顺序反了就是在教反的。

审计首轮跑出 27 条问题，与人工审核逐条对应。

### 审计自己也有三个 bug，而且差点让我改错内容

重建内容后审计仍报 9 条，其中 **6 条是审计错了**：

- 位置标签按**列表顺序**取，于是「CO 开池面对 BTN 3bet」被判成 BTN。改为按在
  字符串中出现的先后取。
- 组合漂移检查仍拿 `options`（现在是单手牌频率）去比范围的组合权重——两个不同的量。
  范围级声明现在只存在于解释文本里，改为比那个。
- 下注树检查把 `call(to:)` 当成声明尺度。`legalActions()` 里是
  `.call(to: amountToCall)`，那是**应跟金额**，由底池状态决定，不属于下注树；
  全下同理（那是筹码量）。

**为了让一个有缺陷的检查变绿而去改内容，比没有检查更糟。** 每次红都要先判断是
内容错了还是检查错了。

### 结构性改变：声明频率不再是独立填写的数字

内容改由 `Content/build-core-export.py` 从范围表生成：

- 整段开池频率 = 范围表的组合加权，**算出来的**，不是另填的；
- `options` 频率 = 英雄手牌在范围表里那一格，**读出来的**；
- 下注树尺寸在脚本顶部定义一次，场景引用同一批常量。

三者由构造保证一致，不可能再分叉。**不允许手改生成的策略包**——`verify-m1c.sh`
会重新导入并逐字节比对。

内容仍为 `unverifiedDraft`。机械自洽不是策略正确，EV 数值仍无求解器可追溯。
