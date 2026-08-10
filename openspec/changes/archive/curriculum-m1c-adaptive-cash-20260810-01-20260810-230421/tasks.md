---
name: curriculum-m1c-adaptive-cash-20260810-01
status: planned
---

# 执行计划：M1C 自适应现金局课程

## 执行原则

- 每个 Task 一个可独立评审的提交。
- 每条测试**必须先看到它失败**再写实现。掌握判定尤其如此——本次审需已经证明，只有否定场景的规格可以被 `false` 恒真实现全绿。
- 不得为了让测试通过而放宽断言。断言与实现冲突时，先判定哪一个是错的。

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核时间 | Task 1 |
| versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核人 | Task 1 |
| versioned-strategy-content | 审核状态约束 | 已审核内容元数据齐备 | Task 1 |
| versioned-strategy-content | 审核状态约束 | 开发内容展示 | Task 16 |
| versioned-strategy-content | 审核状态约束 | 未审核内容必须披露 | Task 16 |
| versioned-strategy-content | 策略包来源可追溯 | 合法策略包加载 | Task 3 |
| versioned-strategy-content | 策略包来源可追溯 | checksum 不匹配 | Task 18 |
| versioned-strategy-content | 决策节点语义校验 | 频率总和错误 | Task 3 |
| versioned-strategy-content | 决策节点语义校验 | 非法行动进入策略 | Task 3 |
| versioned-strategy-content | 内容版本不可原地修改 | 内容升级后历史仍可追溯 | Task 20 |
| adaptive-curriculum | 现金局能力树 | 浏览能力树 | Task 19 |
| adaptive-curriculum | 现金局能力树 | 内容缺失的节点 | Task 19 |
| adaptive-curriculum | 现金局能力树 | 事件所属内容版本不在本机 | Task 8 |
| adaptive-curriculum | 节点掌握判定 | 五项信号齐备时判定掌握 | Task 10 |
| adaptive-curriculum | 节点掌握判定 | 样本不足不判定掌握 | Task 10 |
| adaptive-curriculum | 节点掌握判定 | 近期稳定性不足不判定掌握 | Task 10 |
| adaptive-curriculum | 节点掌握判定 | 高信心错误阻止掌握 | Task 10、Task 11 |
| adaptive-curriculum | 节点掌握判定 | 复练未完成不判定掌握 | Task 10 |
| adaptive-curriculum | 节点掌握判定 | 迁移未通过不判定掌握 | Task 10 |
| adaptive-curriculum | 学习路径推荐 | 今日计划来自画像而非用户选择 | Task 11 |
| adaptive-curriculum | 学习路径推荐 | 用户直接选择具体节点 | Task 19 |
| spaced-repetition | 同类非同题复现 | 隔日复练 | Task 9 |
| spaced-repetition | 同类非同题复现 | 内容不足以避免重复 | Task 9 |
| spaced-repetition | 复现间隔阶梯 | 首次复练间隔为一天 | Task 9 |
| spaced-repetition | 复现间隔阶梯 | 答对沿阶梯前进 | Task 9 |
| spaced-repetition | 复现间隔阶梯 | 答错退一级且不低于一天 | Task 9 |
| strategy-content-pipeline | 求解器输出导入 | 合法求解器导出导入 | Task 5 |
| strategy-content-pipeline | 求解器输出导入 | 求解器导出不满足语义约束 | Task 5 |
| strategy-content-pipeline | 求解器输出导入 | 导入是确定性的 | Task 6 |
| strategy-content-pipeline | 内容升级黄金回归 | 升级改变了评分结果 | Task 7 |
| strategy-content-pipeline | 内容升级黄金回归 | 升级在容差内 | Task 7 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 首次离线启动使用内置内容 | Task 17 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 校验通过且版本更高的更新包被采用 | Task 18 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包 checksum 不匹配 | Task 18 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包内容版本等于当前 | Task 18 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包内容版本低于当前 | Task 18 |
| initial-diagnostic | 跨维度初始诊断 | 完成诊断 | Task 12、Task 20 |
| initial-diagnostic | 跨维度初始诊断 | 跳过诊断 | Task 12、Task 20 |
| initial-diagnostic | 跨维度初始诊断 | 中断后恢复 | Task 12、Task 20 |
| local-learning-profile | 不可变本地训练事件 | 首次追加 / 重复事件 / 损坏事件文件 | 既有实现，Task 23 回归 |
| local-learning-profile | 能力画像归约 | 高信心错误 | 既有实现，Task 23 回归 |
| local-learning-profile | 今日训练优先级 | 高信心弱项优先 | Task 11 |
| local-learning-profile | 今日训练优先级 | 到期复练排在未到期项目之前 | Task 11 |
| local-learning-profile | 今日训练优先级 | 高信心错误压过复练到期 | Task 11 |
| local-learning-profile | 今日训练优先级 | 每个计划项给出被选中的原因 | Task 11 |
| local-learning-profile | 今日训练优先级 | 计划受可用时长约束 | Task 11 |
| local-learning-profile | 今日与复盘使用真实历史 | 决策完成后刷新 | Task 20 |
| local-learning-profile | 跨设备历史确定性归约 | 远端事件进入画像 | 既有实现，Task 23 回归 |
| local-learning-profile | 跨设备历史确定性归约 | 两台设备独立归约得到相同画像 | Task 8 |
| local-learning-profile | 能力树节点掌握信号 | 查看未掌握原因 | Task 10、Task 19 |
| m1a-release-safety | 开发策略数据隔离 | Debug 训练 | Task 21 |
| m1a-release-safety | 开发策略数据隔离 | Release 构建 | Task 21 |
| m1a-release-safety | 开发策略数据隔离 | dogfooding 构建携带未审核内容 | Task 21、Task 22 |
| m1a-release-safety | 开发策略数据隔离 | 商店发布拒绝未审核内容 | Task 22 |
| m1a-release-safety | 开发策略数据隔离 | 商店发布接受已审核内容 | Task 22 |
| m1a-release-safety | 一键验证 | 从干净检出验证 | Task 23 |

## 文件结构

```
Packages/StrategyContent/Sources/StrategyContent/
    StrategyModels.swift            改：ReviewStatus、reviewedBy、CurriculumNode、curriculumNodeID
    StrategyPackValidator.swift     改：审核元数据、能力树校验
Packages/StrategyTooling/           新增包
    Package.swift
    Sources/StrategyToolingCore/
        SolverExport.swift          求解器导出的输入模型
        PackBuilder.swift           导出 → StrategyPack，确定性编码
        GoldenRegression.swift      升级回归比较
    Sources/strategy-import/main.swift
    Sources/strategy-golden/main.swift
    Tests/StrategyToolingTests/
Packages/TrainingDomain/Sources/TrainingDomain/
    CurriculumResolver.swift        新增：事件 → 节点归属，版本回退
    RepetitionScheduler.swift       新增：间隔阶梯折叠
    NodeMastery.swift               新增：五项掌握信号
    DiagnosticBlueprint.swift       新增：诊断蓝图与进度
    TrainingPlanner.swift           改：裁决顺序、入选原因、时长约束
PokerCoach/
    App/StrategyContentMetadata.swift   改：unverifiedContentAvailable 与披露文案
    App/AppDependencies.swift           改：走通 reviewedContentAvailable
    Infrastructure/Content/
        ContentUpdateSource.swift       新增：更新来源协议
        BundledContentLoader.swift      新增：随包内容加载
        ContentUpdateCoordinator.swift  新增：校验、版本比较、回退
    Features/Learn/                     改：能力树界面
    Features/Today/                     改：诊断入口、计划原因
    Resources/CoreStrategyPack.json         新增：reviewed 核心集
    Resources/UnverifiedStrategyPack.json   新增：unverifiedDraft 深度内容
Config/Dogfood.xcconfig             新增
project.yml                         改：Dogfood 配置、PCContentChannel
scripts/check-release-content.sh    新增：频道 × 审核状态门禁
scripts/verify-m1c.sh               新增：一键验证
```

---

## Phase A — 内容模型与校验

### Task 1: 审核状态与审核元数据 | covers: versioned-strategy-content/审核状态约束

**步骤 1.1** — 先写失败测试。新建
`Packages/StrategyContent/Tests/StrategyContentTests/ReviewMetadataTests.swift`：

```swift
import Foundation
import Testing
@testable import StrategyContent

@Suite("审核元数据")
struct ReviewMetadataTests {
    // GIVEN review status 为 reviewed 且 reviewed-at 为空
    // WHEN validator 校验
    // THEN 策略包被拒绝
    @Test("已审核内容缺少审核时间")
    func rejectsReviewedPackWithoutReviewTime() throws {
        let pack = StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: "Meow Ding",
            reviewedAt: nil
        )
        #expect(throws: StrategyPackValidationError.missingReviewedAt) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // GIVEN review status 为 reviewed、reviewed-at 非空、但 reviewed-by 为空
    // WHEN validator 校验
    // THEN 策略包被拒绝，且错误指明缺失的是审核人
    @Test("已审核内容缺少审核人")
    func rejectsReviewedPackWithoutReviewer() throws {
        let pack = StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: nil,
            reviewedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
        #expect(throws: StrategyPackValidationError.missingReviewedBy) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // GIVEN reviewed-by 与 reviewed-at 均非空且场景合法
    // WHEN validator 校验
    // THEN 策略包被接受，审核人与审核时间可读
    @Test("已审核内容元数据齐备")
    func acceptsFullyAttributedReviewedPack() throws {
        let reviewedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let pack = StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: "Meow Ding",
            reviewedAt: reviewedAt
        )
        try StrategyPackValidator().validate(pack)
        #expect(pack.manifest.reviewedBy == "Meow Ding")
        #expect(pack.manifest.reviewedAt == reviewedAt)
    }

    // unverifiedDraft 不要求审核元数据——否则它与 reviewed 就没有区别了。
    @Test("未审核草稿不要求审核元数据")
    func acceptsUnverifiedDraftWithoutReviewMetadata() throws {
        let pack = StrategyPackFixture.pack(
            reviewStatus: .unverifiedDraft,
            reviewedBy: nil,
            reviewedAt: nil
        )
        try StrategyPackValidator().validate(pack)
    }
}
```

