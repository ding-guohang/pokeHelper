# Capability: adaptive-curriculum

## Requirement: 现金局能力树

The system SHALL organize cash-game competence as a tree whose node membership is a property of the strategy content, resolved from a training event's `scenarioID` rather than stored on the event.

### Scenario: 浏览能力树

- GIVEN 一个内容包，其中映射到节点 `turn-barrel` 的场景有 7 个，且 `river-bluff-catch` 声明前置节点为 `turn-barrel`
- WHEN 用户打开学习页
- THEN `turn-barrel` 显示可练习场景数 7
- AND `river-bluff-catch` 显示其前置节点为 `turn-barrel`
- AND 每个节点显示其当前掌握状态

### Scenario: 内容缺失的节点

- GIVEN 能力树中节点 `river-bluff-catch` 在当前内容包里没有对应场景
- WHEN 用户浏览该节点
- THEN 该节点标记为暂无内容
- AND 该节点不出现在今日计划中
- AND 掌握进度分母不包含该节点

### Scenario: 事件所属内容版本不在本机

- GIVEN 一条训练事件记录的 content version 为 `2026.08.06`，而本机只有 `2026.09.01`
- WHEN 归约器为该事件求节点归属
- THEN 回退使用事件自带的 abilityDimension
- AND 该事件仍计入对应维度的样本，不被丢弃
- AND 该事件不计入任何节点的掌握判定

## Requirement: 节点掌握判定

The system SHALL mark a node mastered only when all five signals hold: at least 20 answers; at least 9 of the last 10 answers graded `excellent` or `acceptable`; every `verySure` answer among the last 10 graded `excellent` or `acceptable`; at least 2 completed due repetitions both graded `excellent` or `acceptable`; and 3 previously unanswered scenario IDs in that node all graded `excellent` or `acceptable`.

### Scenario: 五项信号齐备时判定掌握

- GIVEN 节点 `turn-barrel` 已有 20 次作答，最近 10 次全部为 excellent 或 acceptable
- AND 最近 10 次中所有 verySure 作答均为 excellent 或 acceptable
- AND 该节点已完成 2 次到期复练且两次均为 acceptable 以上
- WHEN 用户在该节点下 3 个此前未作答过的 scenario ID 上均得到 acceptable 以上
- THEN 该节点掌握状态为 mastered
- AND 节点详情显示五项信号全部满足，并给出各自实际值 20/20、10/10、2/2、3/3

### Scenario: 样本不足不判定掌握

- GIVEN 节点 `turn-barrel` 只有 4 次作答，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「样本 4/20」

### Scenario: 近期稳定性不足不判定掌握

- GIVEN 节点 `turn-barrel` 有 20 次作答，最近 10 次中只有 7 次为 excellent 或 acceptable，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「近期稳定性 7/10，需 9/10」

### Scenario: 高信心错误阻止掌握

- GIVEN 节点 `turn-barrel` 最近 10 次作答中存在一次 verySure 且 quality 为 improvable 或 blunder，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 该节点的计划优先级严格大于一个 sampleCount、meanScore、lastPracticedAt、nextDueAt 均相同但 highConfidenceErrorCount 为 0 的对照节点

### Scenario: 复练未完成不判定掌握

- GIVEN 节点 `turn-barrel` 只完成过 1 次到期复练，其余四项信号均满足
- WHEN 系统评估掌握状态
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示「复练 1/2」

### Scenario: 迁移未通过不判定掌握

- GIVEN 节点 `turn-barrel` 的其余四项信号均满足
- WHEN 用户在该节点下第 3 个此前未作答过的 scenario ID 上得到 blunder
- THEN 该节点掌握状态不为 mastered
- AND 节点详情显示迁移信号未满足

## Requirement: 学习路径推荐

The system SHALL recommend the next node from the profile without requiring the user to choose first, while still allowing a direct choice.

### Scenario: 今日计划来自画像而非用户选择

- GIVEN 画像 A 中 bet-sizing 最弱，画像 B 中 preflop-range 最弱，两者 catalog 相同
- WHEN 分别为 A 和 B 生成今日计划
- THEN A 的计划首项维度为 bet-sizing，B 的计划首项维度为 preflop-range
- AND 生成过程不需要任何用户选择交互

### Scenario: 用户直接选择具体节点

- GIVEN 用户想练习一个不在今日计划里的节点
- WHEN 用户从能力树进入该节点
- THEN 训练照常进行
- AND 产生的事件同样进入画像归约
