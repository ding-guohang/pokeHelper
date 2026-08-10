---
name: session-m2a-cash-simulation-20260810-01
created: 2026-08-10
status: draft
---

# 需求提案：M2A 现金局 Session 模拟

## Why

M1C 让 APP 第一次有了真实内容，但训练仍然是**孤立的单点决策**：一道题、一次反馈、下一道题。真实的现金局是连续的——同一个对手连打三十手、你的形象在累积、上一手的弃牌影响这一手的读牌。孤立决策练不出这些。

M2A 补上连续性：可复现的发牌、四种虚拟对手、15/30/60 手的 Session，以及打完之后挑出真正决定输赢的那几手来复盘。

## What Changes

### New Capabilities

- `session-dealing` — 由种子确定的发牌与永远合法的下注状态机。
- `virtual-opponents` — 四种可披露、确定性的对手策略。
- `cash-session-run` — 15/30/60 手的 Session，可中断续打。
- `key-hand-review` — 从一局 Session 中挑出值得复盘的手牌。

### Modified Capabilities

- `local-learning-profile` — 明确 Session 手牌与训练事件的关系：只有落在已安装内容场景上的决策才进入能力画像。

### Removed Capabilities

无。

## 已确定的设计约束

### 1. 没有策略就不评分

`DecisionScorer` 需要 `DecisionScenario.options`——即这个具体局面下每个行动的频率与 EV。内容包为**特定场景**提供这些；随机发出的牌局没有。

因此 **Session 中的决策默认不评分**，只记录。只有当发出的局面与已安装内容中的某个场景在语义上等同（位置、街道、有效筹码、底池、面对的行动、英雄手牌类别全部匹配）时，该手牌才产生 `TrainingEvent` 并进入能力画像。

这不是能力缺失，是拒绝编造判定。给一手无策略可依的牌打上「blunder」，与本项目此前驳回的生成内容是同一类错误。

### 2. Session 记录与训练事件是两种东西

`SessionHand` 记录发生了什么（牌、行动、底池、结果），`TrainingEvent` 记录一次**被评分的决策**。前者不进入 `Contracts/training-event-upload-v1.json`，事件契约不变。

### 3. 对手策略必须可披露且确定性

对手不是「AI」，是四张写死的行为表。给定 (种子, 局面, 档案)，它的行动唯一确定。界面必须能显示当前对手档案及其倾向——否则用户在跟一个不可知的东西对练，学到的东西无法迁移。

## Capabilities Detail

### Capability: session-dealing

#### Requirement: 发牌由种子完全确定

The system SHALL derive every card in a session from a recorded seed, so the same seed replays the same session card for card.

##### Scenario: 同种子重放相同牌局

- GIVEN 一个 Session 种子与手数 30
- WHEN 在两个独立进程中各生成一次
- THEN 两次的每一手英雄手牌、公共牌与对手手牌完全相同
- AND 两次的对手行动序列完全相同

##### Scenario: 不同种子产生不同牌局

- GIVEN 两个不同的种子
- WHEN 各生成 30 手
- THEN 至少 29 手的英雄手牌不同

##### Scenario: 一副牌内不出现重复牌

- GIVEN 任意种子与任意手数
- WHEN 检查每一手的英雄手牌、对手手牌与公共牌
- THEN 同一手内没有任何一张牌出现两次
- AND 每一手最多发出 2 + 2 × 对手数 + 5 张牌

#### Requirement: 下注状态永远合法

The system SHALL reject any action the current betting state does not permit, and SHALL expose the legal set at every decision point.

##### Scenario: 非法行动被拒绝

- GIVEN 面对 3BB 加注、英雄剩余 2BB
- WHEN 尝试加注到 6BB
- THEN 行动被拒绝并返回 typed error
- AND 合法行动集合为 {弃牌, 全下至 2BB}

##### Scenario: 每个决策点都给出合法行动集合

- GIVEN Session 中的任意决策点
- WHEN 读取当前状态
- THEN 合法行动集合非空
- AND 集合中的每个行动都能被状态机接受

##### Scenario: 筹码守恒

