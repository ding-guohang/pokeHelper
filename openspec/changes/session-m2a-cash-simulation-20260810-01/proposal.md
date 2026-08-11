---
name: session-m2a-cash-simulation-20260810-01
created: 2026-08-10
status: review_passed
---

# 需求提案：M2A 现金局 Session 模拟

## Why

M1C 让 APP 第一次有了真实内容，但训练仍然是**孤立的单点决策**：一道题、一次反馈、下一道题。真实的现金局是连续的——同一个对手连打三十手、你的形象在累积、上一手的弃牌影响这一手的读牌。孤立决策练不出这些。

M2A 补上连续性：可复现的发牌、四种虚拟对手、15/30/60 手的 Session，以及打完之后挑出真正决定输赢的那几手来复盘。

还补上职业牌手真正在用的那一步：**按位置的聚合频率对照**。职业工作流是「打 → 导进 tracker → 看各位置的 VPIP/PFR → 对比基准 → 定位漏洞 → 针对性学习」，中间那一步是聚合而不是单手，因为单手噪声太大。单手复盘看的是「这手打错没有」，聚合看的是「我这个位置整体打得太松还是太紧」——后者才是可以拿去练的漏洞。这一步不需要给任何单手评分：实际频率来自记录的手牌，基准来自内容包的范围表。

## What Changes

### New Capabilities

- `session-dealing` — 由种子确定的发牌与永远合法的下注状态机。
- `virtual-opponents` — 四种可披露、确定性的对手策略。
- `cash-session-run` — 15/30/60 手的 Session，可中断续打。
- `key-hand-review` — 从一局 Session 中挑出值得复盘的手牌，并与已安装内容对照。
- `session-frequency-report` — 跨 Session 累计的按位置翻前频率，与内容基准对照。

### Modified Capabilities

- `cash-decision-domain` — 明确 `amountToCall` 是「该玩家实际须投入的额度」，由上游封顶到有效筹码；并明确筹码用尽时的跟注就是全下。
- `local-learning-profile` — 明确 Session 手牌**不产生** TrainingEvent；只有用户在复盘里主动「重打」时才走原有的带信心训练管线。

### Removed Capabilities

无。

## 已确定的设计约束

### 1. 没有策略就不评分，且不为绕开信心而降级评分

`DecisionScorer` 需要 `DecisionScenario.options`——即这个具体局面下每个行动的频率与 EV。内容包为**特定场景**提供这些；随机发出的牌局没有。

更强的一条约束来自现有规格：`explainable-decision-training` 要求**行动与信心共同提交**才评分，并要求**在展示反馈前**持久化事件。Session 里连续打牌不会、也不该在每个决策点弹出信心选择——那就不是打牌了。

因此 **Session 手牌一律不产生 `TrainingEvent`**，无论是否命中内容。命中内容的手牌在复盘里做**对照**（你打了什么 / 内容说的频率是什么），并提供「以训练模式重打这一手」——重打走的是既有管线：出示行动与信心、评分、反馈前落库。

这样做的直接后果是好的：Session 手牌无法伪造样本量、无法满足掌握判定里的复练与迁移信号，而「迁移」本来就是要在**没见过**的局面上发生的，用只有命中内容才计分的规则去喂它是把信号喂反了。

### 2. Session 记录与训练事件是两种东西

`SessionHand` 记录发生了什么（牌、行动、底池、结果），`TrainingEvent` 记录一次**被评分的决策**。前者不进入 `Contracts/training-event-upload-v1.json`，事件契约不变。

### 3. 「局面等同」M2A 只判翻前

等同关系的唯一用途是决定哪些手牌值得在复盘里对照，因此判错的代价是「给你看了一条不相干的对照」，而不是污染画像。即便如此仍需可测判据。

判定的是**内容是否覆盖这个局面**，四项全部满足：

- 街道同为 preflop
- 英雄位置（`heroSeatOffsetFromButton`）相等
- 面对的行动类别相等（未面对下注 / 面对单次加注 / 面对再加注）
- 有效筹码落入同一分桶，分桶边界在本 spec 中枚举：`[0, 2000)`、`[2000, 6000)`、`[6000, 12000)`、`[12000, ∞)` centi-BB

