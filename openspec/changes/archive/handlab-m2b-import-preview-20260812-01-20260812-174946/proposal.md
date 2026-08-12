---
name: handlab-m2b-import-preview-20260812-01
created: 2026-08-12
status: review_passed
---

# 需求提案：M2B 个人牌局实验室（第一切片：牌谱导入与冲突预览）

## Why

产品最高宗旨是把用户训练成更好的职业牌手，而职业提升的核心素材是**用户自己打过的真实牌**。M1/M2A 都基于随包内容与模拟牌局，用户无法把线上打过的手带进来复盘。M2B 的整体目标是"个人牌局实验室"，但它包含解析、冲突预览、场景构建、分支重放、补救训练五块，比 M2A 还大。本切片只做整条流水线的**前半段**：把一段 PokerStars 文本牌谱可靠地变成一份可信的、标准化的牌谱，并在采纳前让用户核对。没有这份可信的标准化牌谱，后续所有分析都建立在猜测之上。

设计流水线（`docs/superpowers/specs/…texas-holdem-coach-design.md` §9）：

> 原始文本 → 格式识别 → 标准牌谱 → 冲突预览 →〔关键节点 → 策略分析 → 漏洞标签 → 后续训练〕

本切片交付到"冲突预览"为止；方括号内推后到后续切片。

## 术语（这些词此前未定义，审需时被指出不可测）

- **统一牌谱模型**：一份被观察到的真实牌的标准化表示。座位、位置、逐街行动、公共牌、结果、抽水均为纯扑克事实；金额一律整数 centi-BB。它与 `SessionSimulation` 的 `PlayedHand` 是两类数据（后者定长 6 人、英雄固定 0 号座、无未知底牌、抽水恒为 0、不带原始文本），本切片独立定义，不复用。
- **规范序列化**：统一牌谱模型的确定性编码——JSON、键按字典序、不转义斜杠。它是"逐字节一致"与黄金夹具比对的对象。凡说"逐字节"均指这份规范序列化的字节，而不是原始文本。
- **冲突（Conflict）**：解析器无法**无歧义**读出某字段时，对该字段登记的一条冲突。每条冲突带 `field`（字段标识）与 `sourceLine`（1 起的原文行号）。"无歧义"的判定标准：该字段在受支持语法下有且仅有一种读法。
- **字段位置**：`sourceLine` = 原始文本中的行号（PokerStars 牌谱以行为单位）。
- **牌谱身份**：一段导入的身份等于其原始文本经行尾规范化后的 SHA-256。两段身份相同即"同一手"。
- **版本**：同一牌谱身份下单调递增的整数，从 1 起。再次采纳同一身份产生新版本，旧版本保留。
- **受支持牌谱**：PokerStars 客户端导出的 No-Limit Hold'em **现金**牌谱，桌型 2–9 人。锦标赛、非 NLHE 变体、其他客户端均不受支持。

## 附录：冻结的样例（scenario 绑定这些具体输入，不再用"一段真实牌谱"这类无法落测的措辞）

- **附录 A（`sample-ps-6max-nlhe.txt`）**：一段完整的 6-max NLHE 现金牌谱，$0.50/$1，按钮在 1 号座（英雄），英雄底牌 `Ah Kd`，打到河牌英雄下注被弃。字段完整、无歧义——**清晰输入**基准。
- **附录 B（`sample-ps-6max-nlhe-unknown-action.txt`）**：附录 A **仅将**英雄翻前那一行的动作动词改为无法识别的记号（其余逐字节相同）——**单字段冲突**基准。
- **附录 C（`sample-ps-tournament.txt`）**：一段 PokerStars **锦标赛**牌谱——**不受支持**基准。
- **附录 D（`sample-ps-6max-rake-fraction.txt`）**：一段盲注为 $0.02/$0.05、抽水 $0.01 的现金牌谱——$0.01 在该 BB 下换算为 20 centi-BB 整除、但另设一处 $0.01 边注在 $0.03 BB 下不整除，用于**非整除必须报冲突**基准。

样例文本随本切片一并提交到解析包的 `Tests/Fixtures/`，其规范序列化的黄金夹具在实现稳定后提交。

## What Changes

### New Capabilities

