---
name: curriculum-m1c-adaptive-cash-20260810-01
created: 2026-08-10
status: review_passed
---

# 需求提案：M1C 自适应现金局课程

## Why

M1A 交付了可离线运行的训练切片，M1B 交付了账号与跨设备同步——但**发布构建里没有一道真实的训练题**。仓库中唯一的策略包是 `PokerCoach/Resources/DevStrategyPack.json`，`Config/Release.xcconfig:3` 明确把它排除在 Release 之外，`scripts/check-m1b-release-secrets.sh:46` 还会断言这一点。因此 Release 下 `AppDependencies.live()` 只能走 `#else` 分支（`AppDependencies.swift:131`），界面显示「未安装已审核策略内容」，训练入口被 `canStartTraining` 挡死。

`StrategyContentAvailability.reviewedContentAvailable` 声明于 `StrategyContentMetadata.swift:18`，在生产 switch 中被匹配，但**全仓库唯一构造它的地方是两个测试文件**。Debug 构建靠 `developmentFixtureAvailable` 能跑，所以 APP 并非完全不可用——不可用的是任何能交到用户手上的构建。

M1C 是让产品第一次真正可用的里程碑：把内容送进 App，并让训练内容随玩家的真实弱点变化，而不是让用户自己决定今天练什么。

## What Changes

### New Capabilities

- `strategy-content-pipeline` — 求解器输出导入、黄金数据回归、内容随包交付与更新校验；打通 `reviewedContentAvailable` 这条从未被走过的路径。
- `initial-diagnostic` — 跨位置、街道、筹码深度和错误类型的初始诊断，建立第一版能力画像。
- `adaptive-curriculum` — 现金局能力树、节点掌握判定与学习路径推荐。
- `spaced-repetition` — 同类但非同题的复现调度，避免记答案。

### Modified Capabilities

- `versioned-strategy-content` — 增加 `unverifiedDraft` 审核状态及其披露约束；`reviewed` 增加必填的审核人字段；新增「内容版本不可原地修改」要求。
- `local-learning-profile` — 新增「能力树节点掌握信号」；「今日训练优先级」的排序输入增加复练到期与学习路径，并补充优先级冲突的裁决顺序、时长约束与入选原因。
- `m1a-release-safety` — 构建类别从 Debug / Release 两种扩展为三种（Debug、dogfooding、商店发布），并把内容审核状态门禁与已有的 `DevStrategyPack.json` 排除门禁放在一起。

### Removed Capabilities

无。

## 内容审核的落地方式

本次内容由我生成，分两档交付：

- **核心集**（6-max 100BB 翻前 RFI 与 3bet 范围，属公开成熟策略）由仓库所有者逐表审核签字，manifest 记录 `reviewedBy` 与 `reviewedAt`，状态为 `reviewed`。审核单位是范围表而非逐题。
- **其余深度内容**状态为 `unverifiedDraft`，界面强制披露「未经策略审核」。

这样 M1C 能真正交付 roadmap 为其定义的「已审核内容」，商店发布门禁可以变绿，`docs/product/scope-and-milestones.md:26` 不需要修改。我不会把未经人工审核的生成内容标成 `reviewed`——`docs/standards/strategy-content.md:8` 要求 `reviewed` 具备审核元数据，伪造它等于把一个虚假保证烧进数据里。

## 已确定的设计约束

以下三点在提案阶段确定，不留给 `/harness-plan`：

1. **能力树节点是内容的属性，不是事件的字段。** `TrainingEvent` 已携带 `scenarioID`、`strategyPackID` 与 `strategyContentVersion`（`TrainingEvent.swift:8-10`），`DecisionScenario` 携带 `abilityDimension`（`StrategyModels.swift:45`）。节点归属通过 `scenarioID` 关联内容包求得，事件契约保持不变。这避免了改动 `Contracts/training-event-upload-v1.json`——那是一个由 `Server/migrations/contracts_test.go` 与 `PokerCoachTests/Support/ContractEventFixture.swift` 双向断言的字节冻结文件。
2. **内容下载属于 App Infrastructure，不属于领域包。** 校验与解码留在 `Packages/StrategyContent/`，HTTP 获取放在 `PokerCoach/Infrastructure/`。把 HTTP 客户端放进领域包会违反 `docs/architecture/m1a-module-boundaries.md:21` 与 `docs/architecture/layering.md:24`。
3. **`m1a-module-boundaries.md` 的契约冻结条款是写给 M1B 的**（该文件 `:5` 的措辞限定为「M1B 只能在不改变这些契约语义的前提下依赖它们」），不是永久冻结。约束 1 使 M1C 事实上无需触碰它。