**步骤 1.2** — 运行，确认因为 `unverifiedDraft`、`reviewedBy`、
`missingReviewedBy` 三个符号不存在而**编译失败**：

```bash
swift test --package-path Packages/StrategyContent 2>&1 | tail -20
```

预期出现 `cannot infer contextual base in reference to member 'unverifiedDraft'`。

**步骤 1.3** — 在 `StrategyModels.swift` 中扩展模型：

```swift
public enum ReviewStatus: String, Codable, Sendable {
    case testFixture
    case unverifiedDraft
    case reviewed
    case retired
}

public struct StrategyPackManifest: Codable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let contentVersion: String
    public let reviewStatus: ReviewStatus
    public let generatedSource: String
    public let reviewedBy: String?
    public let reviewedAt: Date?

    public init(
        id: String,
        schemaVersion: Int,
        contentVersion: String,
        reviewStatus: ReviewStatus,
        generatedSource: String,
        reviewedBy: String?,
        reviewedAt: Date?
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.reviewStatus = reviewStatus
        self.generatedSource = generatedSource
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
    }
}
```

**步骤 1.4** — 在 `StrategyPackValidationError` 中增加两个 case，替换既有的
审核时间校验：

```swift
case missingReviewedAt
case missingReviewedBy
```

`StrategyPackValidator.validate` 中原有的 `reviewStatus == .reviewed` 分支改为：

```swift
if pack.manifest.reviewStatus == .reviewed {
    guard pack.manifest.reviewedAt != nil else {
        throw StrategyPackValidationError.missingReviewedAt
    }
    guard let reviewedBy = pack.manifest.reviewedBy,
          !reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw StrategyPackValidationError.missingReviewedBy
    }
}
```

**步骤 1.5** — 运行至通过：

```bash
swift test --package-path Packages/StrategyContent
```

预期 4 条新测试全部通过，既有测试保持通过。

---

### Task 2: 能力树进入内容模型 | covers: adaptive-curriculum/现金局能力树

**步骤 2.1** — 先写失败测试，新建
`Packages/StrategyContent/Tests/StrategyContentTests/CurriculumTreeTests.swift`：

```swift
import Testing
@testable import StrategyContent

@Suite("能力树校验")
struct CurriculumTreeTests {
    @Test("场景引用了不存在的节点")
    func rejectsScenarioPointingAtUnknownNode() throws {
        let pack = StrategyPackFixture.pack(
            curriculum: [CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: [])],
            scenarioNodeID: "turn-barrel"
        )
        #expect(throws: StrategyPackValidationError.unknownCurriculumNode(
            scenarioID: StrategyPackFixture.defaultScenarioID,
            nodeID: "turn-barrel"
        )) {
            try StrategyPackValidator().validate(pack)
        }
    }

    @Test("前置节点无法解析")
    func rejectsUnresolvablePrerequisite() throws {
        let pack = StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "turn-barrel", title: "转牌持续下注", prerequisiteNodeIDs: ["flop-cbet"]),
            ],
            scenarioNodeID: "turn-barrel"
        )
        #expect(throws: StrategyPackValidationError.unknownPrerequisite(
            nodeID: "turn-barrel",
            prerequisiteID: "flop-cbet"
        )) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // 有环的能力树会让「前置全部掌握才解锁」永远无法满足，且会让任何
    // 深度优先遍历不终止。必须在加载时就拒绝。
    @Test("能力树有环")
    func rejectsCyclicTree() throws {
        let pack = StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "a", title: "A", prerequisiteNodeIDs: ["b"]),
                CurriculumNode(id: "b", title: "B", prerequisiteNodeIDs: ["a"]),
            ],
            scenarioNodeID: "a"
        )
        #expect(throws: StrategyPackValidationError.cyclicCurriculum(nodeIDs: ["a", "b"])) {
            try StrategyPackValidator().validate(pack)
        }
    }

    @Test("合法能力树通过校验")
    func acceptsAcyclicResolvableTree() throws {
        let pack = StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: []),
                CurriculumNode(id: "flop-cbet", title: "翻牌持续下注", prerequisiteNodeIDs: ["preflop-rfi"]),
            ],
            scenarioNodeID: "flop-cbet"
        )
        try StrategyPackValidator().validate(pack)
    }
}
```

**步骤 2.2** — 运行确认编译失败（`CurriculumNode` 不存在）。

**步骤 2.3** — 在 `StrategyModels.swift` 增加模型：

```swift
public struct CurriculumNode: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let prerequisiteNodeIDs: [String]

    public init(id: String, title: String, prerequisiteNodeIDs: [String]) {
        self.id = id
        self.title = title
        self.prerequisiteNodeIDs = prerequisiteNodeIDs
    }
}
```

`DecisionScenario` 增加 `public let curriculumNodeID: String`（放在 `abilityDimension`
之后，并同步 `init`）。`StrategyPack` 增加 `public let curriculum: [CurriculumNode]`
（放在 `manifest` 之后）。**两个字段都不给默认值**——让缺字段的旧 fixture 在解码时
直接失败，而不是静默取空值。

**步骤 2.4** — 校验错误增加三个 case：

```swift
case unknownCurriculumNode(scenarioID: String, nodeID: String)
case unknownPrerequisite(nodeID: String, prerequisiteID: String)
case cyclicCurriculum(nodeIDs: [String])
```

**步骤 2.5** — 在 `StrategyPackValidator` 中实现。环检测用显式栈的深度优先，
不用递归，避免深树触发栈溢出；返回的 `nodeIDs` 按字典序排序，保证错误可断言：

```swift
private func validateCurriculum(_ pack: StrategyPack) throws {
    let nodesByID = Dictionary(
        uniqueKeysWithValues: pack.curriculum.map { ($0.id, $0) }
    )

    for scenario in pack.scenarios where nodesByID[scenario.curriculumNodeID] == nil {
        throw StrategyPackValidationError.unknownCurriculumNode(
            scenarioID: scenario.id,
            nodeID: scenario.curriculumNodeID
        )
    }

    for node in pack.curriculum {
        for prerequisiteID in node.prerequisiteNodeIDs where nodesByID[prerequisiteID] == nil {
            throw StrategyPackValidationError.unknownPrerequisite(
                nodeID: node.id,
                prerequisiteID: prerequisiteID
            )
        }
    }

    if let cycle = firstCycle(in: nodesByID) {
        throw StrategyPackValidationError.cyclicCurriculum(nodeIDs: cycle)
    }
}

/// Iterative depth-first search. Returns the sorted IDs of one cycle, or nil.
private func firstCycle(in nodesByID: [String: CurriculumNode]) -> [String]? {
    var permanentlyMarked: Set<String> = []

    for start in nodesByID.keys.sorted() where !permanentlyMarked.contains(start) {
        var onPath: Set<String> = []
        var stack: [(id: String, remaining: ArraySlice<String>)] = [
            (start, ArraySlice(nodesByID[start]?.prerequisiteNodeIDs ?? [])),
        ]
        onPath.insert(start)

        while var frame = stack.popLast() {
            guard let next = frame.remaining.popFirst() else {
                onPath.remove(frame.id)
                permanentlyMarked.insert(frame.id)
                continue
            }
            stack.append(frame)
            if onPath.contains(next) {
                return onPath.sorted()
            }
            if permanentlyMarked.contains(next) {
                continue
            }
            onPath.insert(next)
            stack.append((next, ArraySlice(nodesByID[next]?.prerequisiteNodeIDs ?? [])))
        }
    }
    return nil
}
```

在 `validate` 末尾调用 `try validateCurriculum(pack)`。

**步骤 2.6** — 运行至通过：

```bash
swift test --package-path Packages/StrategyContent
```

---

### Task 3: 既有 fixture 与开发包补齐新字段 | covers: versioned-strategy-content/策略包来源可追溯

**步骤 3.1** — 运行完整测试，收集所有因缺字段而失败的解码点：

```bash
swift test --package-path Packages/StrategyContent 2>&1 | grep -c "keyNotFound"
```

**步骤 3.2** — 更新 `PokerCoach/Resources/DevStrategyPack.json`：manifest 增加
`"reviewedBy": null`；顶层增加 `curriculum` 数组，为其中每个场景声明节点；每个场景
增加 `curriculumNodeID`。开发包的节点结构与 Core 包保持同名，这样 Debug 下看到的
能力树形状与真实构建一致。

**步骤 3.3** — 更新 `StrategyPackFixture`（测试支持类型），把 Task 1、Task 2 用到的
参数化入口补齐：

```swift
enum StrategyPackFixture {
    static let defaultScenarioID = "fixture-scenario-1"

    static func pack(
        reviewStatus: ReviewStatus = .testFixture,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil,
        curriculum: [CurriculumNode] = [
            CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: []),
        ],
        scenarioNodeID: String = "preflop-rfi"
    ) -> StrategyPack {
        // 复用既有的场景构造，只覆盖本次新增的字段。
    }
}
```

**步骤 3.4** — 全绿：

```bash
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/TrainingDomain
```

---

## Phase B — 内容工具链

### Task 4: 建立 StrategyTooling 包 | covers: strategy-content-pipeline/求解器输出导入

