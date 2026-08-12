# Capability: hand-history-import

## Requirement: 确定性地把受支持的 PokerStars 文本解析为统一牌谱模型

The system SHALL parse a supported PokerStars No-Limit Hold'em cash hand-history text into a unified hand model, deterministically, so the same text always yields the same model, and SHALL express every amount as integer centi-big-blinds derived from the hand's stated big blind.

### Scenario: 附录 A 解析出确定的、与输入相符的模型

- GIVEN 附录 A 的牌谱文本
- WHEN 解析它
- THEN 模型的桌型为 6，英雄座相对按钮偏移为 0（BTN），英雄底牌恰为 `[Ah, Kd]`
- AND 大盲为 100 centi-BB，英雄起始筹码为 10,000 centi-BB
- AND 英雄翻前动作为"加注至 300 centi-BB"，翻牌动作为"下注 400 centi-BB"
- AND 翻牌公共牌恰为 `[Ac, 7h, 2s]`，转牌追加 `Td`，河牌追加 `9c`
- AND 抽水为 50 centi-BB（非零——把观察到的真实牌与抽水恒为 0 的模拟牌区分开）

### Scenario: 换算是大盲的函数，而非硬编码

- GIVEN 附录 A（大盲 $1）与一段除大盲改为 $2、金额等比放大一倍外与附录 A 逐字节相同的文本
- WHEN 分别解析
- THEN 两者英雄起始筹码均为 10,000 centi-BB、大盲均为 100 centi-BB
- AND 因此"金额→centi-BB"必须按各自声明的大盲换算，硬编码常量会在其中一个上失败

### Scenario: 位置由按钮与座位顺序导出

- GIVEN 附录 A（PokerStars 文本只给"Seat #1 is the button"与盲注，不含 UTG/CO 之类位置词）
- WHEN 解析它
- THEN 六个座位的位置标签按座位顺序恰为 `[BTN, SB, BB, UTG, HJ, CO]`
- AND 每个标签由 `TablePosition(tableSize:heroSeatOffsetFromButton:)` 导出——文本中并不存在这些标签，因此拷贝无从发生，标签错误只可能来自导出错误

### Scenario: 逐街行动按发生顺序完整还原

- GIVEN 附录 A
- WHEN 解析它
- THEN 盲注（SB/BB）作为强制下注单列，不计入下述"自主行动"；翻前恰有 6 个自主行动，顺序为 `[UTG 弃, HJ 弃, CO 弃, BTN 加注至 300, SB 弃, BB 跟注]`
- AND 河牌恰有 3 个自主行动 `[BB 过牌, BTN 下注 800, BB 弃牌]`
- AND 全手自主行动总数为 14（翻前 6 + 翻牌 3 + 转牌 2 + 河牌 3），非空

### Scenario: 跨进程规范序列化逐字节一致，并等于黄金夹具

- GIVEN 附录 A
- WHEN 在两个独立进程中各解析并规范序列化一次
- THEN 两次输出逐字节相同
- AND 两次输出逐字节等于随包提交的黄金夹具 `Tests/Fixtures/sample-ps-6max-nlhe.model.json`

## Requirement: 无法无歧义解析的输入被登记为冲突而不是猜测

The system SHALL reject text outside the supported class with an explicit, locatable reason, and SHALL never invent a value for a field it cannot read unambiguously; each such field is registered as a conflict carrying its field identifier and source line, rather than defaulted.

### Scenario: 附录 C（锦标赛）被明确判为不受支持

- GIVEN 附录 C 的锦标赛牌谱文本
- WHEN 尝试解析
- THEN 结果为"不受支持"，并指出触发该判定的原文行号
- AND 不产生任何部分猜测出来的模型

### Scenario: 附录 B 恰好在被改动的那一行报出一个冲突

- GIVEN 附录 B（附录 A 仅将英雄翻前动作动词改为无法识别的记号）
- WHEN 解析它
- THEN 冲突集合恰为一条，其 `sourceLine` 指向被改动的那一行
- AND 该行动不被赋予任何被猜测的值

### Scenario: 附录 A（清晰输入）不产生任何冲突

- GIVEN 附录 A
- WHEN 解析它
- THEN 冲突集合为空
- AND 因附录 A 与附录 B 仅在一行上不同，本场景与上一场景成对：任何"恒报冲突""恒不报冲突"或以无关代理键（如是否含某子串）判定的实现，都无法同时通过两者

### Scenario: 摊牌显示的底牌被读出，未显示的底牌记为未知

- GIVEN 附录 A（英雄底牌 `Ah Kd` 明示；对手底牌未摊）
- WHEN 解析它
- THEN 英雄底牌恰为 `[Ah, Kd]`（"恒为未知"的实现在此失败）
- AND 未摊牌对手的底牌记为"未知"，不被推断（"照抄英雄两张牌"之类的实现在此失败）

### Scenario: 金额不能被大盲整除时报冲突而非四舍五入

- GIVEN 附录 D 中一处在其大盲下无法整除为整数 centi-BB 的金额
- WHEN 解析它
- THEN 该金额字段被登记为冲突，指向其原文行号
- AND 模型不产生任何被四舍五入的 centi-BB 值