## Capabilities Detail

### Capability: strategy-content-pipeline

#### Requirement: 求解器输出导入

The system SHALL import solver output into versioned strategy packs such that every decision node in the input has a semantically equal counterpart in the output, and SHALL reject any input that does not satisfy the existing decision-node semantics.

##### Scenario: 合法求解器导出导入

- GIVEN 一份含 N 个决策节点的求解器导出，每个节点带位置、街道、有效筹码、行动频率与 EV
- WHEN 导入工具生成策略包
- THEN 生成包的场景数等于 N
- AND 对导出中的每一条 (position, street, action, frequencyBasisPoints, ev)，生成包中存在字段逐一相等的 StrategyOption
- AND 生成的包通过 StrategyPackValidator 的全部语义校验
- AND manifest 记录 pack ID、schema version、content version、generatedSource 与导出时间
- AND 每个场景使用 tableSize 与 heroSeatOffsetFromButton 表示位置

##### Scenario: 求解器导出不满足语义约束

- GIVEN 一份导出中某决策节点的行动频率总和不是 10,000 basis points
- WHEN 导入工具处理该导出
- THEN 导入以非零码失败并指明场景 ID 与实际频率总和
- AND 输出路径下不存在任何文件

##### Scenario: 导入是确定性的

- GIVEN 同一份求解器导出
- WHEN 导入工具在两个独立进程中各运行一次，两次的工作目录、系统时钟与哈希种子均不同
- THEN 两次产出的策略包字节完全相同
- AND 其 SHA-256 等于仓库中签入的黄金 checksum

#### Requirement: 内容升级黄金回归

The system SHALL run a golden-data regression on every content upgrade and SHALL report each scenario whose grading outcome moves beyond tolerance, as required by `docs/standards/strategy-content.md:35`.

##### Scenario: 升级改变了评分结果

- GIVEN 黄金数据集中某场景在旧内容下的 lossRateBasisPoints 为 40，新内容下为 260
- WHEN 运行升级回归
- THEN 回归以非零码失败
- AND 报告列出该场景 ID、旧值 40、新值 260 与其跨越的 quality 边界（acceptable → improvable）

##### Scenario: 升级在容差内

- GIVEN 黄金数据集中所有场景的 lossRateBasisPoints 变化都不超过容差且不跨越 quality 边界
- WHEN 运行升级回归
- THEN 回归以零码通过
- AND 报告仍逐条列出实际变化量，而不是只输出一个通过结论

#### Requirement: 内容随包交付与可选更新

The system SHALL ship a bundled strategy pack that works with no network, and SHALL replace it only with a pack whose checksum verifies and whose content version is strictly higher.

##### Scenario: 首次离线启动使用内置内容

- GIVEN 设备从未联网且从未拉取过内容
- WHEN 用户打开 APP
- THEN `StrategyContentAvailability` 为 `.reviewedContentAvailable`
- AND 当前 pack ID 等于随包内置的核心集 pack ID
- AND 从启动到可作答期间网络层记录 0 次请求

##### Scenario: 校验通过且版本更高的更新包被采用

- GIVEN 本机当前内容版本为 `2026.08.06`，服务端提供 `2026.09.01` 的包且其 SHA-256 与声明一致
- WHEN 客户端评估并应用更新
- THEN 此后新生成的训练题的 content version 为 `2026.09.01`
- AND 既有训练事件记录的 content version 仍为 `2026.08.06`

##### Scenario: 更新包 checksum 不匹配

- GIVEN 服务端提供 `2026.09.01` 的包但其 SHA-256 与声明不符
- WHEN 客户端校验下载内容
- THEN 拒绝该更新并返回 checksum-specific typed error
- AND 当前内容版本仍为 `2026.08.06`，训练不中断

##### Scenario: 更新包内容版本等于当前