**步骤 4.1** — 新建 `Packages/StrategyTooling/Package.swift`：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StrategyTooling",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "strategy-import", targets: ["strategy-import"]),
        .executable(name: "strategy-golden", targets: ["strategy-golden"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
        .package(path: "../StrategyContent"),
    ],
    targets: [
        .target(
            name: "StrategyToolingCore",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "StrategyContent", package: "StrategyContent"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "strategy-import", dependencies: ["StrategyToolingCore"]),
        .executableTarget(name: "strategy-golden", dependencies: ["StrategyToolingCore"]),
        .testTarget(name: "StrategyToolingTests", dependencies: ["StrategyToolingCore"]),
    ]
)
```

**步骤 4.2** — 确认能构建：

```bash
swift build --package-path Packages/StrategyTooling
```

**步骤 4.3** — 该包**不加入 `project.yml`**。它是本机开发工具，不进 App 目标；
`docs/standards/coding.md` 的「测试专用 fixture 与开发数据不得进入 Release」在此适用。

---

### Task 5: 导入的输入输出对应与失败路径 | covers: strategy-content-pipeline/求解器输出导入

**步骤 5.1** — 先写失败测试
`Packages/StrategyTooling/Tests/StrategyToolingTests/PackBuilderTests.swift`：

```swift
import Foundation
import StrategyContent
import Testing
@testable import StrategyToolingCore

@Suite("求解器导出导入")
struct PackBuilderTests {
    // GIVEN 一份含 N 个决策节点的导出
    // WHEN 导入工具生成策略包
    // THEN 场景数等于 N，且每条 (action, frequency, ev) 在输出中逐字段可找到
    @Test("输出逐条对应输入")
    func outputCorrespondsToInput() throws {
        let export = SolverExportFixture.export(nodeCount: 3)
        let pack = try PackBuilder().build(from: export, contentVersion: "2026.08.10")

        #expect(pack.scenarios.count == 3)
        for node in export.nodes {
            let scenario = try #require(pack.scenarios.first { $0.id == node.id })
            #expect(scenario.options.count == node.actions.count)
            for action in node.actions {
                let option = try #require(
                    scenario.options.first { $0.action == action.action }
                )
                #expect(option.frequencyBasisPoints == action.frequencyBasisPoints)
                #expect(option.ev == action.ev)
            }
        }
        try StrategyPackValidator().validate(pack)
    }

    // GIVEN 某节点频率总和不是 10,000
    // WHEN 导入处理该导出
    // THEN 失败并指明场景 ID 与实际总和，且不产出任何文件
    @Test("频率总和不合法时导入失败且不落盘")
    func rejectsBadFrequencyTotalWithoutWriting() throws {
        let export = SolverExportFixture.export(nodeCount: 2, frequencyTotalOverride: 9_900)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        #expect(throws: PackBuildError.frequencyTotalMismatch(
            scenarioID: export.nodes[1].id,
            actual: 9_900
        )) {
            try PackBuilder().write(from: export, contentVersion: "2026.08.10", to: outputDirectory)
        }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path())
        #expect(leftovers.isEmpty, "失败的导入在输出目录留下了 \(leftovers)")
    }
}
```

**步骤 5.2** — 运行确认失败。

**步骤 5.3** — 实现 `SolverExport.swift`、`PackBuilder.swift`。`write` 必须先在内存中
构建并完整校验，通过后再一次性写盘——分步写盘会在中途失败时留下半个包，正是
测试第二条要挡的情况。

**步骤 5.4** — 运行至通过：

```bash
swift test --package-path Packages/StrategyTooling
```

---

### Task 6: 跨进程导入确定性 | covers: strategy-content-pipeline/求解器输出导入

**步骤 6.1** — 这条测试是整个 Phase B 最重要的一条，且**必须跨进程**。
`RangeCell.actionWeightsBasisPoints` 是 `[String: Int]`，Swift 的字典迭代顺序由
每进程随机的哈希种子决定；同一进程内跑两次会用同一个种子，因此必然一致——
那样的测试什么都没验。

新建 `Packages/StrategyTooling/Tests/StrategyToolingTests/DeterminismTests.swift`：

```swift
import Foundation
import Testing
@testable import StrategyToolingCore

@Suite("导入确定性")
struct DeterminismTests {
    // GIVEN 同一份导出
    // WHEN 在两个独立进程中导入，两次工作目录、时钟与哈希种子均不同
    // THEN 字节完全相同，且等于签入的黄金 checksum
    @Test("跨进程字节一致")
    func producesIdenticalBytesAcrossProcesses() throws {
        let exportPath = Bundle.module.url(forResource: "sample-export", withExtension: "json")!
        let first = try runImporter(
            exportPath: exportPath,
            workingDirectory: makeScratchDirectory(),
            environment: ["SWIFT_DETERMINISTIC_HASHING": "1", "TZ": "UTC"]
        )
        let second = try runImporter(
            exportPath: exportPath,
            workingDirectory: makeScratchDirectory(),
            environment: ["TZ": "Asia/Shanghai"]
        )

        #expect(first == second, "两个进程产出的字节不同——很可能是字典序列化顺序")
        #expect(sha256Hex(first) == GoldenChecksum.sampleExportPack)
    }
}
```

`runImporter` 用 `Process` 启动构建好的 `strategy-import` 可执行文件，不在测试进程内
直接调用 `PackBuilder`。

**步骤 6.2** — 运行，观察它**失败**（此时 `PackBuilder` 尚未设置 `.sortedKeys`）。
这一步不能跳过：如果先写好编码器再写测试，就无法确认这条测试真的能抓到字典乱序。

**步骤 6.3** — 在 `PackBuilder` 中固定编码：

```swift
private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    // sortedKeys 是这里唯一防住 [String: Int] 迭代顺序随进程哈希种子变化的东西。
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}
```

**步骤 6.4** — 重跑至通过，并连续跑 5 次确认稳定：

```bash
for i in 1 2 3 4 5; do swift test --package-path Packages/StrategyTooling --filter Determinism || break; done
```

---

### Task 7: 内容升级黄金回归 | covers: strategy-content-pipeline/内容升级黄金回归

**步骤 7.1** — 先写失败测试
`Packages/StrategyTooling/Tests/StrategyToolingTests/GoldenRegressionTests.swift`：

```swift
import Testing
@testable import StrategyToolingCore

@Suite("内容升级黄金回归")
struct GoldenRegressionTests {
    // GIVEN 某场景 lossRateBasisPoints 从 40 变为 260
    // WHEN 运行升级回归
    // THEN 以非零码失败，报告含场景 ID、旧值、新值与跨越的 quality 边界
    @Test("跨越 quality 边界时失败")
    func failsWhenGradingCrossesAQualityBoundary() throws {
        let report = GoldenRegression().compare(
            old: GoldenFixture.dataset(lossRateBasisPoints: 40),
            new: GoldenFixture.dataset(lossRateBasisPoints: 260),
            toleranceBasisPoints: 50
        )

        #expect(report.exitCode != 0)
        let change = try #require(report.changes.first)
        #expect(change.scenarioID == GoldenFixture.scenarioID)
        #expect(change.oldLossRateBasisPoints == 40)
        #expect(change.newLossRateBasisPoints == 260)
        #expect(change.oldQuality == .acceptable)
        #expect(change.newQuality == .improvable)
    }

    // GIVEN 变化在容差内且不跨越边界
    // WHEN 运行回归
    // THEN 以零码通过，但报告仍逐条列出变化量
    @Test("容差内通过但仍逐条报告")
    func passesWithinToleranceAndStillReportsEveryDelta() throws {
        let report = GoldenRegression().compare(
            old: GoldenFixture.dataset(lossRateBasisPoints: 40),
            new: GoldenFixture.dataset(lossRateBasisPoints: 70),
            toleranceBasisPoints: 50
        )

        #expect(report.exitCode == 0)
        // 通过时也必须逐条列出，否则「无变化」与「变化但在容差内」
        // 在输出上无法区分，升级就成了黑箱。
        #expect(report.changes.count == 1)
        #expect(report.changes[0].deltaBasisPoints == 30)
    }
}
```

**步骤 7.2** — 运行确认失败，实现 `GoldenRegression.swift` 与 `strategy-golden` 入口，
运行至通过。

---

## Phase C — 领域逻辑

### Task 8: 节点归属与版本回退 | covers: adaptive-curriculum/现金局能力树

**步骤 8.1** — 先写失败测试
`Packages/TrainingDomain/Tests/TrainingDomainTests/CurriculumResolverTests.swift`：

```swift
import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("节点归属")
struct CurriculumResolverTests {
    // GIVEN 事件的 content version 与当前包一致
    // WHEN 求节点归属
    // THEN 归到内容声明的节点
    @Test("版本一致时归到内容声明的节点")
    func resolvesNodeFromContentWhenVersionMatches() throws {
        let pack = TrainingFixture.pack(contentVersion: "2026.08.06", scenarioNodeID: "turn-barrel")
        let event = TrainingFixture.event(scenarioID: pack.scenarios[0].id, contentVersion: "2026.08.06")

        let resolution = CurriculumResolver(pack: pack).resolve(event)

        #expect(resolution == .node("turn-barrel"))
    }