- `hand-history-import` — 把受支持的 PokerStars NLHE 现金文本牌谱确定性地解析为统一牌谱模型；不受支持的格式与无法无歧义解析的字段被明确登记为冲突，而不是被猜测填补。
- `import-conflict-review` — 采纳前展示与模型逐字段相等的标准化预览；存在未解决冲突时不可采纳，用户逐字段修正后方可采纳；原始文本始终保留。
- `personal-hand-library` — 采纳后的标准化牌谱作为版本化的个人资源本地保存，可查看与删除，重复采纳不静默覆盖，且导入路径持有训练事件存储却不产生任何 `TrainingEvent`。

### Modified Capabilities

无。本切片不改动任何现有能力的语义；统一牌谱模型复用 PokerCore 的 `Card` / `BBAmount` / `TablePosition`，但不改变它们。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: hand-history-import

#### Requirement: 确定性地把受支持的 PokerStars 文本解析为统一牌谱模型

The system SHALL parse a supported PokerStars No-Limit Hold'em cash hand-history text into a unified hand model, deterministically, so the same text always yields the same model, and SHALL express every amount as integer centi-big-blinds derived from the hand's stated big blind.

##### Scenario: 附录 A 解析出确定的、与输入相符的模型

- GIVEN 附录 A 的牌谱文本
- WHEN 解析它
- THEN 模型的桌型为 6，英雄座相对按钮偏移为 0（BTN），英雄底牌恰为 `[Ah, Kd]`
- AND 大盲为 100 centi-BB，英雄起始筹码为 10,000 centi-BB
- AND 英雄翻前动作为"加注至 300 centi-BB"，翻牌动作为"下注 400 centi-BB"
- AND 翻牌公共牌恰为 `[Ac, 7h, 2s]`，转牌追加 `Td`，河牌追加 `9c`
- AND 抽水为 50 centi-BB（非零——把观察到的真实牌与抽水恒为 0 的模拟牌区分开）

##### Scenario: 换算是大盲的函数，而非硬编码

- GIVEN 附录 A（大盲 $1）与一段除大盲改为 $2、金额等比放大一倍外与附录 A 逐字节相同的文本
- WHEN 分别解析
- THEN 两者英雄起始筹码均为 10,000 centi-BB、大盲均为 100 centi-BB
- AND 因此"金额→centi-BB"必须按各自声明的大盲换算，硬编码常量会在其中一个上失败

##### Scenario: 位置由按钮与座位顺序导出

- GIVEN 附录 A（PokerStars 文本只给"Seat #1 is the button"与盲注，不含 UTG/CO 之类位置词）
- WHEN 解析它
- THEN 六个座位的位置标签按座位顺序恰为 `[BTN, SB, BB, UTG, HJ, CO]`
- AND 每个标签由 `TablePosition(tableSize:heroSeatOffsetFromButton:)` 导出——文本中并不存在这些标签，因此拷贝无从发生，标签错误只可能来自导出错误

##### Scenario: 逐街行动按发生顺序完整还原

- GIVEN 附录 A
- WHEN 解析它
- THEN 盲注（SB/BB）作为强制下注单列，不计入下述"自主行动"；翻前恰有 6 个自主行动，顺序为 `[UTG 弃, HJ 弃, CO 弃, BTN 加注至 300, SB 弃, BB 跟注]`
- AND 河牌恰有 3 个自主行动 `[BB 过牌, BTN 下注 800, BB 弃牌]`
- AND 全手自主行动总数为 14（翻前 6 + 翻牌 3 + 转牌 2 + 河牌 3），非空

##### Scenario: 跨进程规范序列化逐字节一致，并等于黄金夹具

- GIVEN 附录 A
- WHEN 在两个独立进程中各解析并规范序列化一次
- THEN 两次输出逐字节相同
- AND 两次输出逐字节等于随包提交的黄金夹具 `Tests/Fixtures/sample-ps-6max-nlhe.model.json`

#### Requirement: 无法无歧义解析的输入被登记为冲突而不是猜测

The system SHALL reject text outside the supported class with an explicit, locatable reason, and SHALL never invent a value for a field it cannot read unambiguously; each such field is registered as a conflict carrying its field identifier and source line, rather than defaulted.

##### Scenario: 附录 C（锦标赛）被明确判为不受支持

- GIVEN 附录 C 的锦标赛牌谱文本
- WHEN 尝试解析
- THEN 结果为"不受支持"，并指出触发该判定的原文行号
- AND 不产生任何部分猜测出来的模型

##### Scenario: 附录 B 恰好在被改动的那一行报出一个冲突

- GIVEN 附录 B（附录 A 仅将英雄翻前动作动词改为无法识别的记号）
- WHEN 解析它
- THEN 冲突集合恰为一条，其 `sourceLine` 指向被改动的那一行
- AND 该行动不被赋予任何被猜测的值

