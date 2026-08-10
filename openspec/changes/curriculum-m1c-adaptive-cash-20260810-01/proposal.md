---
name: curriculum-m1c-adaptive-cash-20260810-01
created: 2026-08-10
status: draft
---

# 需求提案：M1C 自适应现金局课程

## Why

M1A 交付了可离线运行的训练切片，M1B 交付了账号与跨设备同步——但**这个 APP 至今没有一道真实的训练题**。Release 构建里没有任何策略内容，`AppDependencies.live()` 走 `reviewedContentUnavailable` 分支，界面显示"未安装已审核策略内容"，训练入口被门禁挡死。`StrategyContentAvailability.reviewedContentAvailable` 这个状态在生产代码里从未被构造过。

M1C 是让产品第一次真正可用的里程碑：把内容送进 App，并让训练内容随玩家的真实弱点变化，而不是让用户自己决定今天练什么。

## What Changes

### New Capabilities

- `strategy-content-pipeline` — 求解器输出导入、内容编排与随包交付；打通 `reviewedContentAvailable` 这条从未被走过的路径。
- `initial-diagnostic` — 跨位置、街道、筹码深度和错误类型的初始诊断，建立第一版能力画像。
- `adaptive-curriculum` — 现金局能力树、节点掌握判定与学习路径推荐。
- `spaced-repetition` — 同类但非同题的复现调度，避免记答案。

### Modified Capabilities

- `versioned-strategy-content` — 增加 `unverifiedDraft` 审核状态及其披露与发布约束；新增“内容版本不可原地修改”要求。随包交付与更新校验归入新能力 `strategy-content-pipeline`。
- `local-learning-profile` — 新增“能力树节点掌握信号”要求；“今日训练优先级”的排序输入增加遗忘风险与学习路径，并补充时长约束与入选原因。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: strategy-content-pipeline

#### Requirement: 求解器输出导入

The system SHALL import solver output into versioned strategy packs, rejecting any input that does not satisfy the existing decision-node semantics.

##### Scenario: 合法求解器导出导入

- GIVEN 一份包含位置、街道、有效筹码、行动频率与 EV 的求解器导出
- WHEN 导入工具生成策略包
- THEN 生成的包通过 StrategyPackValidator 的全部语义校验
- AND manifest 记录 pack ID、schema version、content version、来源工具与导出时间
- AND 每个场景使用 tableSize 与 heroSeatOffsetFromButton 表示位置

##### Scenario: 求解器导出不满足语义约束

- GIVEN 一份导出中某决策节点的行动频率总和不是 10,000 basis points
- WHEN 导入工具处理该导出
- THEN 导入失败并指明场景 ID 与实际频率总和
- AND 不产出任何部分写入的策略包

##### Scenario: 导入是确定性的

- GIVEN 同一份求解器导出
- WHEN 导入工具运行两次
- THEN 两次产出的策略包字节完全相同
- AND 内容版本与 checksum 一致

#### Requirement: 内容随包交付与可选更新

The system SHALL ship a bundled strategy pack that works offline, and MAY replace it with a newer verified pack fetched from the sync service.

##### Scenario: 首次离线启动使用内置内容

- GIVEN 设备从未联网且从未拉取过内容
- WHEN 用户打开 APP
- THEN 训练可以立即开始
- AND 使用的内容来自随包内置的策略包

##### Scenario: 更新包 checksum 不匹配时保留内置内容

- GIVEN 服务端提供了一个更新包但其 SHA-256 与声明不符
- WHEN 客户端校验下载内容
- THEN 拒绝该更新
- AND 继续使用当前已验证的内容而不是降级到无内容状态

##### Scenario: 更新包内容版本不高于当前

- GIVEN 服务端提供的包 content version 不高于本机当前使用的版本
- WHEN 客户端评估是否替换
- THEN 不替换
- AND 训练历史中记录的原 pack ID 与 content version 不受影响

### Capability: initial-diagnostic

#### Requirement: 跨维度初始诊断

The system SHALL offer an initial diagnostic that samples across position, street, stack depth, and error type to produce a first ability profile.

