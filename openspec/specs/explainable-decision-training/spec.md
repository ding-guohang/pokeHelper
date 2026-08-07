# Capability: explainable-decision-training

## Requirement: 行动与信心共同提交

The system SHALL require both a legal action and one of guessing、unsure、very-sure confidence values before grading.

### Scenario: 提交信息不完整

- GIVEN 用户未选择行动或信心
- WHEN 用户尝试提交
- THEN 系统不创建 TrainingEvent
- AND 显示中文提示“请选择行动和信心程度”

### Scenario: 合法提交

- GIVEN 用户选择策略节点中的合法行动和信心
- WHEN 提交成功
- THEN 系统只执行一次确定性评分
- AND 在展示反馈前持久化一条 TrainingEvent

## Requirement: 可解释 EV 评分

The system SHALL grade a selected action using its raw EV loss relative to the best listed action and the decision pot size.

### Scenario: 最高 EV 行动

- GIVEN 用户选择最高 EV 行动
- WHEN 系统评分
- THEN EV loss 为 0 milliBB
- AND score 为 100
- AND quality 为 excellent

### Scenario: 接近 EV 的混合行动

- GIVEN 用户选择频率大于零且只损失 20 milliBB 的第二行动
- WHEN 系统评分
- THEN 系统保留该行动的原始频率和 EV
- AND quality 为 acceptable
- AND 不把它描述为错误答案

### Scenario: 策略节点外行动

- GIVEN 用户提交的行动不在该节点的策略选项中
- WHEN 系统评分
- THEN 评分失败并返回 `actionNotInStrategy`
- AND 不生成伪造频率或 EV

## Requirement: 评分与结果无关

The system SHALL produce a decision grade without consuming later runout, pot result, or winnings.

### Scenario: 相同决策不同后续结果

- GIVEN 两次训练具有相同场景、行动和策略版本，但模拟后续结果不同
- WHEN 系统生成 DecisionGrade
- THEN 两次 grade 完全相同

## Requirement: 专业反馈层级

The system SHALL show quality, raw EV loss, confidence calibration, all action frequencies, range information, structured reasoning, solver assumptions, source, version, and review status.

### Scenario: iPhone 专业反馈

- GIVEN 用户在 iPhone 完成决策
- WHEN 反馈页面出现
- THEN 信息以单列可滚动层级显示
- AND 所有可用行动及其频率仍可查看

### Scenario: iPad 专业反馈

- GIVEN 用户在 iPad 完成决策
- WHEN 反馈页面出现
- THEN 牌桌列与分析列同时可见
- AND 两列使用同一个 DecisionGrade

### Scenario: 剥削条件缺失

- GIVEN 结构化内容没有 exploit condition
- WHEN 系统展示反馈
- THEN 不展示无依据的剥削建议