**手牌类别不在键里。** 场景的 `heroCards` 只是训练时展示的示例手牌，`rangeCells` 覆盖的是整段范围——已发布内容每个场景列 47 到 102 个手牌类别。把示例手牌写进键，等于要求用户恰好摸到那一手才给对照。

在真实路径上实测（200 个种子 × 30 手 = 6000 手，对着已发布的 `CoreStrategyPack.json`）：

| | 含手牌类别的旧键 | 不含手牌类别的覆盖键 |
|---|---|---|
| 命中手数 | 15 手，0.25%，每 400 手一次 | 2257 手，37.62% |
| 每 30 手 Session 期望命中 | 0.07 次 | 11.29 次 |
| 翻前决策被覆盖 | 0.26% | 39.99% |
| 翻前未面对下注的决策被覆盖 | — | 65.16% |

旧键下那条闭环等于不存在。

正确的做法是：先判局面被覆盖，再把英雄的实际手牌拿到该场景的范围表里查。范围表里没有这个类别，就是「该范围对这手牌是 100% 弃牌」，同样是一个可比对的答案。

65.16% 而不是「五个位置除以六」的 83%，差额全部来自筹码分桶漂移：3424 个翻前未面对下注的决策里只有 2369 个仍在 `deep` 桶内，而这 2369 个里 94.17% 被覆盖。内容是按 100BB 写的，筹码漂出该深度后内容就不再适用——这是正确行为，不是缺陷，但意味着长局的覆盖率会随筹码分散而下降。

**翻后不做匹配**，因为翻后手牌类别需要一套本项目尚未定义、也无求解器依据可定义的分类法。翻后对照属于 M2B。

这不是损失：核对过 `PokerCoach/Resources/CoreStrategyPack.json`，已发布内容的 6 个场景**全部是翻前**（board 长度为 0），102 个手牌类别全部是合法的 169 格记号（13 对子 / 57 同花 / 32 非同花，对子不带后缀）。翻后本来就没有内容可对照。

底池不参与判定：翻前底池由盲注与加注序列决定，已被「面对的行动类别」和分桶覆盖，再单列一个连续量只会让等同关系永不成立。

### 4. 对手策略必须可披露且确定性

对手不是「AI」，是四张写死的行为表。给定 (种子, 局面, 档案)，它的行动唯一确定。界面必须能显示当前对手档案及其倾向——否则用户在跟一个不可知的东西对练，学到的东西无法迁移。

档案是**策略形状的真值**，因此与策略内容承担同一条披露义务：界面必须写明对手行为来自固定启发式规则，不是求解器策略，也不代表真实牌手。

### 5. 桌型、抽水与筹码在 M2A 是常量

- 6-max，英雄 + 5 名对手，每个座位由种子独立指派档案。
- 所有座位起始 100BB，Session 内不补码、不换座。
- **抽水恒为 0**。写清楚是为了让「筹码守恒」成为一条有内容的断言，而不是一个未定义项掩护下的恒真式。

## Capabilities Detail

### Capability: session-dealing

#### Requirement: 发牌由种子完全确定

The system SHALL derive every card in a session from a recorded seed, so the same seed replays the same session card for card.

##### Scenario: 同种子重放相同牌局

- GIVEN 种子 42 与手数 30
- WHEN 在两个独立进程中各生成一次
- THEN 两次的每一手英雄手牌、公共牌与对手手牌完全相同
- AND 两次的对手行动序列逐个相同，且序列长度不少于 30
- AND 两次结果逐字段等于 `Tests/Fixtures/session-seed42-30hands.json` 中提交的黄金记录

##### Scenario: 不同种子产生不同牌局

- GIVEN 种子 42 与种子 43
- WHEN 各生成 30 手
- THEN 至少 29 手的英雄手牌不同

##### Scenario: 一副牌内不出现重复牌