##### Scenario: 完成诊断

- GIVEN 用户尚无训练历史
- WHEN 用户完成初始诊断的全部题目
- THEN 生成覆盖所有被采样能力维度的初始画像
- AND 今日计划依据该画像生成
- AND 诊断产生的每道题都写入不可变训练事件

##### Scenario: 跳过诊断

- GIVEN 用户在首次启动时选择跳过诊断
- WHEN 用户直接进入训练
- THEN 训练立即可用
- AND 今日计划从均衡采样的先验开始，并随实际作答收敛
- AND 诊断入口在今日页保留，可随时补做

##### Scenario: 中断后恢复

- GIVEN 用户完成了部分诊断题目后退出 APP
- WHEN 用户再次打开 APP
- THEN 已完成的题目不重复出现
- AND 诊断可从中断处继续

### Capability: adaptive-curriculum

#### Requirement: 现金局能力树

The system SHALL organize cash-game competence as a tree of nodes, each mapped to the ability dimensions its scenarios exercise.

##### Scenario: 浏览能力树

- GIVEN 已安装的策略内容
- WHEN 用户打开学习页
- THEN 显示现金局能力树的节点、依赖关系与当前掌握状态
- AND 每个节点显示其可练习的场景数量

##### Scenario: 内容缺失的节点

- GIVEN 能力树中某节点在当前内容包里没有对应场景
- WHEN 用户浏览该节点
- THEN 该节点显式标记为暂无内容
- AND 该节点不进入今日计划，也不计入掌握进度分母

#### Requirement: 节点掌握判定

The system SHALL mark a node mastered only when minimum sample, recent stability, confidence calibration, completed spaced repetition, and transfer performance are all satisfied.

##### Scenario: 样本不足不判定掌握

- GIVEN 某节点的作答数量低于最小样本
- WHEN 系统评估掌握状态
- THEN 节点不标记为掌握
- AND 显示还需要的样本量

##### Scenario: 高信心错误阻止掌握

- GIVEN 某节点近期存在高信心且明显亏损的错误
- WHEN 系统评估掌握状态
- THEN 节点不标记为掌握
- AND 该节点在今日计划中获得更高优先级

##### Scenario: 陌生场景迁移通过后判定掌握

- GIVEN 某节点已满足样本、稳定性与信心校准，且完成了复练
- WHEN 用户在该节点下未见过的场景中仍然保持稳定表现
- THEN 节点标记为掌握
- AND 掌握判定所依据的信号可在界面上查看

#### Requirement: 学习路径推荐

The system SHALL recommend a next node based on the profile rather than requiring the user to choose.

##### Scenario: 今日计划来自画像而非用户选择

- GIVEN 用户有包含多个弱项的能力画像
- WHEN 用户打开今日页
- THEN 计划已生成且无需用户先做选择
- AND 每个计划项显示被选中的原因

##### Scenario: 用户直接选择具体节点

- GIVEN 用户想练习一个不在今日计划里的节点
- WHEN 用户从能力树进入该节点
- THEN 训练照常进行
- AND 产生的事件同样进入画像归约

### Capability: spaced-repetition

#### Requirement: 同类非同题复现

The system SHALL re-surface a previously failed ability dimension using a different scenario, never the identical question.

##### Scenario: 隔日复练

- GIVEN 用户昨天在某能力维度上答错
- WHEN 今日计划生成
- THEN 该维度出现复练项
- AND 复练使用的场景与上次答错的场景不同

##### Scenario: 内容不足以避免重复

- GIVEN 某能力维度在内容包中只有一个场景
- WHEN 复练需要出题
- THEN 不重复出同一题
- AND 该维度的复练标记为受内容限制而挂起

#### Requirement: 复现间隔随表现变化

The system SHALL lengthen the interval after a correct repetition and shorten it after a failure.

##### Scenario: 连续答对拉长间隔

- GIVEN 某维度的上一次复练答对
- WHEN 系统安排下一次复现
- THEN 间隔比上一次更长