- GIVEN 一手牌从发牌到结算
- WHEN 结算完成
- THEN 所有玩家筹码变化之和加上抽水等于 0

### Capability: virtual-opponents

#### Requirement: 四种可披露的对手档案

The system SHALL offer four named opponent profiles whose tendencies are stated to the user, and SHALL play each deterministically.

##### Scenario: 档案与其倾向对用户可见

- GIVEN 用户开始一局 Session
- WHEN 查看对手信息
- THEN 显示对手档案名称与其倾向描述（入池率、激进度、跟注站或弃牌倾向）
- AND 描述来自档案定义，不是运行时统计

##### Scenario: 同一局面同一档案的行动唯一确定

- GIVEN 相同的种子、局面与对手档案
- WHEN 两次求对手行动
- THEN 两次行动相同

##### Scenario: 四种档案在同一局面下行为可区分

- GIVEN 一个面对下注的局面与四种档案
- WHEN 分别求行动
- THEN 至少三种档案给出的行动或频率互不相同

#### Requirement: 对手行动始终合法

The system SHALL only produce opponent actions the betting state permits.

##### Scenario: 短码对手不会超额下注

- GIVEN 对手剩余 3BB、当前需跟注 5BB
- WHEN 求对手行动
- THEN 行动只能是弃牌或全下至 3BB

### Capability: cash-session-run

#### Requirement: 三种长度的 Session

The system SHALL run sessions of 15, 30 or 60 hands and SHALL record the seed, profile and hand count so a session can be replayed.

##### Scenario: 完成一局 15 手 Session

- GIVEN 用户选择 15 手与一种对手档案
- WHEN 打完全部手数
- THEN Session 标记为完成
- AND 记录中有恰好 15 条 SessionHand
- AND 记录中保存了种子、对手档案与手数

##### Scenario: 中断后续打

- GIVEN 用户打到第 7 手后退出
- WHEN 再次打开该 Session
- THEN 从第 8 手继续
- AND 前 7 手的记录未被改写

#### Requirement: Session 结果与训练画像分离

The system SHALL write a TrainingEvent only for a hand whose spot matches an installed content scenario, and SHALL record every other hand as session history alone.

##### Scenario: 无对应内容的手牌不进入画像

- GIVEN Session 中一手的局面在已安装内容里没有等同场景
- WHEN 该手结束
- THEN 不产生 TrainingEvent
- AND 能力画像的样本量不变
- AND 该手仍出现在 Session 记录中

##### Scenario: 命中内容场景的手牌照常评分

- GIVEN Session 中一手的位置、街道、有效筹码、底池、面对的行动与手牌类别与某个已安装场景等同
- WHEN 用户作答并结束该手
- THEN 产生一条 TrainingEvent，其 scenarioID 为该场景
- AND 能力画像的对应维度样本量加一

### Capability: key-hand-review

#### Requirement: 挑出值得复盘的手牌

The system SHALL select key hands from a finished session by pot size, decision difficulty and outcome swing, and SHALL state why each was selected.

##### Scenario: 完成 Session 后给出关键手

- GIVEN 一局已完成的 30 手 Session
- WHEN 打开复盘
- THEN 列出不超过 5 手关键手
- AND 每一手显示其入选原因（大底池、艰难决策或结果大幅波动）

##### Scenario: 全部小底池的 Session

- GIVEN 一局 15 手 Session 中每手底池都不超过 3BB
- WHEN 打开复盘
- THEN 仍然列出关键手，按相对排序选出
- AND 不出现空列表

##### Scenario: 关键手可逐街回放

- GIVEN 一手关键手
- WHEN 用户打开它
- THEN 可以逐街查看当时的底池、筹码、行动与手牌
- AND 若该手命中了内容场景，同时显示当时的评分

### Capability: local-learning-profile

<!-- 归档时整块替换 openspec/specs/local-learning-profile/spec.md；
     由 scripts/check-proposal-completeness.sh 机械校验。 -->

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

##### Scenario: Session 手牌不写入无策略可依的事件

