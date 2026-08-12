# Capability: virtual-opponents

## Requirement: 四种可披露的对手档案

The system SHALL offer four named opponent profiles whose tendencies are stated to the user as defined values, and SHALL disclose that these are fixed heuristics rather than solver strategy.

### Scenario: 档案与其倾向对用户可见

- GIVEN 用户开始一局 Session
- WHEN 查看对手信息
- THEN 显示的名称等于所选档案的 `name`，显示的入池率、激进度与跟注倾向数值逐字段等于该档案定义
- AND 四种档案同时列出，四组数值两两不同
- AND 同一档案下打完 30 手后重新查看，显示的数值未改变

### Scenario: 对手行为的来源被披露

- GIVEN 任意一局 Session
- WHEN 用户查看对手信息
- THEN 显示「对手为固定启发式规则，不是求解器策略」
- AND 该文案与策略内容的披露文案是两条独立文案

### Scenario: 同一局面同一档案的行动唯一确定

- GIVEN 种子 42、固定局面与同一档案
- WHEN 在两个独立进程中各求一次
- THEN 两次行动相同
- AND 对种子 42 的 30 手，该档案的行动序列逐个等于 `Tests/Fixtures/opponent-<profile>-seed42.json` 中提交的黄金序列

### Scenario: 四种档案在同一局面下行为可区分

- GIVEN `Tests/Fixtures/opponent-spots-20.json` 中 20 个固定局面
- WHEN 四种档案分别在每个局面求行动
- THEN 任意两种档案之间至少在 5 个局面上行动不同
- AND 在这 20 个局面 × 50 个生成器种子上，每种档案都至少弃牌一次、至少过牌或跟注一次、至少下注或加注一次

## Requirement: 对手行动始终合法

The system SHALL only produce opponent actions the betting state permits.

### Scenario: 短码对手不会超额下注

- GIVEN 对手剩余 3BB，面对一次 5BB 的下注，须投入额度已被状态机封顶为 3BB
- WHEN 四种档案分别求行动
- THEN 每种档案的行动都属于 `{.fold, .call(to: 3BB)}`
- AND 四种档案中至少一种返回 `.fold`、至少一种返回 `.call(to: 3BB)`
