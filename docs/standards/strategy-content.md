# 策略内容规范

## 必需元数据

每个策略包必须包含：

- pack ID、schema version、content version。
- review status 和 generated source。
- `reviewed` 内容另需 reviewed by 与 reviewed time；两者缺一即拒绝加载。
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

构建分为三个频道，由产物 Info.plist 中的 `PCContentChannel` 标记，
由 `scripts/check-release-content.sh` 从产物本身读取并判定。

| 状态 | 用途 | Debug | dogfooding | 商店发布 |
|---|---|---|---|---|
| `testFixture` | 单元、UI 和演示数据 | 是 | 否 | 否 |
| `unverifiedDraft` | 内部自洽但未经人工策略审核的内容 | 是 | 是 | 否 |
| `reviewed` | 经来源和扑克策略审核的内容 | 是 | 是 | 是 |
| `retired` | 历史保留，不用于新训练 | 否 | 否 | 否 |

`unverifiedDraft` 存在的理由：生成的内容可以做到行动合法、频率总和 10,000、
EV 序关系合理，但没有任何求解验证。把它标成 `reviewed` 等于断言一次没人做过的审核。

## 版本规则

- 已发布 pack 不可原地修改。
- 新内容使用新 content version。
- TrainingEvent 固定记录原 pack ID 和 content version。
- 策略升级必须运行黄金数据回归并记录超出容差的变化。

## 展示规则

- `testFixture` 内容始终展示“开发演示数据”。
- `unverifiedDraft` 内容始终展示“未经策略审核”，且该文案与上一条不同。
- 历史条目的来源无法确认时展示“内容来源未知”，不得留空。
- 用户可查看关键求解假设和内容版本。
- 生成式教练文本不得添加结构化数据中不存在的数字或结论。

