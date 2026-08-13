# Capability: hand-lab-replay

## Requirement: 把已存储牌谱按其到达的街正确回放

The system SHALL replay a stored personal hand street by street, each street carrying the community cards visible during that street and that street's voluntary actions in recorded order (all players, not just the hero), and SHALL show only the streets the hand actually reached — never padding unreached streets.

### Scenario: 附录 A 回放为四条街且逐街公共牌与行动数正确

- GIVEN 第一切片附录 A 的 `ObservedHand`（翻前 6 个自主行动、翻牌 3、转牌 2、河牌 3，合计 14）
- WHEN 逐街回放
- THEN 恰得到 4 条街，`street` 依次 preflop/flop/turn/river
- AND 翻牌街公共牌恰为 `[Ac, 7h, 2s]`、转牌街 `[Ac, 7h, 2s, Td]`、河牌街 `[Ac, 7h, 2s, Td, 9c]`（每街是该街期间可见的牌，不是最终牌面）
- AND 各街自主行动数依次为 `[6, 3, 2, 3]`（含所有玩家的行动，非仅英雄——排除"只回放英雄行动"的实现）

### Scenario: 翻前结束的手只有一条街、不补空街

- GIVEN 一手在翻前即结束的已存储牌谱（附录 I：`32o` 从 CO 开池，众弃）
- WHEN 回放
- THEN 恰得到 1 条街（preflop），其公共牌为空
- AND 不补出空的翻牌/转牌/河牌街

## Requirement: 每个英雄节点给内容反事实，未命中不编造，回放不重模拟不产事件

The system SHALL, at each hero decision point in the replay, present the hero's actual action and — when the point's `SpotSignature` is covered by installed content — the content's basis-point weight for that action from the covering scenario's range table, mark an uncovered point as `NodeCoverage.uncovered` with no frequency shown, and SHALL neither fabricate a weight, present any action beyond those recorded, nor produce any `TrainingEvent` on replay.

### Scenario: 命中英雄节点给内容反事实，未命中标 uncovered

- GIVEN 附录 A：其英雄翻前节点被内容 S 覆盖（用 `HandLabContentFixture` 造该节点权重非整值 6234），翻后英雄节点无覆盖
- WHEN 回放并读取每个英雄节点的反事实
- THEN 翻前命中节点显示英雄行动与内容对该 `handClass`+行动的权重（== `scenario.rangeWeightBasisPoints(...)`，非编造）
- AND 翻后节点为 `NodeCoverage.uncovered`、不显示任何频率/EV；两者成对，排除"恒有/恒无反事实"的实现

### Scenario: 回放逐街行动与记录逐一相同，不重模拟对手

- GIVEN 附录 A 的 `ObservedHand`
- WHEN 回放
- THEN 回放每条街呈现的自主行动序列与 `ObservedHand.streets` 对应街的 `actions` 逐一相同（座位、种类、金额都相同，既不新增也不遗漏）
- AND 尤其不出现记录之外的、任何被生成/推断的对手后续行动

### Scenario: 回放不产生事件，命中节点完成补救才 +1

- GIVEN 一条持有非空训练事件存储（before.count ≥ 1）的回放路径，回放附录 A
- WHEN 用户回放并浏览各节点但不发起补救训练
- THEN 训练事件存储的条数与内容不变（after == before）
- AND 随后从某个命中英雄节点经回放自身的补救入口发起并完成一道补救训练后，事件存储恰 +1（普通训练事件，复用第三切片）——证明回放的补救入口是活的，且"不变"不是断链造成的

## Impact

- **Code:** App 层 `Features/HandLab` 新增回放呈现（数据源 `ObservedHand.streets`：每街公共牌+自主行动，不含派生底池）与回放视图；每个英雄节点复用 `heroDecisionSignatures()` + `classify(signature:action:)` 求反事实，命中处复用第三切片补救入口。无新领域类型、无新事件字段、不触碰结算。
- **Interfaces:** 复盘→Hand Lab→某手→回放（与"分析"并列）；无服务端接口变更。
- **Dependencies:** 复用 `HandHistory`/`StrategyContent`/既有补救；无第三方；不使用 `SessionSimulation` 的对手（导入牌无从重模拟）。

## Risks

- **臆造对手后续（把"反事实"做成重模拟）** → 断言回放逐街行动与记录逐一相同、含所有玩家；反事实只对照已审核内容真值；不引入对手模型。
- **逐街语义错（每街显示最终牌面）** → 每街只带该街期间可见的牌；附录 A 逐街公共牌钉死；翻前结束单街、不补空街。
- **为未命中节点编造频率** → 未命中记 `uncovered`、不显频率；命中权重钉到范围表非整值 6234；成对。
- **显示错误底池** → 本切片不显示派生底池（不为导入牌重实现结算）。
- **回放误产生事件 / 补救入口断链** → 非空存储下回放不 +1；成对断言：从命中节点完成补救才 +1（走回放自身入口）。

## Non-Goals

- **对手后续的重模拟/真正 what-if 续打**——导入真实牌无从得知对手后续，重模拟即编造；真正换打法重打整手只在 M2A Session（有虚拟对手）成立。
- **派生每街/最终底池展示**——需为导入牌重实现结算（未跟注返还、死盲、边池），有显示错误底池风险，推迟到有可靠来源。
- 翻后内容反事实（内容只有翻前，翻后节点一律 uncovered）；漏洞标签聚合；新事件字段或契约变更；对无覆盖节点评分。

## Acceptance Criteria

1. 附录 A 回放为 4 条街，逐街公共牌为该街期间可见的牌、各街自主行动数 `[6,3,2,3]`（含所有玩家）；翻前结束的手只 1 条街、公共牌空、不补空街。
2. 命中英雄节点显示内容权重反事实（== 范围表查得，非整值 6234），未命中记 `uncovered`、不显频率（成对）。
3. 回放逐街行动与记录逐一相同（不重模拟、不发明对手后续）；回放不产生 `TrainingEvent`，从命中节点完成补救才 +1（走回放自身入口）。
4. 分层不破坏：回放与反事实在 App 层，复用 `ObservedHand`/matcher/补救；不改其语义、不触碰结算、不改契约。