- GIVEN 种子 42 的 30 手
- WHEN 检查每一手的英雄手牌、对手手牌与公共牌
- THEN 每一手恰好发出 2 张英雄手牌与 10 张对手手牌
- AND 公共牌张数按该手到达的街道恰为 0、3、4 或 5
- AND 同一手内任意两张牌互不相同

#### Requirement: 下注状态永远合法

The system SHALL reject any action the current betting state does not permit, and SHALL expose at every decision point the complete set of permitted actions.

##### Scenario: 超出筹码的加注被拒绝

- GIVEN 英雄剩余 2BB，面对一次加注，须投入额度已被状态机封顶为 2BB
- WHEN 尝试加注到 6BB
- THEN 行动被拒绝并返回 `SessionActionError.exceedsEffectiveStack`
- AND 合法行动集合恰为 `{.fold, .call(to: 2BB)}`——其中 `call(to: effectiveStack)` 即为全下
- AND Session 状态未改变

##### Scenario: 每个决策点都给出完整合法集合

- GIVEN 种子 42 的 30 手中的每一个决策点
- WHEN 读取当前状态
- THEN 集合中的每个行动都能被状态机接受
- AND 任何不在该集合中的行动都被状态机拒绝
- AND 未面对下注时集合同时包含 check 与至少一个下注尺度
- AND 面对下注且剩余筹码大于须跟注额时集合同时包含 fold、call 与至少一个 raise 尺度

##### Scenario: 筹码守恒

- GIVEN 种子 42 的 30 手，抽水为 0
- WHEN 每一手结算完成
- THEN 该手所有玩家筹码变化之和等于 0
- AND 每一层底池都记有至少一名赢家
- AND 发出的筹码总额等于投入的筹码总额
- AND 结算后底池为 0
- AND 30 手结束时六个座位筹码之和等于 600BB

##### Scenario: 零增量的手牌必须解释得通

- GIVEN 200 个种子各 15 手，共 3000 手
- WHEN 检查所有玩家筹码变化都不为正的手牌
- THEN 每一手要么是唯一投入者取回自己的盲注，要么是多名投入者平分且各自取回原额
- AND 两种情形在扫描中都至少出现一次
- AND 不存在既非上述两者、筹码却减少的手牌

### Capability: virtual-opponents

#### Requirement: 四种可披露的对手档案

The system SHALL offer four named opponent profiles whose tendencies are stated to the user as defined values, and SHALL disclose that these are fixed heuristics rather than solver strategy.

##### Scenario: 档案与其倾向对用户可见

- GIVEN 用户开始一局 Session
- WHEN 查看对手信息
- THEN 显示的名称等于所选档案的 `name`，显示的入池率、激进度与跟注倾向数值逐字段等于该档案定义
- AND 依次选择四种档案，四次显示的数值组合两两不同
- AND 同一档案下打完 30 手后重新查看，显示的数值未改变

##### Scenario: 对手行为的来源被披露

- GIVEN 任意一局 Session
- WHEN 用户查看对手信息
- THEN 显示「对手为固定启发式规则，不是求解器策略」
- AND 该文案与策略内容的披露文案是两条独立文案

##### Scenario: 同一局面同一档案的行动唯一确定

- GIVEN 种子 42、固定局面与同一档案
- WHEN 在两个独立进程中各求一次
- THEN 两次行动相同
- AND 对种子 42 的 30 手，该档案的行动序列逐个等于 `Tests/Fixtures/opponent-<profile>-seed42.json` 中提交的黄金序列

##### Scenario: 四种档案在同一局面下行为可区分

- GIVEN `Tests/Fixtures/opponent-spots-20.json` 中 20 个固定局面
- WHEN 四种档案分别在每个局面求行动
- THEN 任意两种档案之间至少在 5 个局面上行动不同
- AND 在这 20 个局面 × 50 个生成器种子上，每种档案都至少弃牌一次、至少过牌或跟注一次、至少下注或加注一次

#### Requirement: 对手行动始终合法

The system SHALL only produce opponent actions the betting state permits.

##### Scenario: 短码对手不会超额下注

