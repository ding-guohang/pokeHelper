---
name: curriculum-m1c-adaptive-cash-20260810-01
status: designed
---

# 技术方案：M1C 自适应现金局课程

## 方案概述

M1C 要同时解决两件事：把真实内容送进可交付的构建，以及让训练内容随玩家弱点变化。方案的骨架是**让内容承载课程结构**——能力树节点、节点归属、求解假设全部是策略包的属性，训练事件保持不变。这一个决定连带消掉了本次最大的几处风险：跨语言字节冻结契约不用动、跨设备画像一致性不用新增同步面、复练调度不用新增持久化状态。

## 三个设计点的决断

### 1. 构建类别：用 Info.plist 里的频道标记，不用命令行参数

新增第三种构建类别 dogfooding。判定依据放在**产物自身**而不是调用方：

```
Config/Debug.xcconfig     PC_CONTENT_CHANNEL = debug
Config/Release.xcconfig   PC_CONTENT_CHANNEL = store
Config/Dogfood.xcconfig   PC_CONTENT_CHANNEL = dogfood   （#include Release.xcconfig）
```

`project.yml` 把 `PCContentChannel: $(PC_CONTENT_CHANNEL)` 写进 Info.plist，并新增 `Dogfood` 配置（基于 release）。内容随包与否继续用既有的 `EXCLUDED_SOURCE_FILE_NAMES` 机制：

| 配置 | 排除 | 随包内容 |
|---|---|---|
| Debug | 无 | Dev + Core + Unverified |
| Dogfood | `DevStrategyPack.json` | Core（reviewed）+ Unverified |
| Release | `DevStrategyPack.json` `UnverifiedStrategyPack.json` | 仅 Core（reviewed） |

门禁 `scripts/check-release-content.sh` 打开构建产物，读 `PCContentChannel`，枚举包内所有策略包，逐个读 manifest 的 `reviewStatus`，按上表判定。

**为什么不用命令行参数指定 channel。** 门禁如果依赖调用方传 `--channel store`，忘传就等于没检查，而这正是本轮反复出现的失效模式——`strings | grep -q` 那次、`TEST_RUNNER_` 环境变量那次，都是「门禁看起来跑了但什么都没验」。频道刻在产物里，门禁无法被漏配绕过。

### 2. 复练调度状态：从事件历史推导，不持久化

`intervalDays` 与 `nextDueAt` 是对某节点事件序列的确定性折叠：

```
首次出现 quality ∈ {improvable, blunder}        → interval = 1, due = 该事件时间 + 1d
此后该节点第一条 occurredAt ≥ due 的事件即复练：
    quality ∈ {excellent, acceptable}           → interval 沿 1/3/7/14/30 前进一级
    否则                                         → 退一级，下限 1
    due = 该复练事件时间 + interval
```

**为什么推导优于持久化。** 持久化要新增一份状态，就要回答它怎么同步、怎么在档案切换时隔离、两台设备冲突时谁赢——M1B 花了整整一轮把「画像由完整事件确定性归约」这条性质建立起来，新增可变状态等于在它旁边开一个例外。推导则天然满足 `local-learning-profile` 已有的「两台设备相同事件集合得到相同画像」要求。代价是每次计算 O(节点事件数)，在个人训练的数据量下可忽略。

调度结果通过 `RepetitionSchedule` 值类型暴露 `intervalDays` 与 `nextDueAt`，满足 spaced-repetition 要求的可读性，但它是计算结果不是存储。

### 3. 服务端内容分发端点：本次不做

`strategy-content-pipeline` 的客户端行为（checksum 校验、版本比较、拒绝后保留当前内容）全部实现，接在 `ContentUpdateSource` 协议后面，M1C 只提供一个测试用实现。**HTTPS 端点与对象存储不在本次范围。**

**为什么。** 端点在存在第二个内容版本之前没有任何东西可以下发；而 M1C 的真实价值是让 App 第一次有内容。把服务端一起做会显著放大范围，却不改变用户能拿到什么。客户端机制先立住，端点是之后一个小增量。

这一条同时订正 `docs/architecture/components.md:40`——它把「内容分发」标为 M1B 已实现，而 `Server/internal/` 下根本没有 content 包。

