# Capability: spaced-repetition

## Requirement: 同类非同题复现

The system SHALL re-surface a failed node using a scenario the user has not answered in that node, and SHALL NOT re-surface a node whose last answer was correct.

### Scenario: 隔日复练

- GIVEN 用户昨天在 bet-sizing 的场景 `s-101` 上得到 blunder，同日在 preflop-range 上全部为 acceptable
- WHEN 今日计划生成
- THEN 计划中存在 bet-sizing 的复练项
- AND 该复练项的 scenario ID 不是 `s-101`
- AND 计划中不存在 preflop-range 的复练项

### Scenario: 内容不足以避免重复

- GIVEN bet-sizing 在内容包中只有 `s-101` 一个场景，且用户已在其上答错
- WHEN 复练需要出题
- THEN 不产出以 `s-101` 为题的复练项
- AND 该维度的复练状态为「受内容限制而挂起」

## Requirement: 复现间隔阶梯

The system SHALL schedule repetitions on the ladder 1, 3, 7, 14, 30 days, advancing one rung after a correct repetition and falling back one rung after an incorrect one, never below one day, and SHALL expose each node's current `intervalDays` and `nextDueAt`.

### Scenario: 首次复练间隔为一天

- GIVEN 某节点首次出现答错，此前无复练记录
- WHEN 调度器安排复现
- THEN 该节点的 intervalDays 为 1
- AND nextDueAt 为答错时间的次日

### Scenario: 答对沿阶梯前进

- GIVEN 某节点当前 intervalDays 为 3，其到期复练得到 acceptable
- WHEN 调度器安排下一次复现
- THEN intervalDays 变为 7

### Scenario: 答错退一级且不低于一天

- GIVEN 某节点当前 intervalDays 为 7，其到期复练得到 blunder
- WHEN 调度器安排下一次复现
- THEN intervalDays 变为 3
- AND 当节点已处于最低一级时再次答错，intervalDays 仍为 1，不会变为 0