##### Scenario: 复练再次失败缩短间隔

- GIVEN 某维度的复练再次答错
- WHEN 系统安排下一次复现
- THEN 间隔缩短
- AND 该维度在今日计划中的优先级提高

### Capability: versioned-strategy-content

<!-- 归档时本节整块替换 openspec/specs/versioned-strategy-content/spec.md，
     因此未变更的 Requirement 与 Scenario 也必须原文保留。 -->

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

The system SHALL distinguish `testFixture`, `unverifiedDraft`, `reviewed`, and `retired` strategy content, and SHALL NOT present content of any status other than `reviewed` as verified poker advice.

##### Scenario: 已审核内容缺少审核时间

- GIVEN review status 为 `reviewed` 且 reviewed-at 为空
- WHEN validator 校验
- THEN 策略包被拒绝

##### Scenario: 已审核内容缺少审核来源

- GIVEN review status 为 `reviewed` 且 reviewed-by 为空
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 错误指明缺失的是审核来源而非其他 manifest 字段

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

##### Scenario: 未审核内容不得进入商店发布

- GIVEN 一个面向 App Store 提交的构建
- WHEN 发布门禁检查随包策略内容的 review status
- THEN 存在任何 `testFixture` 或 `unverifiedDraft` 的包都使门禁以非零码失败
- AND 失败信息列出违规包的 pack ID 与其 review status

##### Scenario: dogfooding 构建可以携带未审核内容

- GIVEN 一个供作者自用、不提交 App Store 的构建
- WHEN 该构建随包携带 `unverifiedDraft` 内容
- THEN 门禁通过且训练可以开始
- AND 由该内容生成的界面仍显示“未经策略审核”

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

The system SHALL rank training catalog items using weakness, high-confidence errors, days since practice, forgetting risk, and the active learning path.

##### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

##### Scenario: 到期复练排在未到期项目之前

- GIVEN 某维度的复练已到期，另一维度的复练尚未到期且两者弱项程度相同
- WHEN planner 生成今日项目
- THEN 已到期的维度排在未到期的维度之前

##### Scenario: 每个计划项给出被选中的原因

- GIVEN 今日计划已生成
- WHEN 读取任意一个计划项
- THEN 该项携带一个非空的、来自枚举的入选原因（弱项、高信心错误、复练到期或学习路径推进）
- AND 该原因在相同输入下保持稳定

##### Scenario: 计划受可用时长约束

- GIVEN 今日计划的目标时长上限为 10 分钟，且每项的预计时长已知
- WHEN planner 生成计划
- THEN 计划项预计时长之和不超过 10 分钟
- AND 至少包含一项

#### Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the active profile's local event store after a completed or synchronized decision.

##### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 今日主训练可以指向该弱项

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

#### Requirement: 能力树节点掌握信号

The system SHALL expose, for every curriculum node, which of the five mastery signals it currently satisfies and which it does not.

##### Scenario: 查看未掌握原因

- GIVEN 某节点样本数为 4、最小样本为 20，且存在一个未完成的复练
- WHEN 用户查看该节点
- THEN 界面列出未满足的信号为“样本不足（4/20）”与“复练未完成”
- AND 已满足的信号也逐项列出，而不是只给出一个未掌握结论

## 设计阶段需决断的点

以下问题影响架构，留给 `/harness-plan` 决定，不在本提案中预设答案：

1. **dogfooding 构建如何与商店发布区分。** 今天 `Config/` 只有 Debug 与 Release 两套配置，Release 即商店发布。要让作者能用 `unverifiedDraft` 内容连续使用四周（roadmap 的 M4 前置门槛），需要第三套配置，或在提交环节而非构建环节设卡。这个选择决定了 `check-m1b-release-secrets.sh` 类门禁的判定依据。
2. **能力树节点与 ability dimension 的映射关系。** 现有事件只带单一 `abilityDimension` 字符串。节点是与维度一一对应，还是一个节点聚合多个维度，影响掌握判定与画像归约的形状，也影响是否需要改动 M1A 的事件契约——按 `m1a-module-boundaries.md`，事件语义不得改变。
3. **复练调度状态存放位置。** 下次复现时间可以从事件历史推导（无新增状态、跨设备自然一致），也可以单独持久化（更快，但需要纳入同步与档案隔离）。前者与"画像由完整事件确定性归约"的既有约束更一致。
4. **内容更新通道是否在本次启用。** 提案已定"内置为主、更新可选"，但更新端点是否落在 M1C 交付范围内需要明确；若推迟，`strategy-content-pipeline` 的交付边界仅到随包内置与校验。