- GIVEN 对手剩余 3BB，面对一次 5BB 的下注，须投入额度已被状态机封顶为 3BB
- WHEN 四种档案分别求行动
- THEN 每种档案的行动都属于 `{.fold, .call(to: 3BB)}`
- AND 四种档案中至少一种返回 `.fold`、至少一种返回 `.call(to: 3BB)`

### Capability: cash-session-run

#### Requirement: 三种长度的 Session

The system SHALL run sessions of 15, 30 or 60 hands and SHALL record the seed, profile assignment, opponent profile table version and hand count so a session can be replayed hand for hand.

##### Scenario: 完成一局 Session

- GIVEN 用户分别选择 15、30、60 手
- WHEN 打完全部手数
- THEN 三局都标记为完成
- AND 三局的 SessionHand 条数恰为 15、30、60
- AND 每条记录保存了种子、五个座位的档案指派、对手行为表版本与手数
- AND 用该记录重新构造 Session 得到逐手相同的牌与逐个相同的对手行动

##### Scenario: 行为表版本变化时拒绝静默重放

- GIVEN 一条记录的对手行为表版本与当前内置版本不同
- WHEN 用户重放该 Session
- THEN 系统不声称重放一致
- AND 明确告知该记录由另一版本的对手行为产生
- AND 仍可查看已保存的手牌记录

##### Scenario: 中断后续打

- GIVEN 用户打到第 7 手后终止进程
- WHEN 再次打开该 Session
- THEN 从第 8 手继续
- AND 前 7 手的记录未被改写
- AND 第 8 至 15 手的牌与对手行动，与同种子不中断连续打完的 Session 的第 8 至 15 手完全相同

#### Requirement: Session 手牌不进入能力画像

The system SHALL NOT create a TrainingEvent from a session hand, whether or not its spot matches installed content.

##### Scenario: 未命中内容的手牌不产生事件

- GIVEN 已安装内容非空，Session 中一手在翻前的位置与内容某场景相同但手牌类别不同
- WHEN 该手结束
- THEN 不产生 TrainingEvent
- AND 事件存储的条数不变
- AND 能力画像的样本量不变
- AND 该手仍出现在 Session 记录中

##### Scenario: 命中内容的手牌同样不产生事件

- GIVEN Session 中一手在翻前与某已安装场景等同
- WHEN 该手结束
- THEN 不产生 TrainingEvent
- AND 事件存储的条数不变
- AND 该手在 Session 记录中被标记为可对照

##### Scenario: 相邻分桶不算等同

- GIVEN 一手的街道、位置、面对的行动类别与手牌类别均与某场景相同，但有效筹码落在与该场景相邻的分桶
- WHEN 判定等同
- THEN 判定为不等同
- AND 该手不被标记为可对照

##### Scenario: 翻后手牌不参与匹配

- GIVEN 一手打到翻牌之后，其翻前部分与某已安装场景等同
- WHEN 判定等同
- THEN 只有该手的翻前决策点被标记为可对照
- AND 翻牌及之后的决策点都不被标记

### Capability: key-hand-review

#### Requirement: 挑出值得复盘的手牌

The system SHALL select between three and five key hands from a finished session using pot size, all-in occurrence, stack swing and content match, and SHALL state which of these caused each hand to be selected.

##### Scenario: 完成 Session 后给出关键手

- GIVEN 一局已完成的 30 手 Session
- WHEN 打开复盘
- THEN 列出 3 到 5 手关键手
- AND 每一手的入选原因为 `.deviation`、`.allIn`、`.bigSwing`、`.bigPot` 之一
- AND 标记 `.deviation` 的手，其翻前局面被已安装内容覆盖，且英雄的行动在该范围表对其手牌类别的权重低于 5000 基点
- AND 标记 `.bigPot` 的手，其底池必须是该 Session 底池最大的 5 手之一
- AND 标记 `.bigSwing` 的手，其英雄筹码变化绝对值不小于 20BB

##### Scenario: 全部小底池的 Session

- GIVEN 一局 15 手 Session，每手底池均不超过 3BB，第 4 手 3.0BB 为全局最大、第 9 手 2.9BB 次之
- WHEN 打开复盘
- THEN 列表非空，按选择分数降序排列
- AND 首项为第 4 手