    // GIVEN 事件记录 2026.08.06，本机只有 2026.09.01
    // WHEN 归约器求节点归属
    // THEN 回退到事件自带的 abilityDimension，事件仍计入维度样本但不参与掌握判定
    @Test("版本不在本机时回退到事件自带维度")
    func fallsBackToEventDimensionWhenContentVersionAbsent() throws {
        let pack = TrainingFixture.pack(contentVersion: "2026.09.01", scenarioNodeID: "turn-barrel")
        let event = TrainingFixture.event(
            scenarioID: "s-from-old-pack",
            contentVersion: "2026.08.06",
            abilityDimension: "bet-sizing"
        )

        let resolution = CurriculumResolver(pack: pack).resolve(event)

        #expect(resolution == .dimensionOnly("bet-sizing"))
        #expect(resolution.countsTowardMastery == false)
        #expect(resolution.abilityDimension == "bet-sizing")
    }

    // 回退的事件不能被丢弃——否则升级内容会让历史样本量凭空缩水。
    @Test("回退事件仍计入维度样本")
    func fallbackEventStillCountsTowardTheDimensionSample() throws {
        let pack = TrainingFixture.pack(contentVersion: "2026.09.01", scenarioNodeID: "turn-barrel")
        let events = [
            TrainingFixture.event(scenarioID: "s-old", contentVersion: "2026.08.06", abilityDimension: "bet-sizing"),
            TrainingFixture.event(scenarioID: pack.scenarios[0].id, contentVersion: "2026.09.01", abilityDimension: "bet-sizing"),
        ]

        let profile = PlayerModelReducer(pack: pack).reduce(events)

        #expect(profile.dimension("bet-sizing")?.sampleCount == 2)
    }
}
```

**步骤 8.2** — 运行确认失败，实现 `CurriculumResolver.swift`：

```swift
/// Where a training event belongs in the curriculum.
///
/// An event records the pack and content version it was answered under. When
/// that version is not the one currently installed, its scenario may not exist
/// locally at all, so node membership cannot be resolved. Dropping the event
/// would silently shrink the user's history every time content upgrades, so it
/// keeps contributing to its ability dimension and is excluded only from
/// node-level mastery, where attributing it to the wrong node would be worse
/// than not counting it.
public enum CurriculumResolution: Sendable, Equatable {
    case node(String)
    case dimensionOnly(String)

    public var countsTowardMastery: Bool {
        if case .node = self { return true }
        return false
    }
}
```

**步骤 8.3** — 补一条既有 spec 的回归，确认「两台设备独立归约得到相同画像」在
引入节点归属后仍成立，写在同一测试文件：写入顺序打乱的两个事件集合，断言画像
逐字段相等且 `bet-sizing` 的 `sampleCount` 为 5、`meanScore` 为 62、
`highConfidenceErrorCount` 为 2。

**步骤 8.4** — 运行至通过：

```bash
swift test --package-path Packages/TrainingDomain
```

---

### Task 9: 复练间隔阶梯 | covers: spaced-repetition/复现间隔阶梯、同类非同题复现

**步骤 9.1** — 先写失败测试
`Packages/TrainingDomain/Tests/TrainingDomainTests/RepetitionSchedulerTests.swift`：

```swift
import Foundation
import Testing
@testable import TrainingDomain

@Suite("复练调度")
struct RepetitionSchedulerTests {
    private let scheduler = RepetitionScheduler()

    // GIVEN 某节点首次答错，此前无复练记录
    // THEN intervalDays 为 1，nextDueAt 为次日
    @Test("首次复练间隔为一天")
    func firstFailureSchedulesOneDayOut() throws {
        let failedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let schedule = try #require(scheduler.schedule(
            forNode: "turn-barrel",
            events: [TrainingFixture.event(nodeID: "turn-barrel", quality: .blunder, at: failedAt)]
        ))

        #expect(schedule.intervalDays == 1)
        #expect(schedule.nextDueAt == failedAt.addingTimeInterval(86_400))
    }

    // GIVEN intervalDays 为 3，到期复练得到 acceptable
    // THEN intervalDays 变为 7
    @Test("答对沿阶梯前进")
    func correctRepetitionAdvancesOneRung() throws {
        let schedule = try #require(scheduler.schedule(
            forNode: "turn-barrel",
            events: TrainingFixture.ladderEvents(reaching: 3, thenAnswering: .acceptable)
        ))
        #expect(schedule.intervalDays == 7)
    }

    // GIVEN intervalDays 为 7，到期复练得到 blunder
    // THEN intervalDays 变为 3
    @Test("答错退一级")
    func incorrectRepetitionFallsBackOneRung() throws {
        let schedule = try #require(scheduler.schedule(
            forNode: "turn-barrel",
            events: TrainingFixture.ladderEvents(reaching: 7, thenAnswering: .blunder)
        ))
        #expect(schedule.intervalDays == 3)
    }

    // 没有下限的话间隔会退到 0，同一题会在同一次会话里无限重复出现。
    @Test("最低一级答错仍为一天")
    func lowestRungNeverFallsBelowOneDay() throws {
        let schedule = try #require(scheduler.schedule(
            forNode: "turn-barrel",
            events: TrainingFixture.ladderEvents(reaching: 1, thenAnswering: .blunder)
        ))
        #expect(schedule.intervalDays == 1)
    }

    // GIVEN 昨天在 bet-sizing 的 s-101 上 blunder，同日 preflop-range 全对
    // THEN 存在 bet-sizing 复练项且题目不是 s-101，不存在 preflop-range 复练项
    @Test("隔日复练换题且不复练已答对的维度")
    func schedulesADifferentScenarioAndSkipsPassedNodes() throws {
        let plan = scheduler.dueRepetitions(
            events: TrainingFixture.yesterdayMixedEvents(),
            pack: TrainingFixture.pack(scenarioIDs: ["s-101", "s-102"]),
            now: TrainingFixture.today
        )

        let betSizing = try #require(plan.first { $0.nodeID == "bet-sizing" })
        #expect(betSizing.scenarioID != "s-101")
        #expect(plan.contains { $0.nodeID == "preflop-range" } == false)
    }

    // GIVEN bet-sizing 只有 s-101 一个场景且已答错
    // THEN 不出同一题，该维度复练挂起
    @Test("内容不足时挂起而不是重复出题")
    func suspendsRepetitionRatherThanRepeatingTheSameQuestion() throws {
        let plan = scheduler.dueRepetitions(
            events: TrainingFixture.yesterdayMixedEvents(),
            pack: TrainingFixture.pack(scenarioIDs: ["s-101"]),
            now: TrainingFixture.today
        )

        let betSizing = try #require(plan.first { $0.nodeID == "bet-sizing" })
        #expect(betSizing.scenarioID == nil)
        #expect(betSizing.isContentLimited)
    }
}
```

**步骤 9.2** — 运行确认失败。

**步骤 9.3** — 实现 `RepetitionScheduler.swift`。核心是对节点事件序列的折叠，
不持有任何状态：

```swift
/// Repetition state is folded from the event history rather than stored.
///
/// Persisting `nextDueAt` would add mutable state that has to answer how it
/// syncs, how it isolates across profiles, and who wins when two devices
/// disagree. M1B established that the profile is a deterministic reduction of
/// the complete event history; deriving the schedule the same way keeps that
/// property instead of opening an exception beside it.
public struct RepetitionScheduler: Sendable {
    static let ladder = [1, 3, 7, 14, 30]

    public func schedule(forNode nodeID: String, events: [TrainingEvent]) -> RepetitionSchedule? {
        let ordered = events.sorted { $0.occurredAt < $1.occurredAt }
        guard let firstFailure = ordered.first(where: { Self.isError($0.grade.quality) }) else {
            return nil
        }

        var rung = 0
        var dueAt = firstFailure.occurredAt.addingTimeInterval(86_400)

        for event in ordered where event.occurredAt >= dueAt {
            rung = Self.isError(event.grade.quality)
                ? max(0, rung - 1)
                : min(Self.ladder.count - 1, rung + 1)
            dueAt = event.occurredAt.addingTimeInterval(
                TimeInterval(Self.ladder[rung]) * 86_400
            )
        }

        return RepetitionSchedule(
            nodeID: nodeID,
            intervalDays: Self.ladder[rung],
            nextDueAt: dueAt,
            isContentLimited: false
        )
    }

    private static func isError(_ quality: DecisionQuality) -> Bool {
        quality == .improvable || quality == .blunder
    }
}
```

**步骤 9.4** — 运行至通过。

---

### Task 10: 五项掌握信号 | covers: adaptive-curriculum/节点掌握判定、local-learning-profile/能力树节点掌握信号

**步骤 10.1** — **先写正向测试并确认它失败**。这一步的顺序是本 Task 的要点：
若先写五条否定测试，`isMastered` 恒为 `false` 会让它们全绿，而缺陷不可见。

新建 `Packages/TrainingDomain/Tests/TrainingDomainTests/NodeMasteryTests.swift`：

```swift
import Testing
@testable import TrainingDomain

