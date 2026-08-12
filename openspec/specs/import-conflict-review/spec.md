# Capability: import-conflict-review

## Requirement: 采纳前展示与模型逐字段相等的标准化预览

The system SHALL present a standardized preview whose displayed values equal the parsed model, and SHALL NOT accept a hand while it has unresolved conflicts.

### Scenario: 预览值等于模型值

- GIVEN 附录 A 的解析结果
- WHEN 用户打开导入预览
- THEN 预览显示的每个座位位置、以 BB 表示的筹码、逐街行动、公共牌与结果，逐项等于模型中的对应值（例如英雄位置显示 BTN、起始筹码显示 100BB、翻牌显示 `Ac 7h 2s`）
- AND 原始文本与解析前逐字节相同

### Scenario: 存在未解决冲突时不能采纳

- GIVEN 附录 B 的解析结果（含一个未解决冲突）
- WHEN 用户尝试采纳它
- THEN 采纳被拒绝，界面指出仍未解决的冲突字段与行号
- AND 个人牌谱库中的条目数不变

### Scenario: 用户修正被标记的字段后可采纳

- GIVEN 附录 B 的解析结果（英雄翻前动作被标为冲突）
- WHEN 用户把该动作指定为"加注至 300 centi-BB"
- THEN 该冲突从冲突集合中清除，模型据此记录该动作
- AND 冲突集合清空后牌谱通过校验并可被采纳

### Scenario: 每个冲突可定位到具体字段与行号

- GIVEN 一段恰好含两个已知冲突字段的构造牌谱（附录 B 再叠加一处无法识别的金额，两处分处不同行）
- WHEN 查看冲突列表
- THEN 冲突恰为两条，分别指向那两行的行号与字段标识
- AND 一段无冲突的附录 A 在同一视图中显示零条冲突（使"冲突数目"不因恒真而失去意义）