##### Scenario: 偏离内容范围的手排在纯粹大底池之前

- GIVEN 一局 Session 中，第 3 手英雄在被内容覆盖的局面上做出了范围表权重为 0 的行动，第 8 手是全局最大底池但英雄的行动与范围表一致
- WHEN 打开复盘
- THEN 第 3 手排在第 8 手之前
- AND 第 3 手的原因为 `.deviation`，第 8 手不是

##### Scenario: 内容未覆盖的手不会被标为偏离

- GIVEN 一手的翻前局面在已安装内容里没有覆盖
- WHEN 选关键手
- THEN 该手的原因不可能是 `.deviation`
- AND 它仍可因底池、全下或波动入选

##### Scenario: 关键手不是「取前五手」

- GIVEN 两局同种子 Session，第二局把第 11 至 15 手的底池放大
- WHEN 分别打开复盘
- THEN 两次选出的手牌编号集合不同
- AND 第二次选出的手牌至少包含第 11 至 15 手中的两手

##### Scenario: 关键手可逐街回放

- GIVEN 一手打到河牌的关键手
- WHEN 用户逐街翻看
- THEN 四个街道分别显示 0、3、4、5 张公共牌
- AND 每个街道显示的底池等于该街道结束时的底池，四个数值不全相同
- AND 每个街道显示的行动只包含该街道发生的行动

#### Requirement: 命中内容的关键手可对照与重打

The system SHALL show, for a key hand whose preflop spot matches installed content, the user's action beside the content's frequencies, and SHALL let the user replay that spot through the normal training pipeline.

##### Scenario: 对照展示

- GIVEN 一手关键手的翻前局面与某已安装场景等同
- WHEN 用户打开该手
- THEN 显示用户当时的行动与该场景各行动的频率和 EV
- AND 明确标注这是对照，不是评分
- AND 不显示 EV 损失或质量等级

##### Scenario: 重打产生正常训练事件

- GIVEN 一手可对照的关键手
- WHEN 用户选择「以训练模式重打」，提交行动与信心
- THEN 产生一条 TrainingEvent，其 scenarioID 为该已安装场景
- AND 该事件带有用户提交的信心值
- AND 该事件在展示反馈前已持久化
- AND 能力画像的对应维度样本量加一

##### Scenario: 未命中内容的关键手不提供重打

- GIVEN 一手关键手在已安装内容里没有等同场景
- WHEN 用户打开该手
- THEN 可以逐街回放
- AND 不显示对照，也不显示「重打」入口

### Capability: session-frequency-report

#### Requirement: 按位置累计翻前频率并与内容基准对照

The system SHALL accumulate the user's realized preflop action frequencies per (position, facing action) pair across all recorded sessions, SHALL derive each baseline from the installed content's range chart for that same pair rather than from stored constants, and SHALL withhold any comparison verdict for a pair whose opportunity count is below 30.

##### Scenario: 样本不足时只报计数，不下结论

- GIVEN 用户在 BTN 位置累计有 8 次开池机会，阈值为 30
- WHEN 打开频率报告
- THEN 显示「BTN 8 次机会」与实际开池次数
- AND 不显示与基准的差值
- AND 显示「样本不足，暂不比较」
- AND 该位置不出现在漏洞列表里

##### Scenario: 样本足够时给出与基准的对照

- GIVEN 用户在 BTN 位置累计有 60 次开池机会，其中开池 42 次
- AND 已安装内容的 BTN 开池基准为 41.22%
- WHEN 打开频率报告
- THEN 显示实际 70.00%、基准 41.22%、差值 +28.78 个百分点
- AND 该位置出现在漏洞列表里，标注为偏松

##### Scenario: 差距在容差内不算漏洞

- GIVEN 某位置累计 60 次机会，实际频率与基准相差 3 个百分点
- WHEN 打开频率报告
- THEN 显示实际值、基准值与差值
- AND 该位置不出现在漏洞列表里
- AND 相差 6 个百分点的位置出现在漏洞列表里