@Suite("节点掌握判定")
struct NodeMasteryTests {
    // GIVEN 20 次作答、最近 10 次全达标、verySure 全达标、2 次复练通过
    // WHEN 在 3 个未作答过的 scenario ID 上均达标
    // THEN mastered，且五项信号带实际值 20/20、10/10、2/2、3/3
    @Test("五项信号齐备时判定掌握")
    func marksMasteredWhenEverySignalHolds() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(),
            pack: MasteryFixture.pack
        )

        #expect(mastery.isMastered)
        #expect(mastery.signals.count == 5)
        #expect(mastery.signal(.sample).actual == 20)
        #expect(mastery.signal(.sample).required == 20)
        #expect(mastery.signal(.recentStability).actual == 10)
        #expect(mastery.signal(.repetition).actual == 2)
        #expect(mastery.signal(.transfer).actual == 3)
        #expect(mastery.signals.allSatisfy(\.satisfied))
    }

    @Test("样本不足不判定掌握")
    func withholdsMasteryWhenSampleIsShort() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(sampleCount: 4),
            pack: MasteryFixture.pack
        )
        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.sample).actual == 4)
        #expect(mastery.signal(.sample).satisfied == false)
        #expect(mastery.signal(.recentStability).satisfied)
    }

    @Test("近期稳定性不足不判定掌握")
    func withholdsMasteryWhenRecentStabilityIsShort() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(recentPassCount: 7),
            pack: MasteryFixture.pack
        )
        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.recentStability).actual == 7)
        #expect(mastery.signal(.recentStability).required == 9)
        #expect(mastery.signal(.sample).satisfied)
    }

    @Test("高信心错误阻止掌握")
    func withholdsMasteryOnAHighConfidenceError() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(includingHighConfidenceError: true),
            pack: MasteryFixture.pack
        )
        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.confidenceCalibration).satisfied == false)
    }

    @Test("复练未完成不判定掌握")
    func withholdsMasteryWhenRepetitionIsIncomplete() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(completedRepetitions: 1),
            pack: MasteryFixture.pack
        )
        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.repetition).actual == 1)
        #expect(mastery.signal(.repetition).required == 2)
    }

    @Test("迁移未通过不判定掌握")
    func withholdsMasteryWhenTransferFails() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.allSignalsSatisfied(transferPassCount: 2),
            pack: MasteryFixture.pack
        )
        #expect(mastery.isMastered == false)
        #expect(mastery.signal(.transfer).actual == 2)
        #expect(mastery.signal(.transfer).required == 3)
    }

    // 「查看未掌握原因」要求五项逐行可读，不是一个笼统结论。
    @Test("五项信号逐项可读")
    func exposesEverySignalWithItsValue() throws {
        let mastery = MasteryEvaluator().evaluate(
            nodeID: "turn-barrel",
            events: MasteryFixture.earlyProgress(),
            pack: MasteryFixture.pack
        )

        #expect(mastery.signals.map(\.kind) == [
            .sample, .recentStability, .confidenceCalibration, .repetition, .transfer,
        ])
        #expect(mastery.signal(.sample).actual == 4)
        #expect(mastery.signal(.recentStability).actual == 3)
        #expect(mastery.signal(.confidenceCalibration).satisfied)
        #expect(mastery.signal(.repetition).actual == 0)
        #expect(mastery.signal(.transfer).actual == 0)
    }
}
```

**步骤 10.2** — 运行。**必须先只写一个恒返回 `isMastered == false` 的骨架实现，
确认第一条正向测试失败、其余五条通过。** 看到这个结果本身就是证据：
它证明了这套否定测试单独无法约束实现。把这个观察写进提交信息。

**步骤 10.3** — 实现 `NodeMastery.swift`：

```swift
public struct MasterySignal: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case sample
        case recentStability
        case confidenceCalibration
        case repetition
        case transfer
    }

    public let kind: Kind
    public let actual: Int
    public let required: Int

    /// Every signal is a "reached at least N" comparison, so satisfaction is
    /// derived rather than stored. A separately stored flag could disagree
    /// with the numbers shown beside it, and the numbers are what the user
    /// reads to know how much further they have to go.
    public var satisfied: Bool { actual >= required }
}

public struct NodeMastery: Sendable, Equatable {
    public let nodeID: String
    /// Always five entries, in Kind.allCases order, so the UI can render them
    /// as a fixed table and tests can index them.
    public let signals: [MasterySignal]

    public var isMastered: Bool { signals.allSatisfy(\.satisfied) }

    public func signal(_ kind: MasterySignal.Kind) -> MasterySignal {
        // Force-unwrap is deliberate: an evaluator that omits a signal is a
        // programming error, and returning a placeholder would let the
        // omission reach the screen as a satisfied row.
        signals.first { $0.kind == kind }!
    }
}
```

再实现 `MasteryEvaluator`，阈值取
`sample=20`、`recentStability=9/10`、`confidenceCalibration` 为最近 10 次内所有
`verySure` 均非 `improvable`/`blunder`、`repetition=2`、`transfer=3`。
判定「达标」复用既有语义：`quality ∈ {excellent, acceptable}`，不另立阈值。

**步骤 10.4** — 全部七条通过：

```bash
swift test --package-path Packages/TrainingDomain --filter NodeMastery
```

---

### Task 11: 计划优先级、裁决顺序与入选原因 | covers: local-learning-profile/今日训练优先级

**步骤 11.1** — 先写失败测试，追加到既有的
`Packages/TrainingDomain/Tests/TrainingDomainTests/TrainingPlannerTests.swift`：

```swift
// GIVEN A 与 B 各项相同，A 复练已到期、B 未到期，且 A 的 catalog ID 排在 B 之后
// THEN A 排在 B 之前，且 priority 严格大于 B
// catalog ID 顺序刻意与期望结果相反：否则既有的 ID 字典序 tie-break
// 会让一个完全没有到期项的实现也通过。
@Test("到期复练排在未到期项目之前")
func dueRepetitionOutranksAnIdenticalItemThatIsNotDue() throws {
    let plan = TrainingPlanner().plan(PlannerFixture.tiedExcept(
        dueNodeCatalogID: "z-due",
        notDueNodeCatalogID: "a-not-due"
    ))

    #expect(plan.items[0].catalogID == "z-due")
    #expect(plan.items[0].priority > plan.items[1].priority)
}

// GIVEN A 有高信心错误但未到期，B 无高信心错误但已到期
// THEN A 排在 B 之前
@Test("高信心错误压过复练到期")
func highConfidenceErrorOutranksADueRepetition() throws {
    let plan = TrainingPlanner().plan(PlannerFixture.highConfidenceErrorVersusDue())
    #expect(plan.items[0].catalogID == PlannerFixture.highConfidenceErrorCatalogID)
}

// GIVEN 四个画像，各自只具备一种入选依据
// THEN 四个计划的首项原因依次为四个不同的枚举值
@Test("每个计划项给出被选中的原因")
func reportsWhyEachItemWasChosen() throws {
    #expect(TrainingPlanner().plan(PlannerFixture.onlyWeakness()).items[0].reason == .weakness)
    #expect(TrainingPlanner().plan(PlannerFixture.onlyHighConfidenceError()).items[0].reason == .highConfidenceError)
    #expect(TrainingPlanner().plan(PlannerFixture.onlyRepetitionDue()).items[0].reason == .repetitionDue)
    #expect(TrainingPlanner().plan(PlannerFixture.onlyPathProgress()).items[0].reason == .pathProgress)
}

// GIVEN 目标 5–10 分钟，候选充足
// THEN 总时长落在区间内，且再加任意一项都会超过上限
@Test("计划受可用时长约束")
func fillsTheWindowWithoutOverrunningIt() throws {
    let input = PlannerFixture.abundantCandidates()
    let plan = TrainingPlanner().plan(input)
    let total = plan.items.map(\.estimatedMinutes).reduce(0, +)

    #expect(total <= 10)
    #expect(total >= 5)
    let unselected = input.candidates.filter { candidate in
        plan.items.contains { $0.catalogID == candidate.catalogID } == false
    }
    for candidate in unselected {
        #expect(total + candidate.estimatedMinutes > 10, "计划没有填满窗口")
    }
}

// GIVEN 画像 A 中 bet-sizing 最弱、画像 B 中 preflop-range 最弱
// THEN 两者首项维度不同，且生成不需要用户先做选择
@Test("今日计划来自画像而非用户选择")
func derivesTheFirstItemFromTheProfile() throws {
    #expect(TrainingPlanner().plan(PlannerFixture.weakest("bet-sizing")).items[0].dimension == "bet-sizing")
    #expect(TrainingPlanner().plan(PlannerFixture.weakest("preflop-range")).items[0].dimension == "preflop-range")
}
```

**步骤 11.2** — 运行确认失败。

**步骤 11.3** — 实现。`PlanItemReason` 为公开枚举，裁决顺序按
弱项 → 高信心错误 → 距上次练习天数 → 复练到期 → 学习路径固定，写成显式的
比较链而不是加权和——加权和会让「哪一项压过哪一项」取决于系数取值，
无法与规格中声明的顺序对应。既有的 `高信心弱项优先` 与
「排序在相同输入下保持稳定」两条断言必须继续通过。

**步骤 11.4** — 全部通过：

```bash
swift test --package-path Packages/TrainingDomain
```

---

### Task 12: 诊断蓝图与进度 | covers: initial-diagnostic/跨维度初始诊断

**步骤 12.1** — 先写失败测试
`Packages/TrainingDomain/Tests/TrainingDomainTests/DiagnosticBlueprintTests.swift`：

```swift
import Testing
@testable import TrainingDomain

@Suite("初始诊断")
struct DiagnosticBlueprintTests {
    // GIVEN 蓝图声明维度全集 D
    // WHEN 从内容包选题
    // THEN 恰好 12 题，覆盖 ≥3 个座位、≥3 条街道、≥2 个筹码档
    @Test("选题覆盖蓝图声明的采样面")
    func drawsTwelveQuestionsCoveringEveryDeclaredAxis() throws {
        let questions = DiagnosticBlueprint.cash6MaxDefault.draw(from: DiagnosticFixture.pack)

        #expect(questions.count == 12)
        #expect(Set(questions.map(\.heroSeatOffsetFromButton)).count >= 3)
        #expect(Set(questions.map(\.street)).count >= 3)
        #expect(Set(questions.map(\.effectiveStack)).count >= 2)
        #expect(Set(questions.map(\.abilityDimension)) == DiagnosticBlueprint.cash6MaxDefault.dimensions)
    }

