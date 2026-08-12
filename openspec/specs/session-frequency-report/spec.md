# Capability: session-frequency-report

## Requirement: 按位置累计翻前频率并与内容基准对照

The system SHALL accumulate the user's realized preflop action frequencies per (position, facing action) pair across all recorded sessions, SHALL derive each baseline from the installed content's range chart for that same pair rather than from stored constants, and SHALL withhold any comparison verdict for a pair whose opportunity count is below 30.

### Scenario: 样本不足时只报计数，不下结论

- GIVEN 用户在 BTN 位置累计有 8 次开池机会，阈值为 30
- WHEN 打开频率报告
- THEN 显示「BTN 8 次机会」与实际开池次数
- AND 不显示与基准的差值
- AND 显示「样本不足，暂不比较」
- AND 该位置不出现在漏洞列表里

### Scenario: 样本足够时给出与基准的对照

- GIVEN 用户在 BTN 位置累计有 60 次开池机会，其中开池 42 次
- AND 已安装内容的 BTN 开池基准为 41.22%
- WHEN 打开频率报告
- THEN 显示实际 70.00%、基准 41.22%、差值 +28.78 个百分点
- AND 该位置出现在漏洞列表里，标注为偏松

### Scenario: 差距在容差内不算漏洞

- GIVEN 某位置累计 60 次机会，实际频率与基准相差 3.00 个百分点
- WHEN 打开频率报告
- THEN 显示实际值、基准值与差值
- AND 该位置不出现在漏洞列表里
- AND 同样 60 次机会、相差 6.00 个百分点的位置出现在漏洞列表里
- AND 这两个数值直接出现在测试里，容差因此被夹在 3.00 与 6.00 之间

### Scenario: 基准由内容算出，不是写死的数字

- GIVEN 两个已安装内容版本，其 BTN 范围表的组合权重不同
- WHEN 分别打开频率报告
- THEN 两次显示的基准值不同
- AND 每次的基准值等于该版本 BTN 未面对下注范围表中的非弃牌组合数除以 1326

### Scenario: 同一位置的不同面对情形各有各的基准

- GIVEN 已安装内容在 CO 位置同时有未面对下注与面对 3bet 两个场景
- WHEN 计算 CO 的基准
- THEN 未面对下注的基准为 24.86%，面对 3bet 的基准为 9.05%
- AND 两者不被合并成一个 CO 基准
- AND 英雄在 CO 面对 3bet 的手牌只计入面对 3bet 的机会数

### Scenario: 内容未覆盖的位置不显示基准

- GIVEN 已安装内容没有 BB 位置的场景
- WHEN 打开频率报告
- THEN 显示 BB 的实际次数与频率
- AND BB 行不显示基准值或差值
- AND BB 不出现在漏洞列表里

### Scenario: 无内容时不编造基准

- GIVEN 未安装任何内容
- WHEN 打开频率报告
- THEN 仍显示各位置的实际次数与频率
- AND 不显示任何基准值或差值
- AND 不出现漏洞列表

### Scenario: 跨 Session 累计而不是单局

- GIVEN 三局各 15 手的已完成 Session
- WHEN 打开频率报告
- THEN 各位置的机会数等于三局之和
- AND 删除其中一局后，机会数相应减少

## Requirement: 频率来自记录的手牌

The system SHALL compute every reported frequency from recorded session hands, never from an estimate or a running counter that can drift from the hands on disk.

### Scenario: 报告可由记录重算

- GIVEN 一份任意的 Session 记录集合
- WHEN 计算频率报告两次，第二次在重新读取记录之后
- THEN 两次结果逐字段相等

### Scenario: 未到该位置行动的手牌不计入机会数

- GIVEN 一手牌在英雄行动前已经结束
- WHEN 计算频率报告
- THEN 该手不计入英雄所在位置的机会数
- AND 也不计入开池次数