## 详细设计

### StrategyContent：内容承载课程结构

```swift
public enum ReviewStatus: String, Codable, Sendable {
    case testFixture
    case unverifiedDraft   // 新增
    case reviewed
    case retired
}

public struct StrategyPackManifest: Codable, Sendable {
    // 既有字段不变
    public let reviewedBy: String?   // 新增；reviewed 时必填
}

public struct CurriculumNode: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let prerequisiteNodeIDs: [String]
}

public struct StrategyPack: Codable, Sendable {
    public let manifest: StrategyPackManifest
    public let curriculum: [CurriculumNode]   // 新增
    public let scenarios: [DecisionScenario]
}

public struct DecisionScenario: Codable, Sendable, Identifiable {
    // 既有字段不变
    public let curriculumNodeID: String   // 新增
}
```

`StrategyPackValidator` 增加四条校验：`reviewed` 必须有 `reviewedBy` 与 `reviewedAt`；每个场景的 `curriculumNodeID` 在 `curriculum` 中存在；`prerequisiteNodeIDs` 全部可解析；能力树无环。全部产出既有风格的 typed error。

### TrainingDomain：节点掌握与复练

新增三个纯值类型，不引入可变状态：

```swift
public struct MasterySignal: Sendable, Equatable {
    public enum Kind { case sample, recentStability, confidenceCalibration, repetition, transfer }
    public let kind: Kind
    public let satisfied: Bool
    public let actual: Int
    public let required: Int
}

public struct NodeMastery: Sendable, Equatable {
    public let nodeID: String
    public let signals: [MasterySignal]   // 恒为五项，顺序固定
    public var isMastered: Bool { signals.allSatisfy(\.satisfied) }
}

public struct RepetitionSchedule: Sendable, Equatable {
    public let nodeID: String
    public let intervalDays: Int
    public let nextDueAt: Date
    public let isContentLimited: Bool
}
```

节点归属由 `CurriculumResolver` 完成：给定事件与当前包，用 `scenarioID` 查 `curriculumNodeID`。事件的 content version 与当前包不符时回退到事件自带的 `abilityDimension`，该事件计入维度样本但不参与任何节点的掌握判定——这条回退必须有独立测试，否则升级内容会静默改写历史节点归属。

`TrainingPlanner` 的排序输入扩展为五项，裁决顺序按 proposal 声明的顺序固定：弱项 → 高信心错误 → 距上次练习天数 → 复练到期 → 学习路径。入选原因用枚举 `PlanItemReason` 暴露，不是自由文本。

### App：披露与可用性

```swift
enum StrategyContentAvailability: Equatable {
    case developmentFixtureAvailable
    case unverifiedContentAvailable   // 新增
    case reviewedContentAvailable
    case reviewedContentUnavailable
}
```

`canStartTraining` 对新增 case 返回 `true`，`disclosureText` 返回新文案「未经策略审核」。Swift 的穷尽 switch 会强制 `StrategyContentMetadata.swift:23` 与 `:34` 两处以及所有下游展示点更新——这是我们要的，编译器代替人工清点调用点。

`disclosure(forStrategyPackID:)` 改为 `disclosure(forReviewStatus:)`：现在的实现靠硬编码 pack ID 判断是不是开发数据，加入第三种内容后这个判据不成立。

`AppDependencies.live()` 的 `#else` 分支从「无内容」改为「加载随包 Core 包」，`reviewedContentAvailable` 由此第一次在生产代码中被构造。

### 内容工具链

新增 SwiftPM 包 `Packages/StrategyTooling`，两个可执行目标，依赖 `StrategyContent` 复用既有校验器：

- `strategy-import` — 求解器导出 → 策略包。确定性靠 `JSONEncoder` 的 `.sortedKeys` + `.withoutEscapingSlashes` + 固定日期编码保证。**`RangeCell.actionWeightsBasisPoints` 是 `[String: Int]`**，没有 `.sortedKeys` 它的序列化顺序在跨进程时不稳定——这正是 checksum 漂移最可能的来源，必须有跨进程测试覆盖，同进程跑两次会因为哈希种子相同而假通过。
- `strategy-golden` — 内容升级黄金回归。对固定的 (场景, 提交) 对，比较新旧包下的 `lossRateBasisPoints` 与 `quality`，跨越 quality 边界即失败，通过时也逐条打印变化量。