    // GIVEN 完成前 5 题后退出
    // THEN 进度 5/12，剩余 7 题与已完成的不相交
    @Test("中断后从断点继续")
    func resumesFromTheInterruptionPoint() throws {
        let session = DiagnosticSession(blueprint: .cash6MaxDefault, pack: DiagnosticFixture.pack)
        let answered = session.questions.prefix(5).map(\.scenarioID)
        let resumed = session.resuming(answeredScenarioIDs: Set(answered))

        #expect(resumed.completedCount == 5)
        #expect(resumed.totalCount == 12)
        #expect(resumed.remaining.count == 7)
        #expect(Set(resumed.remaining.map(\.scenarioID)).isDisjoint(with: Set(answered)))
    }

    // GIVEN 跳过诊断
    // THEN 计划非空，各项分属互不相同的维度
    @Test("跳过诊断时用均衡先验")
    func fallsBackToABalancedPriorWhenSkipped() throws {
        let plan = TrainingPlanner().plan(DiagnosticFixture.emptyProfileInput())

        #expect(plan.items.isEmpty == false)
        #expect(Set(plan.items.map(\.dimension)).count == plan.items.count)
    }

    // 收敛的可观测代理：三次 blunder 后该维度排到第一。
    @Test("作答后先验被真实历史压过")
    func realHistoryOverridesThePriorAfterRepeatedFailure() throws {
        let plan = TrainingPlanner().plan(
            DiagnosticFixture.afterThreeBlunders(in: "turn-barrel")
        )
        #expect(plan.items[0].dimension == "turn-barrel")
    }
}
```

**步骤 12.2** — 运行确认失败，实现 `DiagnosticBlueprint.swift`，运行至通过。

---

## Phase D — 内容本体

### Task 13: 生成核心集求解器导出 | covers: strategy-content-pipeline/求解器输出导入

**步骤 13.1** — 在 `Content/exports/core-6max-100bb.json` 写入 6-max 100BB 翻前
RFI 与 3bet 的求解器导出。位置用 `tableSize: 6` 与 `heroSeatOffsetFromButton`
表示，频率用 basis points 且每个节点严格求和到 10,000，EV 用 milli-BB。

**步骤 13.2** — 导入并确认通过全部校验：

```bash
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/core-6max-100bb.json \
  --content-version 2026.08.10 \
  --review-status unverifiedDraft \
  --output PokerCoach/Resources/CoreStrategyPack.json
```

此时状态是 `unverifiedDraft`——**未经审核之前不允许写 `reviewed`**，
Task 1 的校验器也会拒绝没有 `reviewedBy` 的 `reviewed` 包。

**步骤 13.3** — 生成范围表审核视图，供人工审核：

```bash
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/core-6max-100bb.json --print-range-tables \
  > Content/review/core-6max-100bb-ranges.txt
```

---

### Task 14: 人工审核闸门 | covers: versioned-strategy-content/审核状态约束

**这个 Task 不能由 agent 单独完成。**

**步骤 14.1** — 把 `Content/review/core-6max-100bb-ranges.txt` 交给仓库所有者，
按范围表逐张审核。

**步骤 14.2** — 所有者确认后，记录审核人与审核时间，重新导入定版：

```bash
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/core-6max-100bb.json \
  --content-version 2026.08.10 \
  --review-status reviewed \
  --reviewed-by "<所有者签字>" \
  --reviewed-at "<ISO8601 审核时间>" \
  --output PokerCoach/Resources/CoreStrategyPack.json
```

**步骤 14.3** — 记录黄金 checksum：

```bash
shasum -a 256 PokerCoach/Resources/CoreStrategyPack.json \
  | awk '{print $1}' > PokerCoach/Resources/CoreStrategyPack.sha256
```

**步骤 14.4** — 若所有者对某张范围表提出修改，改的是
`Content/exports/core-6max-100bb.json`，然后从步骤 14.2 重来。
**不允许直接编辑生成的策略包**——那会让包与导出不再对应，
Task 6 的确定性测试随即失效。

---

### Task 15: 生成未审核深度内容 | covers: versioned-strategy-content/审核状态约束

**步骤 15.1** — 在 `Content/exports/depth-6max-100bb.json` 写入翻后深度内容导出。

**步骤 15.2** — 导入为 `unverifiedDraft`：

```bash
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/depth-6max-100bb.json \
  --content-version 2026.08.10 \
  --review-status unverifiedDraft \
  --output PokerCoach/Resources/UnverifiedStrategyPack.json
```

**步骤 15.3** — 断言这个包**没有** `reviewedBy` 与 `reviewedAt`：

```bash
python3 -c "
import json,sys
m=json.load(open('PokerCoach/Resources/UnverifiedStrategyPack.json'))['manifest']
assert m['reviewStatus']=='unverifiedDraft', m['reviewStatus']
assert m.get('reviewedBy') is None and m.get('reviewedAt') is None, m
print('unverified pack carries no review attribution')
"
```

---
## Phase E — App 集成

### Task 16: 披露文案与可用性状态 | covers: versioned-strategy-content/审核状态约束

**步骤 16.1** — 先写失败测试
`PokerCoachTests/StrategyContentDisclosureTests.swift`：

```swift
import Testing
import StrategyContent
@testable import PokerCoach

@Suite("内容披露")
struct StrategyContentDisclosureTests {
    // GIVEN testFixture 内容
    // THEN 显示「开发演示数据」，且不描述为已审核建议
    @Test("开发内容展示")
    func labelsDevelopmentFixture() {
        #expect(
            StrategyContentAvailability.developmentFixtureAvailable.disclosureText
                == "开发演示数据"
        )
    }

    // GIVEN unverifiedDraft 内容
    // THEN 显示「未经策略审核」，且与开发数据文案不同
    @Test("未审核内容必须披露")
    func labelsUnverifiedDraft() {
        let unverified = StrategyContentAvailability.unverifiedContentAvailable.disclosureText
        #expect(unverified == "未经策略审核")
        // 两条文案必须不同：复用同一条横幅会让这个场景在
        // 一个只有单一提示的实现上也通过。
        #expect(unverified != StrategyContentAvailability.developmentFixtureAvailable.disclosureText)
    }

    // 未审核内容不阻断训练——dogfooding 的整个意义就在这里。
    @Test("未审核内容可以训练")
    func unverifiedContentStillAllowsTraining() {
        #expect(StrategyContentAvailability.unverifiedContentAvailable.canStartTraining)
    }

    // 披露由审核状态决定，不由 pack ID 决定。
    // 原实现硬编码比较开发包 ID，加入第三种内容后该判据不成立。
    @Test("披露由审核状态决定")
    func derivesDisclosureFromReviewStatus() {
        #expect(StrategyContentMetadata.disclosure(forReviewStatus: .testFixture) == "开发演示数据")
        #expect(StrategyContentMetadata.disclosure(forReviewStatus: .unverifiedDraft) == "未经策略审核")
        #expect(StrategyContentMetadata.disclosure(forReviewStatus: .reviewed) == nil)
    }
}
```

**步骤 16.2** — 运行确认失败：

```bash
xcodegen generate && xcodebuild test -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:PokerCoachTests/StrategyContentDisclosureTests 2>&1 | tail -20
```

**步骤 16.3** — 修改 `PokerCoach/App/StrategyContentMetadata.swift`：

```swift
import StrategyContent

enum StrategyContentMetadata {
    static let developmentDisclosure = "开发演示数据"
    static let unverifiedDisclosure = "未经策略审核"
    static let reviewedContentAvailableDisclosure = "已安装已审核策略内容"
    static let reviewedContentUnavailableDisclosure = "未安装已审核策略内容"

    /// Disclosure is a function of the review status, not of a hardcoded pack
    /// ID. The previous implementation compared against the development pack's
    /// ID, which stops distinguishing anything once a third kind of content
    /// ships.
    static func disclosure(forReviewStatus reviewStatus: ReviewStatus) -> String? {
        switch reviewStatus {
        case .testFixture: developmentDisclosure
        case .unverifiedDraft: unverifiedDisclosure
        case .reviewed, .retired: nil
        }
    }
}

enum StrategyContentAvailability: Equatable {
    case developmentFixtureAvailable
    case unverifiedContentAvailable
    case reviewedContentAvailable
    case reviewedContentUnavailable

    var canStartTraining: Bool {
        switch self {
        case .developmentFixtureAvailable, .unverifiedContentAvailable, .reviewedContentAvailable:
            true
        case .reviewedContentUnavailable:
            false
        }
    }

    var disclosureText: String {
        switch self {
        case .developmentFixtureAvailable: StrategyContentMetadata.developmentDisclosure
        case .unverifiedContentAvailable: StrategyContentMetadata.unverifiedDisclosure
        case .reviewedContentAvailable: StrategyContentMetadata.reviewedContentAvailableDisclosure
        case .reviewedContentUnavailable: StrategyContentMetadata.reviewedContentUnavailableDisclosure
        }
    }
}
```

**步骤 16.4** — 编译会在所有穷尽 switch 处报错。**逐个修，不要加 `default`**——
`default` 会让下一次新增状态时静默漏掉展示点，而编译器本可以指出来。

**步骤 16.5** — 全绿：

```bash
xcodebuild test -scheme PokerCoach -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:PokerCoachTests
```

---

### Task 17: 走通 reviewedContentAvailable | covers: strategy-content-pipeline/内容随包交付与可选更新

**步骤 17.1** — 先写失败测试
`PokerCoachTests/BundledContentTests.swift`：

```swift
import Testing
@testable import PokerCoach

