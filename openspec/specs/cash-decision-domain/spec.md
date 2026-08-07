# Capability: cash-decision-domain

## Requirement: 精确扑克值

The system SHALL represent pot and stack amounts as integer centi-big-blinds, EV as integer milli-big-blinds, and strategy frequencies as integer basis points.

### Scenario: 精确金额运算

- GIVEN 两个可相加的 centi-BB 金额和两个可相减的 milli-BB EV
- WHEN 领域层执行运算
- THEN 结果使用整数精确计算
- AND 领域真值不依赖浮点数比较

## Requirement: 稳定牌面表示

The system SHALL parse and serialize a card using a stable two-character rank/suit code.

### Scenario: 合法牌往返

- GIVEN 输入 `As`
- WHEN 系统解析后重新序列化
- THEN 结果仍为 `As`
- AND 点数为 Ace、花色为 Spades

### Scenario: 非法牌拒绝

- GIVEN 输入 `1x`
- WHEN 系统尝试解析
- THEN 解析失败
- AND 不产生部分 Card 值

## Requirement: 合法行动过滤

The system SHALL derive the available fold, check, call, bet, raise, and all-in actions from a stored betting decision context.

### Scenario: 未面对下注

- GIVEN amount-to-call 为零，配置了两个低于有效筹码的下注尺度
- WHEN 系统计算合法行动
- THEN 包含 check、两个 bet 和 all-in
- AND 不包含 fold、call 或 raise

### Scenario: 面对下注

- GIVEN amount-to-call 大于零并存在 minimum-raise-to
- WHEN 系统计算合法行动
- THEN 包含 fold、call、达到最小加注要求的 raise 和 all-in
- AND 低于 minimum-raise-to 的配置尺度被排除

## Requirement: 稳定行动 JSON

The system SHALL encode decision actions with an explicit action kind and unit-bearing target amount.

### Scenario: 带金额行动

- GIVEN 行动是 bet 到 2.17BB
- WHEN 系统编码 JSON
- THEN JSON kind 为 `bet`
- AND `toCentiBB` 为 `217`

### Scenario: 行动字段不匹配

- GIVEN fold/check 包含金额或 bet/raise 缺少金额
- WHEN 系统解码
- THEN 解码失败并返回 typed error