## Impact

- **Code:**
  - `Packages/StrategyContent/` — 审核状态扩展、内容包交付与更新校验
  - `Packages/TrainingDomain/` — 能力树节点掌握判定、复练调度、计划优先级扩展
  - 新增内容导入工具（求解器输出 → 策略包）
  - `PokerCoach/Features/Learn/` — 能力树界面
  - `PokerCoach/Features/Today/` — 诊断入口与计划原因展示
  - `PokerCoach/App/AppDependencies.swift` — 首次走通 `reviewedContentAvailable`
  - `Server/` — 可选内容分发端点（若启用更新通道）
- **Interfaces:** 新增内容包更新的 HTTPS 端点；能力树与诊断为新增 UI 入口；导入工具为本地开发工具，不对外暴露。
- **Dependencies:** 无新增运行时依赖。导入工具依赖求解器导出格式，该格式在 design 阶段确定。

## Risks

- **生成内容被误当作已审核策略** → 新增 `unverifiedDraft` 状态、强制界面披露、发布门禁拒绝非 `reviewed` 内容随包交付。
- **能力树节点与内容覆盖不匹配，导致节点永远无法掌握** → 无内容的节点显式标记并排除出计划与进度分母。
- **复练在小内容集下退化为重复同一题** → 明确"同类非同题"约束，内容不足时挂起该维度的复练而不是重复出题。
- **掌握判定过松让用户误以为已掌握** → 掌握需同时满足五项信号，且界面显示缺失的具体信号而非笼统结论。
- **内容更新破坏历史可追溯** → 已发布内容版本不可原地修改，事件永久记录当时的 pack ID 与 content version。
- **导入工具产出不确定导致 checksum 漂移** → 要求同一输入两次导入字节相同。

## Non-Goals

- 不做锦标赛能力树、短码、Ante、ICM（属于 M3）。
- 不做连续牌局模拟与虚拟对手（属于 M2A）。
- 不做牌谱导入与场景构建（属于 M2B）。
- 不做订阅、权益与上架（属于 M4）。
- 不由本次变更产出经人工策略审核的 `reviewed` 内容；本次交付的是把内容变为 `reviewed` 的通路与在此之前的诚实标注。
- 不做生成式教练文案；教练文本仍只组织已有结构化分析。

## Acceptance Criteria

1. Release 构建随包内置策略内容，首次离线启动即可训练，`reviewedContentAvailable` 在生产代码中被真实构造。
2. 求解器导出可经导入工具产出通过全部语义校验的策略包，且同一输入两次导入字节相同。
3. 初始诊断可完成、可跳过、可中断后继续；跳过后今日计划仍可生成。
4. 学习页显示现金局能力树，无内容的节点显式标记且不计入进度分母。
5. 节点掌握需同时满足最小样本、近期稳定性、信心校准、复练完成与迁移表现；未掌握时显示缺失的具体信号。
6. 复练出题与上次答错的场景不同；内容不足时该维度复练挂起而非重复出题。
7. 复练间隔在答对后拉长、答错后缩短。
8. 任何由 `unverifiedDraft` 内容生成的界面都显示未经策略审核的提示。
9. 发布门禁在随包内容为 `testFixture` 或 `unverifiedDraft` 时失败。
10. 内容升级后，既有训练事件记录的 pack ID 与 content version 不被改写，复盘仍可显示当时的内容版本。
11. `bash scripts/verify-m1a.sh` 与 `bash scripts/verify-m1b.sh` 仍然通过。