@Suite("随包内容")
struct BundledContentTests {
    // GIVEN 设备从未联网、从未拉取内容
    // WHEN 加载随包内容
    // THEN 可用性为 reviewedContentAvailable，pack ID 为内置核心集，期间零网络请求
    @Test("首次离线启动使用内置内容")
    func loadsBundledCoreContentWithoutNetwork() throws {
        let recorder = RequestRecordingURLProtocol.install()
        defer { recorder.uninstall() }

        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()

        #expect(loaded.availability == .reviewedContentAvailable)
        #expect(loaded.pack.manifest.id == BundledContentLoader.corePackID)
        #expect(loaded.pack.manifest.reviewStatus == .reviewed)
        #expect(recorder.requestCount == 0)
    }

    // dogfooding 构建同时带 reviewed 与 unverifiedDraft，
    // 加载器要选出正确的那个并给出对应的披露状态。
    @Test("同时存在两种内容时选择审核状态更高的")
    func prefersReviewedOverUnverifiedWhenBothArePresent() throws {
        let loaded = try BundledContentLoader(
            bundle: BundleFixture.withCoreAndUnverifiedPacks()
        ).loadPreferredPack()

        #expect(loaded.availability == .reviewedContentAvailable)
    }

    @Test("只有未审核内容时状态为 unverifiedContentAvailable")
    func reportsUnverifiedAvailabilityWhenOnlyDraftContentIsPresent() throws {
        let loaded = try BundledContentLoader(
            bundle: BundleFixture.withUnverifiedPackOnly()
        ).loadPreferredPack()

        #expect(loaded.availability == .unverifiedContentAvailable)
        #expect(loaded.pack.manifest.reviewStatus == .unverifiedDraft)
    }
}
```

**步骤 17.2** — 运行确认失败，实现
`PokerCoach/Infrastructure/Content/BundledContentLoader.swift`。加载时必须走
`StrategyPackValidator`——随包内容不是可信输入，`.sha256` 与语义校验都要过。

**步骤 17.3** — 改 `AppDependencies.live()` 的 `#else` 分支：

```swift
#else
        let loaded = try BundledContentLoader(bundle: .main).loadPreferredPack()
        let dependencies = availableContent(
            eventStore: try syncTrackingEventStore(in: storageDirectory),
            strategyPack: loaded.pack,
            localIdentity: localIdentity,
            strategyContentAvailability: loaded.availability
        )
#endif
```

**步骤 17.4** — 运行至通过。这一步之后，`reviewedContentAvailable` 第一次在
生产代码中被构造——把这个事实写进提交信息。

---

### Task 18: 内容更新机制 | covers: strategy-content-pipeline/内容随包交付与可选更新

**步骤 18.1** — 先写失败测试
`PokerCoachTests/ContentUpdateCoordinatorTests.swift`，五条场景一一对应：

```swift
import Testing
@testable import PokerCoach

@Suite("内容更新")
struct ContentUpdateCoordinatorTests {
    // 正向路径先写。没有它，一个 apply() 体为空的实现能通过
    // 下面全部四条否定测试。
    @Test("校验通过且版本更高的更新包被采用")
    func adoptsAVerifiedHigherVersion() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: ContentFixture.pack(contentVersion: "2026.08.06"),
            source: StubContentUpdateSource(offering: ContentFixture.verifiedOffer(contentVersion: "2026.09.01"))
        )

        let outcome = try await coordinator.checkForUpdate()

        #expect(outcome == .adopted(contentVersion: "2026.09.01"))
        #expect(coordinator.currentPack.manifest.contentVersion == "2026.09.01")
    }

    @Test("更新包 checksum 不匹配")
    func rejectsAPackWhoseChecksumDoesNotMatch() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: ContentFixture.pack(contentVersion: "2026.08.06"),
            source: StubContentUpdateSource(offering: ContentFixture.corruptedOffer(contentVersion: "2026.09.01"))
        )

        let outcome = try await coordinator.checkForUpdate()

        #expect(outcome == .rejected(.checksumMismatch))
        #expect(coordinator.currentPack.manifest.contentVersion == "2026.08.06")
    }

    @Test("更新包内容版本等于当前")
    func ignoresAnEqualVersion() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: ContentFixture.pack(contentVersion: "2026.08.06"),
            source: StubContentUpdateSource(offering: ContentFixture.verifiedOffer(contentVersion: "2026.08.06"))
        )
        #expect(try await coordinator.checkForUpdate() == .ignored(.notNewer))
        #expect(coordinator.currentPack.manifest.contentVersion == "2026.08.06")
    }

    @Test("更新包内容版本低于当前")
    func ignoresAnOlderVersion() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: ContentFixture.pack(contentVersion: "2026.09.01"),
            source: StubContentUpdateSource(offering: ContentFixture.verifiedOffer(contentVersion: "2026.08.06"))
        )
        #expect(try await coordinator.checkForUpdate() == .ignored(.notNewer))
        #expect(coordinator.currentPack.manifest.contentVersion == "2026.09.01")
    }

    // 拒绝更新不能退化成「没有内容」——训练必须继续可用。
    @Test("拒绝更新后训练不中断")
    func keepsTrainingAvailableAfterARejectedUpdate() async throws {
        let coordinator = ContentUpdateCoordinator(
            current: ContentFixture.pack(contentVersion: "2026.08.06"),
            source: StubContentUpdateSource(offering: ContentFixture.corruptedOffer(contentVersion: "2026.09.01"))
        )
        _ = try await coordinator.checkForUpdate()
        #expect(coordinator.availability.canStartTraining)
    }
}
```

**步骤 18.2** — 运行确认失败。

**步骤 18.3** — 实现 `ContentUpdateSource.swift` 与
`ContentUpdateCoordinator.swift`。协议保持最小，只描述「取一个候选包及其声明的
checksum」；HTTPS 实现不在本次范围，本次只有测试用实现：

```swift
/// Where a candidate content pack comes from.
///
/// M1C ships bundled content only; the HTTPS endpoint that would back a real
/// implementation is deliberately out of scope, because it has nothing to
/// serve until a second content version exists. The client-side rules --
/// verify the checksum, refuse anything not strictly newer, keep serving the
/// current pack on refusal -- are implemented and tested here so that adding
/// the endpoint later is an increment rather than a redesign.
protocol ContentUpdateSource: Sendable {
    func fetchCandidate() async throws -> ContentUpdateOffer?
}
```

版本比较**不用字符串比较**：`2026.9.1` 与 `2026.09.01` 在字典序下不等价。解析为
数值组件后比较，无法解析即视为不可采用。

**步骤 18.4** — 运行至通过。

---

### Task 19: 能力树界面 | covers: adaptive-curriculum/现金局能力树、local-learning-profile/能力树节点掌握信号

**步骤 19.1** — 先写失败的 ViewModel 测试
`PokerCoachTests/LearnViewModelTests.swift`：

```swift
// GIVEN 包中映射到 turn-barrel 的场景有 7 个，river-bluff-catch 前置为 turn-barrel
// THEN 树上两个节点的场景数与前置关系都正确
@Test("浏览能力树")
func presentsNodesWithCountsAndPrerequisites() throws {
    let viewModel = LearnViewModel(pack: LearnFixture.pack, events: [])
    viewModel.refresh()

    let turnBarrel = try #require(viewModel.nodes.first { $0.id == "turn-barrel" })
    #expect(turnBarrel.practisableScenarioCount == 7)

    let river = try #require(viewModel.nodes.first { $0.id == "river-bluff-catch" })
    #expect(river.prerequisiteTitles == ["转牌持续下注"])
}

// GIVEN river-bluff-catch 在当前包中无场景
// THEN 标记暂无内容、不进计划、不计入进度分母
@Test("内容缺失的节点")
func marksEmptyNodesAndExcludesThemFromProgress() throws {
    let viewModel = LearnViewModel(pack: LearnFixture.packMissingRiverContent, events: [])
    viewModel.refresh()

    let river = try #require(viewModel.nodes.first { $0.id == "river-bluff-catch" })
    #expect(river.isContentUnavailable)
    #expect(viewModel.masteryProgressDenominator == viewModel.nodes.count - 1)
    #expect(viewModel.plannableNodeIDs.contains("river-bluff-catch") == false)
}

// GIVEN 某节点未掌握
// THEN 五项信号逐行可读，不是一个笼统结论
@Test("查看未掌握原因")
func listsEveryMasterySignalRatherThanAVerdict() throws {
    let viewModel = LearnViewModel(pack: LearnFixture.pack, events: LearnFixture.earlyProgressEvents)
    viewModel.refresh()

    let detail = try #require(viewModel.detail(forNode: "turn-barrel"))
    #expect(detail.signalRows.count == 5)
    #expect(detail.signalRows[0].label == "样本")
    #expect(detail.signalRows[0].value == "4/20")
    #expect(detail.signalRows[0].satisfied == false)
    #expect(detail.signalRows[2].label == "信心校准")
    #expect(detail.signalRows[2].satisfied)
}
```

**步骤 19.2** — 运行确认失败，实现 `LearnViewModel` 与视图。ViewModel 只组合
`MasteryEvaluator` 与 `CurriculumResolver` 的结果，**不自行计算任何掌握判定**——
`docs/architecture/layering.md:23` 禁止 ViewModel 计算领域真值。

**步骤 19.3** — 补一条「用户直接选择具体节点」的测试：从树进入不在今日计划的
节点，训练照常开始，产生的事件进入归约。

**步骤 19.4** — UI 测试各一条（iPhone 与 iPad）。iPad 走 NavigationSplitView，
节点渲染为 `Cell` 内的 `StaticText`，沿用既有 UI 测试的布局感知写法，
不要假设 TabBar。

---

### Task 20: 今日与复盘接入 | covers: initial-diagnostic、local-learning-profile/今日与复盘使用真实历史、versioned-strategy-content/内容版本不可原地修改