- GIVEN 本机当前内容版本为 `2026.08.06`，服务端提供的包也是 `2026.08.06`
- WHEN 客户端评估是否替换
- THEN 不替换

##### Scenario: 更新包内容版本低于当前

- GIVEN 本机当前内容版本为 `2026.09.01`，服务端提供的包是 `2026.08.06`
- WHEN 客户端评估是否替换
- THEN 不替换

### Capability: initial-diagnostic

#### Requirement: 跨维度初始诊断

The system SHALL offer a 12-question initial diagnostic whose blueprint declares the ability dimensions, positions, streets, and stack depths it samples, and SHALL produce a first ability profile covering every dimension the blueprint declares.

##### Scenario: 完成诊断

- GIVEN 用户尚无训练历史，诊断蓝图声明的能力维度全集为 D
- WHEN 用户完成全部 12 道题
- THEN 画像中有快照的能力维度集合等于 D
- AND 这 12 道题覆盖至少 3 个不同的 heroSeatOffsetFromButton、至少 3 条不同街道、至少 2 个有效筹码档位
- AND 事件存储中恰好新增 12 条 TrainingEvent
- AND 由该画像生成的今日计划，其首项维度随画像中最弱维度改变而改变

##### Scenario: 跳过诊断

- GIVEN 用户在首次启动时选择跳过诊断
- WHEN 用户直接进入今日页
- THEN 今日计划非空，且各计划项分属互不相同的能力维度（均衡先验）
- AND 用户在某维度连续三次得到 blunder 后重新生成计划时，该维度排在第一位
- AND 今日页保留诊断入口

##### Scenario: 中断后恢复

- GIVEN 诊断共 12 题，用户完成前 5 题后退出 APP
- WHEN 用户再次打开 APP 并回到诊断
- THEN 进度显示 5/12
- AND 剩余题目的 scenario ID 集合与已完成的 5 个不相交，且数量为 7
- AND 再作答 7 题后诊断结束，而不是重新计数到 12

### Capability: adaptive-curriculum

#### Requirement: 现金局能力树

The system SHALL organize cash-game competence as a tree whose node membership is a property of the strategy content, resolved from a training event's `scenarioID` rather than stored on the event.

##### Scenario: 浏览能力树

- GIVEN 一个内容包，其中映射到节点 `turn-barrel` 的场景有 7 个，且 `river-bluff-catch` 声明前置节点为 `turn-barrel`
- WHEN 用户打开学习页
- THEN `turn-barrel` 显示可练习场景数 7
- AND `river-bluff-catch` 显示其前置节点为 `turn-barrel`
- AND 每个节点显示其当前掌握状态

##### Scenario: 内容缺失的节点

- GIVEN 能力树中节点 `river-bluff-catch` 在当前内容包里没有对应场景
- WHEN 用户浏览该节点
- THEN 该节点标记为暂无内容
- AND 该节点不出现在今日计划中
- AND 掌握进度分母不包含该节点

##### Scenario: 事件所属内容版本不在本机

- GIVEN 一条训练事件记录的 content version 为 `2026.08.06`，而本机只有 `2026.09.01`
- WHEN 归约器为该事件求节点归属
- THEN 回退使用事件自带的 abilityDimension
- AND 该事件仍计入对应维度的样本，不被丢弃
- AND 该事件不计入任何节点的掌握判定

#### Requirement: 节点掌握判定

The system SHALL mark a node mastered only when all five signals hold: at least 20 answers; at least 9 of the last 10 answers graded `excellent` or `acceptable`; every `verySure` answer among the last 10 graded `excellent` or `acceptable`; at least 2 completed due repetitions both graded `excellent` or `acceptable`; and 3 previously unanswered scenario IDs in that node all graded `excellent` or `acceptable`.

##### Scenario: 五项信号齐备时判定掌握

- GIVEN 节点 `turn-barrel` 已有 20 次作答，最近 10 次全部为 excellent 或 acceptable
- AND 最近 10 次中所有 verySure 作答均为 excellent 或 acceptable
- AND 该节点已完成 2 次到期复练且两次均为 acceptable 以上
- WHEN 用户在该节点下 3 个此前未作答过的 scenario ID 上均得到 acceptable 以上
- THEN 该节点掌握状态为 mastered
- AND 节点详情显示五项信号全部满足，并给出各自实际值 20/20、10/10、2/2、3/3

