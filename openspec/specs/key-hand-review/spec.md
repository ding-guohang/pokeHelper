# Capability: key-hand-review

## Requirement: 挑出值得复盘的手牌

The system SHALL select between three and five key hands from a finished session using pot size, all-in occurrence, stack swing and content match, and SHALL state which of these caused each hand to be selected.

### Scenario: 完成 Session 后给出关键手

- GIVEN 一局已完成的 30 手 Session
- WHEN 打开复盘
- THEN 列出 3 到 5 手关键手
- AND 在 300 个种子的真实 Session 上，`.deviation`、`.allIn`、`.bigPot` 三种原因都至少作为展示原因出现过一次
- AND 标记 `.deviation` 的手，其翻前局面被已安装内容覆盖，且英雄的行动在该范围表对其手牌类别的权重低于 5000 基点
- AND 标记 `.bigPot` 的手，其底池必须是该 Session 底池最大的 5 手之一
- AND 标记 `.bigSwing` 的手，其英雄筹码变化绝对值不小于 20BB

### Scenario: 全部小底池的 Session

- GIVEN 一局 15 手 Session，每手底池均不超过 3BB，第 4 手 3.0BB 为全局最大、第 9 手 2.9BB 次之
- WHEN 打开复盘
- THEN 列表非空，按选择分数降序排列
- AND 首项为第 4 手

### Scenario: 偏离内容范围的手排在纯粹大底池之前

- GIVEN 一局 Session 中，第 3 手英雄在被内容覆盖的局面上做出了范围表权重为 0 的行动，第 8 手是全局最大底池但英雄的行动与范围表一致
- WHEN 打开复盘
- THEN 第 3 手排在第 8 手之前
- AND 第 3 手的原因为 `.deviation`，第 8 手不是

### Scenario: 内容未覆盖的手不会被标为偏离

- GIVEN 一手的翻前局面在已安装内容里没有覆盖
- WHEN 选关键手
- THEN 该手的原因不可能是 `.deviation`
- AND 它仍可因底池、全下或波动入选

### Scenario: 关键手不是「取前五手」

- GIVEN 两局同种子 Session，第二局把第 11 至 15 手的底池放大
- WHEN 分别打开复盘
- THEN 两次选出的手牌编号集合不同
- AND 第二次选出的手牌至少包含第 11 至 15 手中的两手

### Scenario: 关键手可逐街回放

- GIVEN 一手打到河牌的关键手
- WHEN 用户逐街翻看
- THEN 四个街道分别显示 0、3、4、5 张公共牌
- AND 每个街道显示的底池等于该街道结束时的底池，四个数值不全相同
- AND 每个街道显示的行动只包含该街道发生的行动

## Requirement: 命中内容的关键手可对照与重打

The system SHALL show, for a key hand whose preflop spot matches installed content, the user's action beside the content's frequencies, and SHALL let the user replay that spot through the normal training pipeline.

### Scenario: 对照展示

- GIVEN 一手关键手的翻前局面与某已安装场景等同
- WHEN 用户打开该手
- THEN 显示用户当时的行动与该场景各行动的频率和 EV
- AND 明确标注这是对照，不是评分
- AND 不显示 EV 损失或质量等级

### Scenario: 重打产生正常训练事件

- GIVEN 一手可对照的关键手
- WHEN 用户选择「以训练模式重打」，提交行动与信心
- THEN 产生一条 TrainingEvent，其 scenarioID 为该已安装场景
- AND 该事件带有用户提交的信心值
- AND 该事件在展示反馈前已持久化
- AND 能力画像的对应维度样本量加一

### Scenario: 未命中内容的关键手不提供重打

- GIVEN 一手关键手在已安装内容里没有等同场景
- WHEN 用户打开该手
- THEN 可以逐街回放
- AND 不显示对照，也不显示「重打」入口