**步骤 20.1** — 先写失败测试，追加到 `PokerCoachTests/TodayViewModelTests.swift`
与 `ReviewViewModelTests.swift`：

```swift
// GIVEN 用户完成一个 bet-sizing 场景
// THEN 今日与复盘都反映该事件，且重新生成的计划首项为 bet-sizing
@Test("决策完成后刷新")
func reflectsTheNewEventInBothSurfaces() async throws {
    let harness = TodayHarness()
    try await harness.completeDecision(dimension: "bet-sizing", quality: .blunder)

    #expect(harness.today.sampleCount(for: "bet-sizing") == 1)
    #expect(harness.today.planItems[0].dimension == "bet-sizing")
    #expect(harness.review.latestEntry?.abilityDimension == "bet-sizing")
}

// GIVEN 已有 2026.08.06 的事件，安装 2026.09.01 的包
// THEN 事件记录的版本不变，复盘对该条显示 2026.08.06
@Test("内容升级后历史仍可追溯")
func keepsHistoricalContentVersionAfterUpgrade() async throws {
    let harness = TodayHarness(contentVersion: "2026.08.06")
    try await harness.completeDecision(dimension: "bet-sizing", quality: .acceptable)
    try await harness.installContent(version: "2026.09.01")

    let entry = try #require(harness.review.latestEntry)
    #expect(entry.strategyContentVersion == "2026.08.06")
    #expect(harness.review.displayedContentVersion(for: entry) == "2026.08.06")
}

// 诊断三条：完成、跳过、中断恢复，在 ViewModel 层验证
@Test("跳过诊断后今日计划仍可生成")
func producesAPlanAfterSkippingTheDiagnostic() async throws {
    let harness = TodayHarness()
    harness.today.skipDiagnostic()

    #expect(harness.today.planItems.isEmpty == false)
    #expect(Set(harness.today.planItems.map(\.dimension)).count == harness.today.planItems.count)
    #expect(harness.today.showsDiagnosticEntry)
}
```

**步骤 20.2** — 运行确认失败，实现，运行至通过。每个计划项在界面上显示其
`PlanItemReason` 对应的中文说明。

---

## Phase F — 构建类别与门禁

### Task 21: 三种构建类别 | covers: m1a-release-safety/开发策略数据隔离

**步骤 21.1** — 新建 `Config/Dogfood.xcconfig`：

```
#include "Release.xcconfig"

PC_CONTENT_CHANNEL = dogfood
// Release 排除了未审核内容；dogfooding 需要它，所以在这里覆盖回来，
// 只保留开发夹具的排除。
EXCLUDED_SOURCE_FILE_NAMES = DevStrategyPack.json
```

**步骤 21.2** — 修改 `Config/Debug.xcconfig` 与 `Config/Release.xcconfig`：

```
# Debug.xcconfig
PC_CONTENT_CHANNEL = debug

# Release.xcconfig
PC_CONTENT_CHANNEL = store
EXCLUDED_SOURCE_FILE_NAMES = DevStrategyPack.json UnverifiedStrategyPack.json
```

**步骤 21.3** — 修改 `project.yml`：`configs` 增加 `Dogfood: release`；
`targets.PokerCoach.configFiles` 增加 `Dogfood: Config/Dogfood.xcconfig`；
`info.properties` 增加 `PCContentChannel: $(PC_CONTENT_CHANNEL)`。

**步骤 21.4** — 三个配置各构建一次，确认产物内容符合预期：

```bash
xcodegen generate
for config in Debug Dogfood Release; do
  xcodebuild -scheme PokerCoach -configuration "$config" \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath ".build/$config" build
done
```

**步骤 21.5** — 逐个断言随包内容与频道标记：

```bash
for config in Debug Dogfood Release; do
  app=$(find ".build/$config/Build/Products" -name PokerCoach.app -maxdepth 3 | head -1)
  channel=$(plutil -extract PCContentChannel raw "$app/Info.plist")
  echo "$config channel=$channel packs=$(ls "$app" | grep -c 'StrategyPack.json')"
done
```

预期：`Debug channel=debug`（3 个包）、`Dogfood channel=dogfood`（2 个）、
`Release channel=store`（1 个）。

---

### Task 22: 内容审核状态发布门禁 | covers: m1a-release-safety/开发策略数据隔离

**步骤 22.1** — 新建 `scripts/check-release-content.sh`。判定依据取自构建产物
自身的 `PCContentChannel`，**不接受命令行指定频道**：

```bash
#!/usr/bin/env bash
#
# Refuses content whose review status does not match the build's channel.
#
# The channel is read out of the built Info.plist rather than passed in. A gate
# that depends on its caller remembering a --channel flag is a gate that passes
# when the flag is forgotten, which is the same failure mode as a grep whose
# pattern can never match: green, and proving nothing.

set -euo pipefail

app_path="${1:?usage: $0 <path to PokerCoach.app>}"

channel="$(plutil -extract PCContentChannel raw "$app_path/Info.plist" 2>/dev/null || true)"
if [[ -z "$channel" ]]; then
  echo "FAIL: $app_path/Info.plist has no PCContentChannel" >&2
  exit 1
fi

case "$channel" in
  debug)   allowed=("testFixture" "unverifiedDraft" "reviewed") ;;
  dogfood) allowed=("unverifiedDraft" "reviewed") ;;
  store)   allowed=("reviewed") ;;
  *)       echo "FAIL: unknown PCContentChannel '$channel'" >&2; exit 1 ;;
esac

violations=0
found=0
while IFS= read -r pack; do
  found=$((found + 1))
  pack_id="$(plutil -extract manifest.id raw "$pack")"
  status="$(plutil -extract manifest.reviewStatus raw "$pack")"
  if [[ ! " ${allowed[*]} " == *" $status "* ]]; then
    echo "FAIL: channel '$channel' forbids '$status' but $pack_id carries it" >&2
    violations=$((violations + 1))
  fi
done < <(find "$app_path" -maxdepth 1 -name '*StrategyPack.json')

if [[ "$found" -eq 0 ]]; then
  echo "FAIL: $app_path bundles no strategy pack at all" >&2
  exit 1
fi
if [[ "$violations" -gt 0 ]]; then
  exit 1
fi

echo "OK: channel '$channel' with $found pack(s), all within {${allowed[*]}}"
```

**步骤 22.2** — 三个真实产物各跑一次，全部应通过：

```bash
for config in Debug Dogfood Release; do
  app=$(find ".build/$config/Build/Products" -name PokerCoach.app -maxdepth 3 | head -1)
  bash scripts/check-release-content.sh "$app"
done
```

**步骤 22.3** — **证明门禁会失败。** 只有通过路径的门禁与恒真无异：

```bash
app=$(find ".build/Release/Build/Products" -name PokerCoach.app -maxdepth 3 | head -1)
probe=$(mktemp -d)/PokerCoach.app
cp -R "$app" "$probe"
cp PokerCoach/Resources/UnverifiedStrategyPack.json "$probe/"
if bash scripts/check-release-content.sh "$probe"; then
  echo "GATE IS BROKEN: store channel accepted unverifiedDraft" >&2; exit 1
fi
echo "gate correctly rejects unverified content on the store channel"
```

**步骤 22.4** — 再证明缺少频道标记时门禁失败而不是放行：

```bash
probe2=$(mktemp -d)/PokerCoach.app
cp -R "$app" "$probe2"
plutil -remove PCContentChannel "$probe2/Info.plist"
if bash scripts/check-release-content.sh "$probe2"; then
  echo "GATE IS BROKEN: missing channel defaulted to pass" >&2; exit 1
fi
echo "gate correctly fails closed on a missing channel"
```

---

### Task 23: 一键验证 | covers: m1a-release-safety/一键验证

**步骤 23.1** — 新建 `scripts/verify-m1c.sh`，串起：三个领域包的测试、
`StrategyTooling` 的测试（含跨进程确定性）、App 单元测试、iPhone 与 iPad UI 测试、
三个配置的构建与 `check-release-content.sh`、正反两条门禁探针、
`Contracts/training-event-upload-v1.sha256` 未变更断言。

**步骤 23.2** — 断言事件契约未被本次改动波及：

```bash
git diff --quiet HEAD -- Contracts/ \
  || { echo "FAIL: M1C must not change the frozen event contract" >&2; exit 1; }
shasum -a 256 -c Contracts/training-event-upload-v1.sha256
```

**步骤 23.3** — 确认既有里程碑仍然成立：

```bash
bash scripts/verify-m1a.sh
bash scripts/verify-m1b.sh
bash scripts/verify-m1c.sh
```

**步骤 23.4** — 更新 `docs/standards/strategy-content.md`：审核状态表增加
`unverifiedDraft` 行，「Release 可用」一列拆为「dogfooding 可用」与「商店发布可用」，
必需元数据增加 `reviewedBy`，展示规则增加 `unverifiedDraft`。同时订正
`docs/architecture/components.md:40` 中「内容分发」为 M1B 已实现的错误说法。

---

## Self-Review Checklist

- [ ] **Capability 追溯表完整**：proposal 的 21 个 Requirement、58 个 Scenario 都有对应 Task
- [ ] 每个 Task 2–5 分钟一步，一步一个动作
- [ ] 无 TBD / TODO / 「类似 Task N」/「适当处理」
- [ ] 后续 Task 引用的类型名与前序 Task 的定义一致
- [ ] 每条测试都先看到失败再实现，掌握判定的正向测试尤其要单独确认
- [ ] 门禁既有通过路径也有失败路径，且失败路径被真实触发过
- [ ] `Contracts/` 未被改动

## 下一步

执行 `/harness-apply curriculum-m1c-adaptive-cash-20260810-01`