##### Scenario: 样本不足不判定掌握

- GIVEN 节点 `turn-barrel` 只有 4 次作答，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「样本 4/20」

##### Scenario: 近期稳定性不足不判定掌握

- GIVEN 节点 `turn-barrel` 有 20 次作答，最近 10 次中只有 7 次为 excellent 或 acceptable，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「近期稳定性 7/10，需 9/10」

##### Scenario: 高信心错误阻止掌握

- GIVEN 节点 `turn-barrel` 最近 10 次作答中存在一次 verySure 且 quality 为 improvable 或 blunder，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 该节点的计划优先级严格大于一个 sampleCount、meanScore、lastPracticedAt、nextDueAt 均相同但 highConfidenceErrorCount 为 0 的对照节点

##### Scenario: 复练未完成不判定掌握

- GIVEN 节点 `turn-barrel` 只完成过 1 次到期复练，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「复练 1/2」

##### Scenario: 迁移未通过不判定掌握

- GIVEN 节点 `turn-barrel` 的其余四项信号均满足
- WHEN 用户在该节点下第 3 个此前未作答过的 scenario ID 上得到 blunder
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示迁移信号未满足

#### Requirement: 学习路径推荐

The system SHALL recommend the next node from the profile without requiring the user to choose first, while still allowing a direct choice.

##### Scenario: 今日计划来自画像而非用户选择

- GIVEN 画像 A 中 bet-sizing 最弱，画像 B 中 preflop-range 最弱，两者 catalog 相同
- WHEN 分别为 A 和 B 生成今日计划
- THEN A 的计划首项维度为 bet-sizing，B 的计划首项维度为 preflop-range
- AND 生成过程不需要任何用户选择交互

##### Scenario: 用户直接选择具体节点

- GIVEN 用户想练习一个不在今日计划里的节点
- WHEN 用户从能力树进入该节点
- THEN 训练照常进行
- AND 产生的事件同样进入画像归约

### Capability: spaced-repetition

#### Requirement: 同类非同题复现

The system SHALL re-surface a failed node using a scenario the user has not answered in that node, and SHALL NOT re-surface a node whose last answer was correct.

##### Scenario: 隔日复练

- GIVEN 用户昨天在 bet-sizing 的场景 `s-101` 上得到 blunder，同日在 preflop-range 上全部为 acceptable
- WHEN 今日计划生成
- THEN 计划中存在 bet-sizing 的复练项
- AND 该复练项的 scenario ID 不是 `s-101`
- AND 计划中不存在 preflop-range 的复练项

##### Scenario: 内容不足以避免重复

- GIVEN bet-sizing 在内容包中只有 `s-101` 一个场景，且用户已在其上答错
- WHEN 复练需要出题
- THEN 不产出以 `s-101` 为题的复练项
- AND 该维度的复练状态为「受内容限制而挂起」

#### Requirement: 复现间隔阶梯

The system SHALL schedule repetitions on the ladder 1, 3, 7, 14, 30 days, advancing one rung after a correct repetition and falling back one rung after an incorrect one, never below one day, and SHALL expose each node's current `intervalDays` and `nextDueAt`.

##### Scenario: 首次复练间隔为一天

- GIVEN 某节点首次出现答错，此前无复练记录
- WHEN 调度器安排复现
- THEN 该节点的 intervalDays 为 1
- AND nextDueAt 为答错时间的次日

##### Scenario: 答对沿阶梯前进

- GIVEN 某节点当前 intervalDays 为 3，其到期复练得到 acceptable
- WHEN 调度器安排下一次复现
- THEN intervalDays 变为 7

##### Scenario: 答错退一级且不低于一天

- GIVEN 某节点当前 intervalDays 为 7，其到期复练得到 blunder
- WHEN 调度器安排下一次复现
- THEN intervalDays 变为 3
- AND 当节点已处于最低一级时再次答错，intervalDays 仍为 1，不会变为 0

### Capability: versioned-strategy-content

<!-- 归档时本节整块替换 openspec/specs/versioned-strategy-content/spec.md，
     因此未变更的 Requirement 与 Scenario 也必须原文保留。
     由 scripts/check-proposal-completeness.sh 机械校验。 -->

