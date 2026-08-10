# Capability: local-learning-profile

## Requirement: 不可变本地训练事件

The system SHALL persist each completed decision as an immutable, append-only event that includes event ID, local user ID, device ID, occurrence time, scenario ID, strategy pack ID, content version, ability dimension, submission, and grade.

### Scenario: 首次追加

- GIVEN 本地事件存储为空
- WHEN APP 追加一个 TrainingEvent
- THEN 事件可按时间顺序读取
- AND 所有同步所需标识与评分字段均保留

### Scenario: 重复事件

- GIVEN 存储中已经存在相同 event ID
- WHEN APP 再次追加该事件
- THEN 存储内容不重复
- AND 读取结果仍只有一条该事件

### Scenario: 损坏事件文件

- GIVEN JSON Lines 文件的某一行无法解码
- WHEN store 初始化或读取
- THEN 返回包含行号的 typed corruption error
- AND 日志不输出完整事件正文

## Requirement: 能力画像归约

The system SHALL derive each ability dimension from its immutable training events.

### Scenario: 高信心错误

- GIVEN very-sure 决策被评为 improvable 或 blunder
- WHEN reducer 生成能力画像
- THEN 对应维度 high-confidence-error-count 增加
- AND 其他能力维度不受影响

## Requirement: 今日训练优先级

The system SHALL rank training catalog items using weakness, high-confidence errors, days since practice, repetition due date, and the active learning path, resolving conflicts in that stated order.

### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

### Scenario: 到期复练排在未到期项目之前

- GIVEN A 与 B 的 meanScore、highConfidenceErrorCount、lastPracticedAt 完全相同
- AND A 的 nextDueAt 为昨天、B 的 nextDueAt 为三天后，且 A 的 catalog ID 字典序排在 B 之后
- WHEN planner 生成今日项目
- THEN A 排在 B 之前
- AND A 的 priority 严格大于 B 的 priority

### Scenario: 高信心错误压过复练到期

- GIVEN A 有高信心错误但复练未到期，B 无高信心错误但复练已到期，其余输入相同
- WHEN planner 生成今日项目
- THEN A 排在 B 之前

### Scenario: 每个计划项给出被选中的原因

- GIVEN 四个画像，分别只具备低分、只具备高信心错误、只具备到期复练、只具备学习路径推进
- WHEN 分别生成今日计划
- THEN 四个计划的首项入选原因依次为 `.weakness`、`.highConfidenceError`、`.repetitionDue`、`.pathProgress`
- AND 该原因在相同输入下保持稳定

### Scenario: 计划受可用时长约束

- GIVEN 今日计划目标时长为 5 到 10 分钟，候选项充足且每项预计时长已知
- WHEN planner 生成计划
- THEN 计划项预计时长之和不超过 10 分钟且不少于 5 分钟
- AND 再加入任意一个未入选候选项都会超过 10 分钟

## Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the active profile's local event store after a completed or synchronized decision.

### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 重新生成的今日计划首项维度为 bet-sizing

## Requirement: 跨设备历史确定性归约

The system SHALL derive the active user's ability profile from the deduplicated union of locally created and synchronized TrainingEvents.

### Scenario: 远端事件进入画像

- GIVEN 同一账号的另一设备完成训练并同步
- WHEN 当前设备拉取并合并该事件
- THEN Today 与 Review 的样本和能力画像包含该事件
- AND 相同 event ID 的重复拉取不改变结果

### Scenario: 两台设备独立归约得到相同画像

- GIVEN 两台设备各自持有相同的去重事件集合，但本地写入顺序不同
- WHEN 各自独立归约
- THEN 两台设备得到逐字段相等的画像
- AND 该画像等于预期快照：bet-sizing 的 sampleCount 为 5、meanScore 为 62、highConfidenceErrorCount 为 2

## Requirement: 能力树节点掌握信号

The system SHALL expose, for every curriculum node, each of the five mastery signals with its satisfied state and its current numeric value.

### Scenario: 查看未掌握原因

- GIVEN 节点 `turn-barrel` 有 4 次作答，最近 10 次中 3 次达标，无 verySure 作答，已完成 0 次复练，迁移未开始
- WHEN 用户查看该节点
- THEN 界面逐行列出五项信号：样本 4/20 未满足、近期稳定性 3/10 未满足、信心校准 满足、复练 0/2 未满足、迁移 0/3 未满足
- AND 不显示笼统的未掌握结论