##### Scenario: 基准由内容算出，不是写死的数字

- GIVEN 两个已安装内容版本，其 BTN 范围表的组合权重不同
- WHEN 分别打开频率报告
- THEN 两次显示的基准值不同
- AND 每次的基准值等于该版本 BTN 未面对下注范围表中的非弃牌组合数除以 1326

##### Scenario: 同一位置的不同面对情形各有各的基准

- GIVEN 已安装内容在 CO 位置同时有未面对下注与面对 3bet 两个场景
- WHEN 计算 CO 的基准
- THEN 未面对下注的基准为 24.86%，面对 3bet 的基准为 9.05%
- AND 两者不被合并成一个 CO 基准
- AND 英雄在 CO 面对 3bet 的手牌只计入面对 3bet 的机会数

##### Scenario: 内容未覆盖的位置不显示基准

- GIVEN 已安装内容没有 BB 位置的场景
- WHEN 打开频率报告
- THEN 显示 BB 的实际次数与频率
- AND BB 行不显示基准值或差值
- AND BB 不出现在漏洞列表里

##### Scenario: 无内容时不编造基准

- GIVEN 未安装任何内容
- WHEN 打开频率报告
- THEN 仍显示各位置的实际次数与频率
- AND 不显示任何基准值或差值
- AND 不出现漏洞列表

##### Scenario: 跨 Session 累计而不是单局

- GIVEN 三局各 15 手的已完成 Session
- WHEN 打开频率报告
- THEN 各位置的机会数等于三局之和
- AND 删除其中一局后，机会数相应减少

#### Requirement: 频率来自记录的手牌

The system SHALL compute every reported frequency from recorded session hands, never from an estimate or a running counter that can drift from the hands on disk.

##### Scenario: 报告可由记录重算

- GIVEN 一份任意的 Session 记录集合
- WHEN 计算频率报告两次，第二次在重新读取记录之后
- THEN 两次结果逐字段相等

##### Scenario: 未到该位置行动的手牌不计入机会数

- GIVEN 一手牌在英雄行动前已经结束
- WHEN 计算频率报告
- THEN 该手不计入英雄所在位置的机会数
- AND 也不计入开池次数

### Capability: cash-decision-domain

<!-- 归档时整块替换 openspec/specs/cash-decision-domain/spec.md；
     由 scripts/check-proposal-completeness.sh 机械校验。 -->

#### Requirement: 精确扑克值

The system SHALL represent pot and stack amounts as integer centi-big-blinds, EV as integer milli-big-blinds, and strategy frequencies as integer basis points.

##### Scenario: 精确金额运算

- GIVEN 两个可相加的 centi-BB 金额和两个可相减的 milli-BB EV
- WHEN 领域层执行运算
- THEN 结果使用整数精确计算
- AND 领域真值不依赖浮点数比较

#### Requirement: 稳定牌面表示

The system SHALL parse and serialize a card using a stable two-character rank/suit code.

##### Scenario: 合法牌往返

- GIVEN 输入 `As`
- WHEN 系统解析后重新序列化
- THEN 结果仍为 `As`
- AND 点数为 Ace、花色为 Spades

##### Scenario: 非法牌拒绝

- GIVEN 输入 `1x`
- WHEN 系统尝试解析
- THEN 解析失败
- AND 不产生部分 Card 值

#### Requirement: 合法行动过滤

The system SHALL derive the available fold, check, call, bet, raise, and all-in actions from a stored betting decision context, in which amount-to-call is the amount the acting player must actually put in and therefore never exceeds the effective stack.

##### Scenario: 未面对下注

- GIVEN amount-to-call 为零，配置了两个低于有效筹码的下注尺度
- WHEN 系统计算合法行动
- THEN 包含 check、两个 bet 和 all-in
- AND 不包含 fold、call 或 raise

##### Scenario: 面对下注

- GIVEN amount-to-call 大于零并存在 minimum-raise-to
- WHEN 系统计算合法行动
- THEN 包含 fold、call、达到最小加注要求的 raise 和 all-in
- AND 低于 minimum-raise-to 的配置尺度被排除

