# 策略内容规范

## 必需元数据

每个策略包必须包含：

- pack ID、schema version、content version。
- review status、generated source 和 reviewed time。
- 游戏类型、桌型、有效筹码。
- 盲注、Ante、Rake 和允许下注尺度。
- 场景历史、双方范围和求解假设。

## 决策节点规则

- 所有行动必须由 `BettingDecisionContext` 判定为合法。
- 行动不得重复。
- 频率总和必须严格等于 10,000 basis points。
- 每个行动保留原始 EV。
- 多个接近 EV 的行动保持可接受，不强制唯一答案。
- 剥削建议必须包含对手假设和适用条件。

## 审核状态

| 状态 | 用途 | Release 可用 |
|---|---|---|
| `testFixture` | 单元、UI 和演示数据 | 否 |
| `reviewed` | 经来源和扑克策略审核的内容 | 是 |
| `retired` | 历史保留，不用于新训练 | 否 |

## 版本规则

- 已发布 pack 不可原地修改。
- 新内容使用新 content version。
- TrainingEvent 固定记录原 pack ID 和 content version。
- 策略升级必须运行黄金数据回归并记录超出容差的变化。

## 展示规则

- Debug fixture 始终展示“开发演示数据”。
- 用户可查看关键求解假设和内容版本。
- 生成式教练文本不得添加结构化数据中不存在的数字或结论。