#### Requirement: 策略包来源可追溯

The system SHALL load strategy packs that identify schema version, content version, review status, generated source, game assumptions, and decision scenarios.

##### Scenario: 合法策略包加载

- GIVEN 策略包 schema version 为 1、来源非空且场景完整
- WHEN loader 完成 checksum、解码和语义校验
- THEN 返回不可变 StrategyPack
- AND manifest 与场景中的求解假设可供反馈界面读取
- AND 场景使用 tableSize 与 heroSeatOffsetFromButton 表示可验证的 2–9 人桌位置

##### Scenario: checksum 不匹配

- GIVEN 下载内容的 SHA-256 与期望值不同
- WHEN loader 加载策略包
- THEN 在解码前拒绝内容
- AND 返回 checksum-specific typed error

#### Requirement: 决策节点语义校验

The system SHALL reject a strategy decision node that violates card uniqueness, legal-action, action uniqueness, or frequency-total rules.

##### Scenario: 频率总和错误

- GIVEN 一个场景的行动频率总和不是 10,000 basis points
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 错误包含场景 ID 和实际频率总和

##### Scenario: 非法行动进入策略

- GIVEN 策略选项包含 BettingDecisionContext 未提供的行动
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 该内容不能进入训练流程

#### Requirement: 审核状态约束

The system SHALL distinguish `testFixture`, `unverifiedDraft`, `reviewed`, and `retired` strategy content; SHALL require both a reviewer identity and a review time on `reviewed` content; and SHALL NOT present content of any other status as verified poker advice.

##### Scenario: 已审核内容缺少审核时间

- GIVEN review status 为 `reviewed` 且 reviewed-at 为空
- WHEN validator 校验
- THEN 策略包被拒绝

##### Scenario: 已审核内容缺少审核人

- GIVEN review status 为 `reviewed`、reviewed-at 非空、但 reviewed-by 为空
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 错误指明缺失的是审核人而非其他 manifest 字段

##### Scenario: 已审核内容元数据齐备

- GIVEN review status 为 `reviewed`，reviewed-by 与 reviewed-at 均非空，且场景通过语义校验
- WHEN validator 校验
- THEN 策略包被接受
- AND 反馈界面可以读到审核人与审核时间

##### Scenario: 开发内容展示

- GIVEN APP 使用 `testFixture` 内容
- WHEN 用户查看训练或反馈
- THEN 界面明确显示“开发演示数据”
- AND 不把数据描述为已审核扑克建议

##### Scenario: 未审核内容必须披露

- GIVEN APP 使用 `unverifiedDraft` 内容
- WHEN 用户查看训练、反馈或能力画像
- THEN 界面明确显示“未经策略审核”
- AND 不把数据描述为已审核扑克建议
- AND 该提示与 `testFixture` 的“开发演示数据”是两条不同的文案

#### Requirement: 内容版本不可原地修改

The system SHALL treat a published content version as immutable and SHALL record the pack ID and content version on every training event.

##### Scenario: 内容升级后历史仍可追溯

- GIVEN 本机已有使用 content version `2026.08.06` 作答的训练事件
- WHEN 安装 content version `2026.09.01` 的内容包
- THEN 既有事件记录的 pack ID 与 content version 仍为 `2026.08.06` 的取值
- AND 复盘界面对该条历史显示 `2026.08.06`

### Capability: local-learning-profile

<!-- 同上：归档时整块替换 openspec/specs/local-learning-profile/spec.md。 -->

#### Requirement: 不可变本地训练事件

The system SHALL persist each completed decision as an immutable, append-only event that includes event ID, local user ID, device ID, occurrence time, scenario ID, strategy pack ID, content version, ability dimension, submission, and grade.

##### Scenario: 首次追加

- GIVEN 本地事件存储为空
- WHEN APP 追加一个 TrainingEvent
- THEN 事件可按时间顺序读取
- AND 所有同步所需标识与评分字段均保留

##### Scenario: 重复事件

- GIVEN 存储中已经存在相同 event ID
- WHEN APP 再次追加该事件
- THEN 存储内容不重复
- AND 读取结果仍只有一条该事件

##### Scenario: 损坏事件文件

