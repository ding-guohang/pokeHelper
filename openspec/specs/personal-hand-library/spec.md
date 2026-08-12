# Capability: personal-hand-library

## Requirement: 采纳的牌谱作为版本化个人资源本地保存

The system SHALL store an accepted hand as a versioned personal resource on the device, retaining its raw source alongside the standardized model, and SHALL allow viewing and deletion without affecting other stored hands.

### Scenario: 采纳后可取回与所采纳者相等的牌谱

- GIVEN 用户采纳了附录 A
- WHEN 从库中取回该牌谱
- THEN 取回的标准化模型与采纳时的模型逐字段相等，原始文本与附录 A 逐字节相同
- AND 其牌谱身份等于附录 A 原文的规范化 SHA-256

### Scenario: 再次采纳同一手保留旧版本、不静默覆盖

- GIVEN 用户已采纳附录 A（版本 1）
- WHEN 用户再次采纳身份相同的附录 A
- THEN 库中该身份下存在两个版本，版本号为 1 与 2
- AND 版本 1 的规范序列化与首次采纳时逐字节相同（未被覆盖）

### Scenario: 删除一手不影响其余

- GIVEN 库中已采纳附录 A 与另一段身份不同的牌谱，共两条
- WHEN 用户删除附录 A
- THEN 库中剩余恰为那另一段牌谱，其内容不受影响
- AND 附录 A 及其原始文本从库中移除

### Scenario: 导入并采纳不产生 TrainingEvent

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