- GIVEN 一手 Session 牌局在已安装内容里没有等同场景
- WHEN 该手结束
- THEN 事件存储的条数不变

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

## 设计阶段需决断的点

1. **「局面等同」的判定粒度。** 决定哪些 Session 手牌能被评分。太严则几乎没有手牌命中，太松则拿错误的策略去评分。需要在 plan 阶段定义等同关系并写成可测的判据。
2. **Session 记录的存储与同步。** `SessionHand` 是否纳入跨设备同步。纳入则要扩展服务端；不纳入则换设备看不到历史 Session。
3. **对手档案的定义方式。** 硬编码为 Swift 值，还是作为内容随策略包交付。后者可以随内容更新，但要接受同一套审核与门禁。

## Impact

- **Code:**
  - `Packages/PokerCore/` — 下注状态机与筹码守恒（当前只有单点 `BettingDecisionContext`）
  - 新增 `Packages/SessionSimulation/` — 发牌、对手档案、Session 推进
  - `Packages/TrainingDomain/` — 局面等同判定与事件生成边界
  - `PokerCoach/Features/Session/` — 新增 Session 与关键手复盘界面
  - `PokerCoach/Infrastructure/` — Session 记录持久化
  - `scripts/verify-m2a.sh` — 一键验证
- **Interfaces:** Session 为新增 UI 入口。无新增服务端接口（除非设计点 2 决定同步）。
- **Dependencies:** 无新增运行时依赖。`Contracts/training-event-upload-v1.json` 不变。

## Risks

- **给无策略可依的手牌编造评分** → 只有命中内容场景的手牌才评分，其余只记录；有独立测试断言事件条数不变。
- **发牌不可复现导致 Session 无法回放** → 种子驱动，跨进程确定性测试，禁止 `hashValue`、系统时钟与字典迭代顺序参与。
- **对手行为不可知，用户学到无法迁移的东西** → 档案与其倾向必须在界面上可见，且来自定义而非运行时统计。
- **状态机漏判非法行动，产生不可能的牌局** → 每个决策点断言合法集合非空且集合内行动均可被接受；每手结算断言筹码守恒。
- **关键手选择退化为「取前五手」** → 需要一条断言「相同 Session 换一种排序输入会选出不同的手」的测试。
- **Session 记录混进能力画像，污染掌握判定** → 画像仍只由 TrainingEvent 归约，Session 记录是另一份数据。

## Non-Goals

- 不做牌谱导入与场景构建（属于 M2B）。
- 不做锦标赛、短码、Ante、ICM（属于 M3）。
- 不做订阅与上架（属于 M4）。
- 不做多桌、不做非 6-max 桌型。
- 不为 Session 手牌生成教练文案；反馈仍只组织已有结构化分析。
- 不把对手做成学习型 AI；档案是写死的行为表。

## Acceptance Criteria

1. 同一种子在两个独立进程中重放出逐张相同的牌局与逐个相同的对手行动。
2. 任意种子任意手数下，同一手内无重复牌，且每手发牌数不超过 2 + 2 × 对手数 + 5。
3. 每个决策点的合法行动集合非空，且集合内每个行动都能被状态机接受；非法行动返回 typed error。
4. 每手结算后筹码变化之和加抽水等于 0。
5. 四种对手档案在同一局面下至少三种行为可区分，且各自确定性。
6. 15/30/60 手 Session 可完成、可中断续打，记录保存种子、档案与手数。
7. 未命中内容场景的 Session 手牌不产生 TrainingEvent，能力画像样本量不变。
8. 命中内容场景的手牌产生 TrainingEvent 且进入画像。
9. 完成 Session 后给出不超过 5 手关键手，每手显示入选原因；全小底池时不返回空列表。
10. Session 与关键手复盘在真实构建中可达，并有 UI 测试驱动。
11. `Contracts/training-event-upload-v1.sha256` 未变更。
12. `bash scripts/verify-m1a.sh`、`verify-m1b.sh`、`verify-m1c.sh` 仍然通过。
13. `bash scripts/check-proposal-completeness.sh session-m2a-cash-simulation-20260810-01` 通过。
