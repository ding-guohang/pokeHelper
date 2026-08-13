# Capability: training-progress-trend

## Requirement: 按日聚合训练进度

The system SHALL aggregate the user's own training events into per-day progress (hands practiced, score total, blunder count) grouped by calendar day and ordered ascending by day, computing mean score by integer division, introducing no strategy content and producing no new event.

### Scenario: 多日事件按日聚合且均值精确

- GIVEN 三个训练事件：第 1 天两个（得分 `80`、`60`，其中一个质量为 `blunder`）、第 2 天一个（得分 `100`，非 blunder）
- WHEN 用 `ProgressTrend.daily(events:calendar:)` 聚合
- THEN 得两个 `DailyProgress`，按日升序：第 1 天 `sampleCount=2`、`scoreTotal=140`、`blunderCount=1`、`meanScore=70`；第 2 天 `sampleCount=1`、`scoreTotal=100`、`blunderCount=0`、`meanScore=100`
- AND 同一天的多个事件归入同一桶（不因时刻不同而拆分）

### Scenario: 无事件给空结果

- GIVEN 空事件列表
- WHEN 聚合
- THEN 返回空数组（视图侧显示空态，不显示任何数字）

## Requirement: 复盘下可达的进度趋势视图

The system SHALL make the progress trend reachable from within 复盘, showing per-day rows and an overall summary, or an empty state when there are no events, without altering the four core tabs.

### Scenario: 复盘下打开进度趋势

- GIVEN 复盘标签
- WHEN 打开「训练进度」（`review.progressTrend`）
- THEN 显示每日进度行（或空态）；页面经复盘标签（iPhone）或侧栏（iPad）可达
- AND 四个核心标签不变（`AdaptiveNavigationTests` 仍断言 `[今日,学习,训练,复盘]`）

### Scenario: ViewModel 聚合注入的事件（可测）

- GIVEN 注入一个返回上面三事件的事件存储
- WHEN `ProgressTrendViewModel.load()`
- THEN 有两日行；总览为「共 3 手 · 2 天 · 总平均 80 分」（`240/3` 整除）
- AND 注入空存储时只显示空态、无日行
