# Capability: initial-diagnostic

## Requirement: 跨维度初始诊断

The system SHALL offer a 12-question initial diagnostic whose blueprint declares the ability dimensions, positions, streets, and stack depths it samples, and SHALL produce a first ability profile covering every dimension the blueprint declares.

### Scenario: 完成诊断

- GIVEN 用户尚无训练历史，诊断蓝图声明的能力维度全集为 D
- WHEN 用户完成全部 12 道题
- THEN 画像中有快照的能力维度集合等于 D
- AND 这 12 道题覆盖至少 3 个不同的 heroSeatOffsetFromButton、至少 3 条不同街道、至少 2 个有效筹码档位
- AND 事件存储中恰好新增 12 条 TrainingEvent
- AND 由该画像生成的今日计划，其首项维度随画像中最弱维度改变而改变

### Scenario: 跳过诊断

- GIVEN 用户在首次启动时选择跳过诊断
- WHEN 用户直接进入今日页
- THEN 今日计划非空，且各计划项分属互不相同的能力维度（均衡先验）
- AND 用户在某维度连续三次得到 blunder 后重新生成计划时，该维度排在第一位
- AND 今日页保留诊断入口

### Scenario: 中断后恢复

- GIVEN 诊断共 12 题，用户完成前 5 题后退出 APP
- WHEN 用户再次打开 APP 并回到诊断
- THEN 进度显示 5/12
- AND 剩余题目的 scenario ID 集合与已完成的 5 个不相交，且数量为 7
- AND 再作答 7 题后诊断结束，而不是重新计数到 12