### 内容本体与人工审核

两个包，走同一条导入管道：

1. **Core（reviewed）** — 6-max 100BB 翻前 RFI 与 3bet 范围。我先产出，**交由仓库所有者按范围表审核**，签字后才写入 `reviewedBy`/`reviewedAt` 并重新导入定版。这是任务序列中一道真实的人工闸门，不能由我自行跨过。
2. **Unverified（unverifiedDraft）** — 翻后深度内容。无需签字，但界面强制披露。

## Capability 覆盖

| Capability | 主要落点 |
|---|---|
| strategy-content-pipeline | `Packages/StrategyTooling/`、`Packages/StrategyContent/`（校验扩展）、`PokerCoach/Infrastructure/Content/` |
| initial-diagnostic | `Packages/TrainingDomain/DiagnosticBlueprint.swift`、`PokerCoach/Features/Today/` |
| adaptive-curriculum | `Packages/StrategyContent/`（树模型）、`Packages/TrainingDomain/`（掌握判定）、`PokerCoach/Features/Learn/` |
| spaced-repetition | `Packages/TrainingDomain/RepetitionScheduler.swift` |
| versioned-strategy-content | `Packages/StrategyContent/StrategyModels.swift`、`StrategyPackValidator.swift` |
| local-learning-profile | `Packages/TrainingDomain/PlayerModel.swift`、`TrainingPlanner.swift` |
| m1a-release-safety | `Config/`、`project.yml`、`scripts/check-release-content.sh` |

## 影响范围与向后兼容

- **`Contracts/training-event-upload-v1.json` 不变。** 节点归属从内容派生是为了保住这一点，任务序列中以 `.sha256` 未变更作为硬性验收。
- **`DecisionScenario` 与 `StrategyPack` 增加字段** → `DevStrategyPack.json` 与所有测试 fixture 需同步补字段，否则解码失败。这是本次最广的机械改动面。
- **`StrategyContentAvailability` 增加 case** → 所有穷尽 switch 需更新，编译器强制。
- **服务端不变。**

## 风险

| 风险 | 缓解 |
|---|---|
| 掌握判定实现成恒假仍能通过测试 | 先写「五项齐备判定 mastered」的正向测试，且必须看到它在空实现下失败，再写五项否定测试 |
| `[String: Int]` 序列化顺序导致 checksum 漂移 | 跨进程、异哈希种子的确定性测试；同进程重复运行不作数 |
| 新增模型字段导致既有 fixture 静默失效 | 字段一律非可选，让解码在测试中直接失败而不是取默认值 |
| 人工审核闸门被跳过，未审内容被标 reviewed | `reviewedBy` 非空由校验器强制；门禁在 store 频道拒绝非 reviewed；两者互不依赖 |
| 内容升级改写历史节点归属 | content version 不匹配时回退 `abilityDimension` 并排除出掌握判定，有独立测试 |
| Dogfood 配置漏配 Info.plist 键导致门禁失判 | 门禁在 `PCContentChannel` 缺失时以非零码失败，不默认放行 |

## 测试策略

- **领域层**（StrategyContent / TrainingDomain / StrategyTooling）用 SwiftPM 测试，覆盖全部校验、掌握判定、复练折叠与导入确定性。
- **App 层**用宿主单元测试覆盖披露文案、可用性状态与 ViewModel 刷新。
- **UI 测试**只覆盖 `unverifiedDraft` 披露在真实布局中可见，iPhone 与 iPad 各一。既有 UI 测试对布局形态敏感（iPad 走 NavigationSplitView），新增断言沿用既有的布局感知写法。
- **门禁**用真实构建产物验证三个频道各一条正反路径，其中 store 频道必须同时有「含未审核内容失败」与「全 reviewed 通过」两条，否则「一律失败」的实现也能通过。
- 每条新测试在实现前必须先看到它失败。