- GIVEN JSON Lines 文件的某一行无法解码
- WHEN store 初始化或读取
- THEN 返回包含行号的 typed corruption error
- AND 日志不输出完整事件正文

#### Requirement: 能力画像归约

The system SHALL derive each ability dimension from its immutable training events.

##### Scenario: 高信心错误

- GIVEN very-sure 决策被评为 improvable 或 blunder
- WHEN reducer 生成能力画像
- THEN 对应维度 high-confidence-error-count 增加
- AND 其他能力维度不受影响

#### Requirement: 今日训练优先级

The system SHALL rank training catalog items using weakness, high-confidence errors, days since practice, repetition due date, and the active learning path, resolving conflicts in that stated order.

##### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

##### Scenario: 到期复练排在未到期项目之前

- GIVEN A 与 B 的 meanScore、highConfidenceErrorCount、lastPracticedAt 完全相同
- AND A 的 nextDueAt 为昨天、B 的 nextDueAt 为三天后，且 A 的 catalog ID 字典序排在 B 之后
- WHEN planner 生成今日项目
- THEN A 排在 B 之前
- AND A 的 priority 严格大于 B 的 priority

##### Scenario: 高信心错误压过复练到期

- GIVEN A 有高信心错误但复练未到期，B 无高信心错误但复练已到期，其余输入相同
- WHEN planner 生成今日项目
- THEN A 排在 B 之前

##### Scenario: 每个计划项给出被选中的原因

- GIVEN 四个画像，分别只具备低分、只具备高信心错误、只具备到期复练、只具备学习路径推进
- WHEN 分别生成今日计划
- THEN 四个计划的首项入选原因依次为 `.weakness`、`.highConfidenceError`、`.repetitionDue`、`.pathProgress`
- AND 该原因在相同输入下保持稳定

##### Scenario: 计划受可用时长约束

- GIVEN 今日计划目标时长为 5 到 10 分钟，候选项充足且每项预计时长已知
- WHEN planner 生成计划
- THEN 计划项预计时长之和不超过 10 分钟且不少于 5 分钟
- AND 再加入任意一个未入选候选项都会超过 10 分钟

#### Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the active profile's local event store after a completed or synchronized decision.

##### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 重新生成的今日计划首项维度为 bet-sizing

#### Requirement: 跨设备历史确定性归约

The system SHALL derive the active user's ability profile from the deduplicated union of locally created and synchronized TrainingEvents.

##### Scenario: 远端事件进入画像

- GIVEN 同一账号的另一设备完成训练并同步
- WHEN 当前设备拉取并合并该事件
- THEN Today 与 Review 的样本和能力画像包含该事件
- AND 相同 event ID 的重复拉取不改变结果

##### Scenario: 两台设备独立归约得到相同画像

- GIVEN 两台设备各自持有相同的去重事件集合，但本地写入顺序不同
- WHEN 各自独立归约
- THEN 两台设备得到逐字段相等的画像
- AND 该画像等于预期快照：bet-sizing 的 sampleCount 为 5、meanScore 为 62、highConfidenceErrorCount 为 2

#### Requirement: 能力树节点掌握信号

The system SHALL expose, for every curriculum node, each of the five mastery signals with its satisfied state and its current numeric value.

##### Scenario: 查看未掌握原因

- GIVEN 节点 `turn-barrel` 有 4 次作答，最近 10 次中 3 次达标，无 verySure 作答，已完成 0 次复练，迁移未开始
- WHEN 用户查看该节点
- THEN 界面逐行列出五项信号：样本 4/20 未满足、近期稳定性 3/10 未满足、信心校准 满足、复练 0/2 未满足、迁移 0/3 未满足
- AND 不显示笼统的未掌握结论

### Capability: m1a-release-safety

<!-- 同上：归档时整块替换 openspec/specs/m1a-release-safety/spec.md。 -->

#### Requirement: 开发策略数据隔离

The system SHALL recognize three build classes — Debug, dogfooding, and store release — SHALL include the deterministic development strategy pack in Debug only, and SHALL admit content to each class by review status: `testFixture` in Debug, `unverifiedDraft` and `reviewed` in dogfooding, `reviewed` only in a store release.

##### Scenario: Debug 训练

- GIVEN APP 使用 Debug 配置启动
- WHEN 开发策略场景被加载
- THEN 用户可以完成纵向训练流程
- AND 所有相关页面显示“开发演示数据”

