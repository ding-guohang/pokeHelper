# Capability: session-dealing

## Requirement: 发牌由种子完全确定

The system SHALL derive every card in a session from a recorded seed, so the same seed replays the same session card for card.

### Scenario: 同种子重放相同牌局

- GIVEN 种子 42 与手数 30
- WHEN 在两个独立进程中各生成一次
- THEN 两次的每一手英雄手牌、公共牌与对手手牌完全相同
- AND 两次的对手行动序列逐个相同，且序列长度不少于 30
- AND 两次输出逐字节等于 `Tests/Fixtures/session-seed42-30hands.txt` 中提交的黄金记录

### Scenario: 不同种子产生不同牌局

- GIVEN 种子 42 与种子 43
- WHEN 各生成 30 手
- THEN 至少 29 手的英雄手牌不同

### Scenario: 一副牌内不出现重复牌

- GIVEN 种子 42 的 30 手
- WHEN 检查每一手的英雄手牌、对手手牌与公共牌
- THEN 每一手恰好发出 2 张英雄手牌与 10 张对手手牌
- AND 公共牌张数按该手到达的街道恰为 0、3、4 或 5
- AND 同一手内任意两张牌互不相同

## Requirement: 每一手都有盲注

The system SHALL post the small and big blind from the first two seats after the button that still hold chips, and SHALL NOT deal a hand when fewer than two seats hold chips.

### Scenario: 盲注位破产时盲注顺延

- GIVEN 按钮后第一个座位筹码为 0
- WHEN 发下一手
- THEN 小盲由按钮后第一个仍有筹码的座位贴出
- AND 大盲由其后第一个仍有筹码的座位贴出
- AND 该手的底池在任何人行动之前不为 0

### Scenario: 每一手都收到盲注

- GIVEN 200 个种子各 15 手
- WHEN 检查每一手行动开始前的底池
- THEN 每一手的底池都严格大于 0
- AND 不存在全场无人贴盲的手牌

### Scenario: 有筹码的座位少于两个时不再发牌

- GIVEN 一局 Session 打到只剩一个座位有筹码
- WHEN 尝试发下一手
- THEN 不发牌，Session 以已完成的手数结束
- AND 记录中的手数少于原定手数，且该情形被明确标示

## Requirement: 下注状态永远合法

The system SHALL reject any action the current betting state does not permit, and SHALL expose at every decision point the complete set of permitted actions.

### Scenario: 超出筹码的加注被拒绝

- GIVEN 英雄剩余 2BB，面对一次加注，须投入额度已被状态机封顶为 2BB
- WHEN 尝试加注到 6BB
- THEN 行动被拒绝并返回 `SessionActionError.exceedsEffectiveStack`
- AND 合法行动集合恰为 `{.fold, .call(to: 2BB)}`——其中 `call(to: effectiveStack)` 即为全下
- AND Session 状态未改变

### Scenario: 每个决策点都给出完整合法集合

- GIVEN 种子 42 的 30 手中的每一个决策点
- WHEN 读取当前状态
- THEN 集合中的每个行动都能被状态机接受
- AND 任何不在该集合中的行动都被状态机拒绝
- AND 未面对下注时集合同时包含 check 与至少一个下注尺度
- AND 面对下注且剩余筹码大于须跟注额时集合同时包含 fold、call 与至少一个 raise 尺度

### Scenario: 筹码守恒

- GIVEN 种子 42 的 30 手，抽水为 0
- WHEN 每一手结算完成
- THEN 该手所有玩家筹码变化之和等于 0
- AND 每一层底池都记有至少一名赢家
- AND 发出的筹码总额等于投入的筹码总额
- AND 结算后底池为 0
- AND 30 手结束时六个座位筹码之和等于 600BB

### Scenario: 零增量的手牌必须解释得通

- GIVEN 200 个种子各 15 手，共 3000 手
- WHEN 检查所有玩家筹码变化都不为正的手牌
- THEN 每一手要么是唯一投入者取回自己的盲注（且该投入额等于其应贴盲注），要么是多名投入者平分且各自取回原额
- AND 两种情形在扫描中都至少出现一次
- AND 两者的计数之和等于零增量手牌的总数——不存在归不进任何一类的手牌
