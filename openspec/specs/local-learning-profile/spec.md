# Capability: local-learning-profile

<!-- 归档时整块替换 openspec/specs/local-learning-profile/spec.md；
     由 scripts/check-proposal-completeness.sh 机械校验。 -->

## Requirement: 不可变本地训练事件

The system SHALL persist each completed decision as an immutable, append-only event that includes event ID, local user ID, device ID, occurrence time, scenario ID, strategy pack ID, content version, ability dimension, submission, and grade.

### Scenario: 首次追加

- GIVEN 本地事件存储为空
- WHEN APP 追加一个 TrainingEvent
- THEN 事件可按时间顺序读取
- AND 所有同步所需标识与评分字段均保留

### Scenario: 重复事件

- GIVEN 存储中已经存在相同 event ID
- WHEN APP 再次追加该事件
- THEN 存储内容不重复
- AND 读取结果仍只有一条该事件

### Scenario: 损坏事件文件

- GIVEN JSON Lines 文件的某一行无法解码
- WHEN store 初始化或读取
- THEN 返回包含行号的 typed corruption error
- AND 日志不输出完整事件正文

### Scenario: Session 手牌不写入事件

- GIVEN 一局 30 手 Session，其中若干手在翻前与已安装场景等同
- WHEN 整局打完
- THEN 事件存储的条数不变
- AND 无论是否命中内容都不产生 TrainingEvent

### Scenario: 重打产生的事件与普通训练事件无从区分

- GIVEN 用户从关键手复盘里重打一个场景，另一用户从今日训练里作答同一场景，行动与信心相同
- WHEN 比较两条 TrainingEvent
- THEN 除 event ID、时间与设备外逐字段相等
- AND 事件中不含任何标示其来自 Session 的字段

## Requirement: 能力画像归约

The system SHALL derive each ability dimension from its immutable training events.

### Scenario: 高信心错误

- GIVEN very-sure 决策被评为 improvable 或 blunder
- WHEN reducer 生成能力画像
- THEN 对应维度 high-confidence-error-count 增加
- AND 其他能力维度不受影响

## Requirement: 今日训练优先级

The system SHALL rank training catalog items using weakness, high-confidence errors, days since practice, repetition due date, and the active learning path, resolving conflicts in that stated order.

### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

### Scenario: 到期复练排在未到期项目之前

- GIVEN A 与 B 的 meanScore、highConfidenceErrorCount、lastPracticedAt 完全相同
- AND A 的 nextDueAt 为昨天、B 的 nextDueAt 为三天后，且 A 的 catalog ID 字典序排在 B 之后
- WHEN planner 生成今日项目
- THEN A 排在 B 之前
- AND A 的 priority 严格大于 B 的 priority

### Scenario: 高信心错误压过复练到期

- GIVEN A 有高信心错误但复练未到期，B 无高信心错误但复练已到期，其余输入相同
- WHEN planner 生成今日项目
- THEN A 排在 B 之前

### Scenario: 每个计划项给出被选中的原因

- GIVEN 四个画像，分别只具备低分、只具备高信心错误、只具备到期复练、只具备学习路径推进
- WHEN 分别生成今日计划
- THEN 四个计划的首项入选原因依次为 `.weakness`、`.highConfidenceError`、`.repetitionDue`、`.pathProgress`
- AND 该原因在相同输入下保持稳定

### Scenario: 计划受可用时长约束

- GIVEN 今日计划目标时长为 5 到 10 分钟，候选项充足且每项预计时长已知
- WHEN planner 生成计划
- THEN 计划项预计时长之和不超过 10 分钟且不少于 5 分钟
- AND 再加入任意一个未入选候选项都会超过 10 分钟

## Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the active profile's local event store after a completed or synchronized decision.

### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 重新生成的今日计划首项维度为 bet-sizing

## Requirement: 跨设备历史确定性归约

The system SHALL derive the active user's ability profile from the deduplicated union of locally created and synchronized TrainingEvents.

### Scenario: 远端事件进入画像

- GIVEN 同一账号的另一设备完成训练并同步
- WHEN 当前设备拉取并合并该事件
- THEN Today 与 Review 的样本和能力画像包含该事件
- AND 相同 event ID 的重复拉取不改变结果

### Scenario: 两台设备独立归约得到相同画像

- GIVEN 两台设备各自持有相同的去重事件集合，但本地写入顺序不同
- WHEN 各自独立归约
- THEN 两台设备得到逐字段相等的画像
- AND 该画像等于预期快照：bet-sizing 的 sampleCount 为 5、meanScore 为 62、highConfidenceErrorCount 为 2

## Requirement: 能力树节点掌握信号

The system SHALL expose, for every curriculum node, each of the five mastery signals with its satisfied state and its current numeric value.

### Scenario: 查看未掌握原因

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
8. 相邻筹码分桶不判定为等同；翻后决策点不被算作可对照。
9. 从关键手复盘重打产生的 TrainingEvent，与今日训练产生的事件除 ID、时间、设备外逐字段相等。
10. 完成 Session 后给出 3 到 5 手关键手，每手带枚举原因；同种子放大后五手底池会改变选择结果。
11. 频率报告在机会数低于 30 时只报计数不给差值；达到阈值后给出的基准值等于内容范围表算出的组合占比。
12. Session、关键手复盘与频率报告在真实构建中可达，并有 UI 测试驱动。
13. `Contracts/training-event-upload-v1.sha256` 未变更。
14. `bash scripts/verify-m1a.sh`、`verify-m1b.sh`、`verify-m1c.sh` 仍然通过。
15. `bash scripts/check-proposal-completeness.sh session-m2a-cash-simulation-20260810-01` 通过。