##### Scenario: 须跟注额被上游封顶到有效筹码

- GIVEN 上游下注为 5BB 而该玩家只剩 3BB
- WHEN 上游构造决策上下文
- THEN amount-to-call 为 3BB，等于有效筹码
- AND 合法行动集合恰为 `{.fold, .call(to: 3BB)}`
- AND 该集合不含独立的 all-in 项——筹码用尽时的 call 就是全下

#### Requirement: 稳定行动 JSON

The system SHALL encode decision actions with an explicit action kind and unit-bearing target amount.

##### Scenario: 带金额行动

- GIVEN 行动是 bet 到 2.17BB
- WHEN 系统编码 JSON
- THEN JSON kind 为 `bet`
- AND `toCentiBB` 为 `217`

##### Scenario: 行动字段不匹配

- GIVEN fold/check 包含金额或 bet/raise 缺少金额
- WHEN 系统解码
- THEN 解码失败并返回 typed error

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

##### Scenario: Session 手牌不写入事件

- GIVEN 一局 30 手 Session，其中若干手在翻前与已安装场景等同
- WHEN 整局打完
- THEN 事件存储的条数不变
- AND 无论是否命中内容都不产生 TrainingEvent

##### Scenario: 重打产生的事件与普通训练事件无从区分

- GIVEN 用户从关键手复盘里重打一个场景，另一用户从今日训练里作答同一场景，行动与信心相同
- WHEN 比较两条 TrainingEvent
- THEN 除 event ID、时间与设备外逐字段相等
- AND 事件中不含任何标示其来自 Session 的字段

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

1. **`SpotSignature` 放在哪一层。** 等同判定需要同时看 Session 局面与 `DecisionScenario`。若判定放进 `SessionSimulation` 就要 import `StrategyContent`，放进 `TrainingDomain` 就要 import `SessionSimulation`——两条都在分层规则之外。倾向把 `SpotSignature` 定义在 `PokerCore`，两侧各自产出签名，由 App 层比较；plan 阶段确认。
2. **Session 记录的存储与同步。** `SessionHand` 是否纳入跨设备同步。纳入则要扩展服务端；不纳入则换设备看不到历史 Session。
3. **对手档案的定义方式。** 硬编码为 Swift 值，还是作为内容随策略包交付。后者可以随内容更新，但要接受同一套审核与门禁。无论哪种，行为表都必须带版本号：Session 重放的确定性依赖它，改表而不改版本号会让旧 Session 静默重放出不同的牌。
4. **关键手选择分数的具体权重。** 四个原因的排序键与并列时的确定性 tie-break。

## Impact

- **Code:**
  - `Packages/PokerCore/` — 下注状态机、筹码守恒、`SpotSignature`
  - 新增 `Packages/SessionSimulation/` — 发牌、对手档案、Session 推进；只依赖 `PokerCore`
  - `PokerCoach/Features/Session/` — 新增 Session 与关键手复盘界面；对照与重打的桥接在此层
  - `PokerCoach/Infrastructure/` — Session 记录持久化
  - `docs/architecture/layering.md` — 把 `SessionSimulation` 写入层图
  - `scripts/verify-m2a.sh` — 一键验证
- **Interfaces:** Session 为新增 UI 入口。无新增服务端接口（除非设计点 2 决定同步）。
- **Dependencies:** 无新增运行时依赖。`Contracts/training-event-upload-v1.json` 不变。`TrainingDomain` 不新增依赖。

## Risks

