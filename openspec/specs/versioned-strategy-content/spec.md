# Capability: versioned-strategy-content

## Requirement: 策略包来源可追溯

The system SHALL load strategy packs that identify schema version, content version, review status, generated source, game assumptions, and decision scenarios.

### Scenario: 合法策略包加载

- GIVEN 策略包 schema version 为 1、来源非空且场景完整
- WHEN loader 完成 checksum、解码和语义校验
- THEN 返回不可变 StrategyPack
- AND manifest 与场景中的求解假设可供反馈界面读取
- AND 场景使用 tableSize 与 heroSeatOffsetFromButton 表示可验证的 2–9 人桌位置

### Scenario: checksum 不匹配

- GIVEN 下载内容的 SHA-256 与期望值不同
- WHEN loader 加载策略包
- THEN 在解码前拒绝内容
- AND 返回 checksum-specific typed error

## Requirement: 决策节点语义校验

The system SHALL reject a strategy decision node that violates card uniqueness, legal-action, action uniqueness, or frequency-total rules.

### Scenario: 频率总和错误

- GIVEN 一个场景的行动频率总和不是 10,000 basis points
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 错误包含场景 ID 和实际频率总和

### Scenario: 非法行动进入策略

- GIVEN 策略选项包含 BettingDecisionContext 未提供的行动
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 该内容不能进入训练流程

## Requirement: 审核状态约束

The system SHALL distinguish `testFixture`, `reviewed`, and `retired` strategy content.

### Scenario: 已审核内容缺少审核时间

- GIVEN review status 为 `reviewed` 且 reviewed-at 为空
- WHEN validator 校验
- THEN 策略包被拒绝

### Scenario: 开发内容展示

- GIVEN APP 使用 `testFixture` 内容
- WHEN 用户查看训练或反馈
- THEN 界面明确显示“开发演示数据”
- AND 不把数据描述为已审核扑克建议