##### Scenario: Release 构建

- GIVEN APP 使用 Release 配置构建
- WHEN 检查生成的 APP bundle
- THEN `DevStrategyPack.json` 不存在
- AND 缺少已审核内容时显示“未安装已审核策略内容”

##### Scenario: dogfooding 构建携带未审核内容

- GIVEN 一个 dogfooding 构建，随包内容含 `unverifiedDraft` 与 `reviewed` 两种
- WHEN 运行发布门禁
- THEN 门禁以 0 退出
- AND 训练可以开始
- AND 由 `unverifiedDraft` 内容生成的界面显示“未经策略审核”

##### Scenario: 商店发布拒绝未审核内容

- GIVEN 一个商店发布构建，随包内容含至少一个 `unverifiedDraft` 包
- WHEN 运行发布门禁
- THEN 门禁以非零码失败
- AND 失败信息列出违规包的 pack ID 与其 review status

##### Scenario: 商店发布接受已审核内容

- GIVEN 一个商店发布构建，随包内容全部为 `reviewed` 且各自具备 reviewed-by 与 reviewed-at
- WHEN 运行发布门禁
- THEN 门禁以 0 退出
- AND `StrategyContentAvailability` 为 `.reviewedContentAvailable`

#### Requirement: 一键验证

The system SHALL provide one command that verifies packages, app models, iPhone flow, iPad layout, and Release fixture exclusion.

##### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift 和 XcodeGen
- WHEN 执行 `bash scripts/verify-m1a.sh`
- THEN PokerCore、StrategyContent 和 TrainingDomain 测试通过
- AND APP 单元测试通过
- AND iPhone 与 iPad UI 测试通过

## 设计阶段需决断的点

以下问题影响架构，留给 `/harness-plan`：

1. **三种构建类别如何在 `Config/` 中落地。** 今天只有 `Debug.xcconfig` 与 `Release.xcconfig`，而 `scripts/check-m1b-release-secrets.sh:46-54` 硬编码了两配置假设。是新增第三套 xcconfig，还是用一个编译条件区分 dogfooding 与商店发布，决定了门禁的判定依据。
2. **复练调度状态存放位置。** `nextDueAt` 与 `intervalDays` 必须可读（见 spaced-repetition 的要求），但可以从事件历史确定性推导，也可以单独持久化。前者与「画像由完整事件确定性归约」一致且天然跨设备一致；后者更快，但要纳入同步与档案隔离。
3. **内容更新端点是否在本次启用。** `strategy-content-pipeline` 的客户端校验行为已经定义，服务端下发端点是否落在 M1C 范围内需要明确；若推迟，该能力的交付边界止于随包内置与本地校验。

## Impact

- **Code:**
  - `Packages/StrategyContent/` — `ReviewStatus` 增加 `unverifiedDraft`；manifest 增加 `reviewedBy`；校验与解码扩展
  - `Packages/TrainingDomain/` — 能力树节点掌握判定、复练调度、`TrainingPlanner` 优先级扩展与裁决顺序
  - 新增内容导入工具（求解器输出 → 策略包）与黄金回归
  - `PokerCoach/App/StrategyContentMetadata.swift` — `StrategyContentAvailability` 与全部披露文案
  - `PokerCoach/Features/Learn/` — 能力树界面（今天只有一个硬编码静态列表）
  - `PokerCoach/Features/Today/` — 诊断入口与计划原因展示
  - `PokerCoach/Features/Train/`、`Feedback/`、`Review/` — `unverifiedDraft` 披露与历史内容版本展示
  - `PokerCoach/Infrastructure/` — 内容更新的 HTTP 获取（不放进领域包）
  - `PokerCoach/App/AppDependencies.swift` — 首次走通 `reviewedContentAvailable`
  - `Config/` 与 `scripts/check-m1b-release-secrets.sh` — 第三种构建类别与内容审核状态门禁
  - `PokerCoach/Resources/` 与 `project.yml` — 随包内置内容的资源条目
  - `Server/` — 可选内容分发端点（若启用更新通道）
