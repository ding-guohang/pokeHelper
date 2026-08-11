# M1A 模块边界与 M1B 交接

## M1B 可依赖的公开契约

以下列表是完整且排他的 M1A → M1B 领域契约。M1B 只能在不改变这些契约语义的前提下依赖它们：

| 公开契约 | 所属模块与源码位置 | M1B 用途 |
|---|---|---|
| `TrainingEvent` | `TrainingDomain` — `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEvent.swift` | 不可变、可编码、带内容版本的同步事件 |
| `TrainingEventStore` | `TrainingDomain` — `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEventStore.swift` | 本地优先追加、全量读取和 checkpoint 后增量读取的存储协议；checkpoint 表示 JSON Lines 追加日志顺序，不受事件时间影响 |
| `FileTrainingEventStore` | `TrainingPersistence` — `Packages/TrainingPersistence/Sources/TrainingPersistence/FileTrainingEventStore.swift` | M1A 的 JSON Lines 本地存储实现；M1B 的 outbox/同步不得改变其事件语义。M2A 起搬出领域包，事件语义未变 |
| `StrategyPackManifest` | `StrategyContent` — `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift` | 策略内容的 pack ID、schema/content version 和审核来源元数据 |

M1B 应在 App Infrastructure 中围绕上述四个契约增加远端同步器：先持久化本地 `TrainingEvent`，再通过 outbox 幂等上传，并以 checkpoint 拉取新增事件。远端确认、重试和冲突处理不能改变事件 ID、事件内容版本或只追加语义。

`allEvents()` 为 UI 和能力归约按 `occurredAt`、再按事件 UUID
稳定排序；`events(after:)` 则严格沿 JSON Lines 追加顺序读取。
即使设备时钟回拨导致晚追加事件的 `occurredAt` 更早，该事件仍必须出现在
先前 checkpoint 之后，避免增量同步漏失。

HTTP 客户端、认证与会话、outbox 持久化细节、服务端 schema，以及 API/数据库 DTO 都属于 M1B 基础设施层。不得把它们放入 `PokerCore`、`StrategyContent` 或 `TrainingDomain`；DTO 必须在基础设施边界转换为上述领域类型，领域包不得依赖 HTTP、认证 SDK、Go API 或数据库表示。

## 供 M3 复用的位置契约

位置使用两个联合字段，定义在 `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift`：

- `SolverAssumptions.tableSize`：本手被发牌的玩家人数，合法范围为 2–9。
- `DecisionScenario.heroSeatOffsetFromButton`：英雄相对按钮的座位偏移，有效范围始终为 `0..<tableSize`。
  - `tableSize == 2`：`0` 是 `BTN/SB`，`1` 是 `BB`。
  - `tableSize >= 3`：`0` 是 `BTN`，`1` 是 `SB`，`2` 是 `BB`，其余位置按人数确定性推导。

`StrategyPackValidator` 必须联合校验这两个字段。M1A fixture 使用 6 人桌，但类型和内容契约不绑定 6-max；M3 的标准 MTT、人数递减和决赛桌场景应直接复用该表示，不新增自由文本位置或固定人数位置枚举。