- **给无策略可依的手牌编造评分** → Session 手牌一律不产生事件；有独立测试断言整局打完后事件条数不变。
- **绕过「行动与信心共同提交」** → 重打走既有管线，并有测试断言重打事件与普通训练事件逐字段无从区分。
- **Session 事件污染掌握判定的复练与迁移信号** → 由「不产生事件」从构造上排除，而非靠过滤。
- **发牌不可复现导致 Session 无法回放** → 种子驱动，跨进程确定性测试加提交的黄金记录，禁止 `hashValue`、系统时钟与字典迭代顺序参与。
- **对手行为不可知，用户学到无法迁移的东西** → 档案与其倾向来自定义而非运行时统计，界面披露其为固定启发式。
- **状态机漏判非法行动，产生不可能的牌局** → 断言合法集合的**双向**性质：集合内均可接受，集合外均被拒绝；每手结算断言筹码守恒且赢家增量为正。
- **关键手选择退化为「取前五手」** → 有一条断言「同种子放大后五手底池会改变选择结果」的测试。
- **等同判定过松，把不相干的对照摆在用户面前** → 有相邻分桶的反例测试；且判错只影响展示，不进入画像。
- **把同一位置的不同面对情形合并成一个基准。** 内容里 CO 有两个场景（未面对下注 24.86%、面对 3bet 9.05%），只按位置取基准会把两者混成一个没有含义的数。→ 基准按 (位置, 面对情形) 取键，并有一条断言两者不被合并的场景。
- **拿几手牌的频率当漏洞给用户看，教出的是噪声。** 6-max 里一个位置每 6 手才轮到一次，60 手 Session 也只给一个位置约 10 次机会，标准误约 ±16 个百分点 → 阈值 30 次机会以下只报计数不下结论，且跨 Session 累计。让用户学会「n=8 说明不了任何事」本身就是职业素养的一部分。
- **改对手行为表后旧 Session 静默重放出不同的牌** → 记录携带行为表版本，版本不符时拒绝声称一致而不是照放。

## Non-Goals

- 不做牌谱导入与场景构建（属于 M2B）。
- 不做翻后局面等同匹配（属于 M2B，需要先有翻后手牌分类法）。
- 不做锦标赛、Ante、ICM（属于 M3）。M2A 内的短码只作为 100BB 牌局中途的自然状态，不做短码桌型。
- 不做订阅与上架（属于 M4）。
- 不做多桌、不做非 6-max 桌型、不做补码与换座。
- M2A 抽水恒为 0，不做抽水模型。
- 不为 Session 手牌生成教练文案；反馈仍只组织已有结构化分析。
- 不把对手做成学习型 AI；档案是写死的行为表。

## Acceptance Criteria

1. 种子 42 在两个独立进程中重放出逐张相同的牌局与逐个相同的对手行动，并与提交的黄金记录逐字段相等。
2. 种子 42 的 30 手中，每手恰好发出 2 + 10 张底牌与街道对应的 0/3/4/5 张公共牌，同一手内无重复牌。
3. 每个决策点的合法集合双向成立：集合内行动均被接受，集合外行动均被拒绝；超出筹码的加注返回 `SessionActionError.exceedsEffectiveStack`。
4. 每手结算后筹码变化之和为 0、每层底池都有赢家、发出额等于投入额、底池归零；30 手后六座位筹码之和为 600BB。3000 手扫描中所有零增量手牌都可归为 walk 或平分。
5. 四种对手档案两两之间在 20 个固定局面上至少 5 个局面行动不同，且各自跨进程确定性。
6. 15/30/60 手 Session 各自可完成，可中断续打，且从记录重建得到逐手相同的牌；行为表版本不符时拒绝声称重放一致。
7. 整局 Session 打完后事件存储条数不变——命中内容与否都不产生 TrainingEvent。
8. 相邻筹码分桶不判定为等同；翻后决策点不被标记为可对照。
9. 从关键手复盘重打产生的 TrainingEvent，与今日训练产生的事件除 ID、时间、设备外逐字段相等。
10. 完成 Session 后给出 3 到 5 手关键手，每手带枚举原因；同种子放大后五手底池会改变选择结果。
11. 频率报告在机会数低于 30 时只报计数不给差值；达到阈值后给出的基准值等于内容范围表算出的组合占比。
12. Session、关键手复盘与频率报告在真实构建中可达，并有 UI 测试驱动。
13. `Contracts/training-event-upload-v1.sha256` 未变更。
14. `bash scripts/verify-m1a.sh`、`verify-m1b.sh`、`verify-m1c.sh` 仍然通过。
15. `bash scripts/check-proposal-completeness.sh session-m2a-cash-simulation-20260810-01` 通过。