##### Scenario: 附录 A（清晰输入）不产生任何冲突

- GIVEN 附录 A
- WHEN 解析它
- THEN 冲突集合为空
- AND 因附录 A 与附录 B 仅在一行上不同，本场景与上一场景成对：任何"恒报冲突""恒不报冲突"或以无关代理键（如是否含某子串）判定的实现，都无法同时通过两者

##### Scenario: 摊牌显示的底牌被读出，未显示的底牌记为未知

- GIVEN 附录 A（英雄底牌 `Ah Kd` 明示；对手底牌未摊）
- WHEN 解析它
- THEN 英雄底牌恰为 `[Ah, Kd]`（"恒为未知"的实现在此失败）
- AND 未摊牌对手的底牌记为"未知"，不被推断（"照抄英雄两张牌"之类的实现在此失败）

##### Scenario: 金额不能被大盲整除时报冲突而非四舍五入

- GIVEN 附录 D 中一处在其大盲下无法整除为整数 centi-BB 的金额
- WHEN 解析它
- THEN 该金额字段被登记为冲突，指向其原文行号
- AND 模型不产生任何被四舍五入的 centi-BB 值

### Capability: import-conflict-review

#### Requirement: 采纳前展示与模型逐字段相等的标准化预览

The system SHALL present a standardized preview whose displayed values equal the parsed model, and SHALL NOT accept a hand while it has unresolved conflicts.

##### Scenario: 预览值等于模型值

- GIVEN 附录 A 的解析结果
- WHEN 用户打开导入预览
- THEN 预览显示的每个座位位置、以 BB 表示的筹码、逐街行动、公共牌与结果，逐项等于模型中的对应值（例如英雄位置显示 BTN、起始筹码显示 100BB、翻牌显示 `Ac 7h 2s`）
- AND 原始文本与解析前逐字节相同

##### Scenario: 存在未解决冲突时不能采纳

- GIVEN 附录 B 的解析结果（含一个未解决冲突）
- WHEN 用户尝试采纳它
- THEN 采纳被拒绝，界面指出仍未解决的冲突字段与行号
- AND 个人牌谱库中的条目数不变

##### Scenario: 用户修正被标记的字段后可采纳

- GIVEN 附录 B 的解析结果（英雄翻前动作被标为冲突）
- WHEN 用户把该动作指定为"加注至 300 centi-BB"
- THEN 该冲突从冲突集合中清除，模型据此记录该动作
- AND 冲突集合清空后牌谱通过校验并可被采纳

##### Scenario: 每个冲突可定位到具体字段与行号

- GIVEN 一段恰好含两个已知冲突字段的构造牌谱（附录 B 再叠加一处无法识别的金额，两处分处不同行）
- WHEN 查看冲突列表
- THEN 冲突恰为两条，分别指向那两行的行号与字段标识
- AND 一段无冲突的附录 A 在同一视图中显示零条冲突（使"冲突数目"不因恒真而失去意义）

### Capability: personal-hand-library

#### Requirement: 采纳的牌谱作为版本化个人资源本地保存

The system SHALL store an accepted hand as a versioned personal resource on the device, retaining its raw source alongside the standardized model, and SHALL allow viewing and deletion without affecting other stored hands.

##### Scenario: 采纳后可取回与所采纳者相等的牌谱

- GIVEN 用户采纳了附录 A
- WHEN 从库中取回该牌谱
- THEN 取回的标准化模型与采纳时的模型逐字段相等，原始文本与附录 A 逐字节相同
- AND 其牌谱身份等于附录 A 原文的规范化 SHA-256

##### Scenario: 再次采纳同一手保留旧版本、不静默覆盖

- GIVEN 用户已采纳附录 A（版本 1）
- WHEN 用户再次采纳身份相同的附录 A
- THEN 库中该身份下存在两个版本，版本号为 1 与 2
- AND 版本 1 的规范序列化与首次采纳时逐字节相同（未被覆盖）

##### Scenario: 删除一手不影响其余

- GIVEN 库中已采纳附录 A 与另一段身份不同的牌谱，共两条
- WHEN 用户删除附录 A
- THEN 库中剩余恰为那另一段牌谱，其内容不受影响
- AND 附录 A 及其原始文本从库中移除

##### Scenario: 导入并采纳不产生 TrainingEvent