- **Docs:** `docs/standards/strategy-content.md` 的审核状态表需增加 `unverifiedDraft` 行，并把「Release 可用」一列拆为「dogfooding 可用」与「商店发布可用」；必需元数据增加 `reviewedBy`；展示规则增加 `unverifiedDraft`。`docs/architecture/components.md:40` 把「内容分发」列为 M1B 已实现，与 `Server/internal/` 的实际内容不符，应一并订正。
- **Interfaces:** 新增内容包更新的 HTTPS 端点（若启用）；能力树与诊断为新增 UI 入口；导入工具为本地开发工具，不对外暴露。
- **Dependencies:** 无新增运行时依赖。`Contracts/training-event-upload-v1.json` 不变——见「已确定的设计约束」第 1 条。

## Risks

- **生成内容被误当作已审核策略** → 核心集由所有者逐表审核并记录 `reviewedBy`/`reviewedAt`；其余标 `unverifiedDraft` 并强制界面披露；商店发布门禁拒绝非 `reviewed` 内容。
- **掌握判定退化为恒假实现** → 五项信号各有独立的否定场景，另有一条五项齐备的正向场景断言 mastered；否则整个特性可以用 `false` 通过。
- **能力树节点与内容覆盖不匹配，导致节点永远无法掌握** → 无内容的节点显式标记并排除出计划与进度分母。
- **复练在小内容集下退化为重复同一题** → 明确「同类非同题」，内容不足时挂起该维度复练。
- **复现间隔无下限导致同一题在同一会话反复出现** → 阶梯与下限写入要求，答错退级不低于一天。
- **内容升级悄悄改变历史评分** → 升级必须运行黄金回归并逐条报告变化量。
- **导入工具产出不确定导致 checksum 漂移** → 要求跨进程、异工作目录、异哈希种子两次导入字节相同并等于签入的黄金 checksum。
- **改动事件契约会破坏跨语言字节冻结文件** → 节点归属从内容派生，事件契约不变。

## Non-Goals

- 不做锦标赛能力树、短码、Ante、ICM（属于 M3）。
- 不做连续牌局模拟与虚拟对手（属于 M2A）。
- 不做牌谱导入与场景构建（属于 M2B）。
- 不做订阅、权益与实际上架动作（属于 M4）；本次只交付发布门禁本身。
- 不由我单方面把生成内容标为 `reviewed`；`reviewed` 一律需要人工审核签字。
- 不做生成式教练文案；教练文本仍只组织已有结构化分析。

## Acceptance Criteria

1. 商店发布构建随包内置经审核签字的核心集内容，首次离线启动即可训练，`reviewedContentAvailable` 在生产代码中被真实构造。
2. 求解器导出可经导入工具产出通过全部语义校验的策略包；输出与输入逐条对应；跨进程两次导入字节相同并等于签入的黄金 checksum。
3. 内容升级运行黄金回归；跨越 quality 边界的变化使回归失败并逐条报告。
4. 初始诊断 12 题可完成、可跳过、可中断后继续；跳过后今日计划仍非空且维度均衡。
5. 学习页显示现金局能力树，节点归属由内容派生；无内容的节点显式标记且不计入进度分母。
6. 节点掌握需五项信号同时满足，且存在一条断言 mastered 的正向测试；五项各有独立的否定测试。
7. 复练出题与上次答错的场景不同；上次答对的维度不出现复练项；内容不足时该维度复练挂起。
8. 复现间隔按 1/3/7/14/30 阶梯前进与退级，下限为 1 天，`intervalDays` 与 `nextDueAt` 可读。
9. 任何由 `unverifiedDraft` 内容生成的界面都显示「未经策略审核」，且该文案与「开发演示数据」不同。
10. 发布门禁：商店发布构建在存在 `testFixture` 或 `unverifiedDraft` 内容时失败、在内容全为 `reviewed` 时通过；dogfooding 构建携带 `unverifiedDraft` 时通过。
11. 内容升级后，既有训练事件记录的 pack ID 与 content version 不被改写，复盘仍显示当时的内容版本。
12. `Contracts/training-event-upload-v1.sha256` 未变更。
13. `bash scripts/verify-m1a.sh` 与 `bash scripts/verify-m1b.sh` 仍然通过。
14. `bash scripts/check-proposal-completeness.sh curriculum-m1c-adaptive-cash-20260810-01` 通过。