- GIVEN 一条持有非空训练事件存储的真实导入路径（该路径够得到事件存储，仿 `SessionRunCoordinator` 持有存储却不写入）
- WHEN 用户导入并采纳附录 A
- THEN 采纳成功，个人牌谱库条目数增加 1（证明导入确实发生，排除"什么都没做"蒙混过关）
- AND 训练事件存储的条数与内容在整个过程中保持不变

## Impact

- **Code:** 新增解析包（暂名 `HandHistory`，位于 PokerCore 之上）承载"文本 → 统一牌谱模型 + 冲突检测 + 规范序列化"的纯逻辑；新增个人牌谱的本地持久化（版本化资源，独立持久化包或基础设施层，不进领域包，仿 `SessionSimulation → SessionPersistence`）；App 新增 `Features/HandLab` 的导入、冲突预览与库界面，导入协调器持有事件存储（仿 `SessionRunCoordinator`）。
- **Interfaces:** 新增导入/预览/库的 UI 入口；本切片无服务端接口变更（个人牌谱跨设备同步推后）。
- **Dependencies:** 无第三方运行时依赖；复用 PokerCore 的 `Card` / `BBAmount` / `TablePosition`；统一牌谱模型需 `Sendable`。

## Risks

- **PokerStars 格式变体众多**（货币符号、锦标赛、straddle、ante、Zoom 标记）→ 本切片限定 2–9 人 NLHE 现金，其余一律走"不受支持"的明确报出路径（附录 C 守住），而不是尽力猜。
- **金额→BB 换算引入浮点或舍入误差** → 一律用整数 centi-BB，按大盲精确换算；非整除边界标为冲突交用户裁决，绝不四舍五入（附录 D 守住）。
- **解析器静默猜测有冲突的字段** → 每个不确定字段必须进入冲突流程；用附录 A/B"仅差一行"的成对断言防退化，proxy 键判定无法同时通过两者。
- **统一牌谱模型与 M2A 的模拟牌谱模型混淆** → 二者是两类数据，本模型独立定义，不复用 `SessionSimulation` 的 `PlayedHand`（架构复核确认其定长 6 人、英雄固定座、无未知底牌、抽水恒 0、无原始文本，结构上不适配）。
- **新包不被分层门禁覆盖** → `scripts/check-package-layering.sh` 逐包枚举，新增 `HandHistory` 及其持久化包必须显式加入该脚本，否则"分层不被破坏"只是声明而未被强制（见验收标准 6）。
- **TrainingEvent 隔离断言退化为"够不到存储的类型"** → 导入路径必须真的持有事件存储（仿 `SessionRunCoordinator`），且隔离场景同时断言"采纳成功、库条目 +1"，排除空操作蒙混。

## Non-Goals

- 关键节点选择、策略分析、漏洞标签、分支重放与反事实对比、补救训练生成——推后到 M2B 后续切片。
- 生成任何 `TrainingEvent`：本切片只产出个人牌谱资源；当补救训练切片到来时，它必须复用冻结的 `Contracts/training-event-upload-v1.json` 契约（M2 gate）。
- 个人牌谱跨设备同步：需要新的服务端 schema 与冲突语义，推后（类比 M2A 推迟 Session 同步）。
- PokerStars 以外的格式（GGPoker 等）与非 NLHE 变体、锦标赛牌谱。
- 手动从零构建场景（场景构建器属于后续切片）。

## Acceptance Criteria

1. 附录 A 被解析为统一模型：金额为整数 centi-BB、位置由按钮导出、逐街行动按序完整还原、抽水非零被捕获；换算被证明是大盲的函数（第二例）；跨进程规范序列化逐字节一致且等于黄金夹具。
2. 附录 C（不受支持）与附录 B（单字段冲突）分别被明确判为不受支持、恰报一条定位到行的冲突；附录 A 零冲突；附录 D 的非整除金额报冲突而非四舍五入；解析器不产生任何被猜测或被舍入的值。
3. 预览各项值等于模型值、原始文本不变；含未解决冲突时不可采纳；用户修正被标记字段后冲突清空并可采纳；冲突可定位到字段与行号。
4. 采纳的牌谱以版本化个人资源本地保存，取回值与采纳者相等，重复采纳保留旧版本不静默覆盖，删除一手不影响其余；导入采纳路径持有事件存储却使其条数与内容不变，同时库条目 +1。
5. 分层不被破坏：解析包只依赖 PokerCore；解析/领域逻辑不反向依赖基础设施或 UI；个人牌谱持久化不进领域包。
6. `scripts/check-package-layering.sh` 增加对新增 `HandHistory` 及其持久化包的显式条目，使第 5 条被门禁强制而非仅声明。
