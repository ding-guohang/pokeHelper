---
name: poker-coach-m1a-cash-coach-20260806-01
status: planned
---

# M1A Offline Cash Coach Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iPhone/iPad vertical slice that loads a versioned 6-max 100BB cash-game scenario, accepts a legal decision and confidence rating, shows professional EV/frequency feedback, records a local training event, and surfaces the result in Today and Review.

**Architecture:** Use XcodeGen to define one SwiftUI application and three focused local Swift packages: `PokerCore` owns exact poker values and legal decisions, `StrategyContent` owns immutable versioned strategy packs, and `TrainingDomain` owns grading, events, ability reduction, and daily planning. The app depends on protocols and presentation models, while an append-only local event store preserves the same event shape that M1B will synchronize to the independent Go backend.

**Tech Stack:** Xcode 26.2, Swift 6.2.3 with strict concurrency, SwiftUI, Foundation, Swift Testing for packages, XCTest/XCUITest for the app, XcodeGen, JSON strategy fixtures.

## Global Constraints

- Product UI is Simplified Chinese first and must run natively on both iPhone and iPad.
- Deployment targets are iOS 18.0 and iPadOS 18.0.
- All play uses virtual chips; no real-money integration, multiplayer cash game, social feed, or leaderboard is permitted.
- The initial game is no-limit hold'em, online-style 6-max cash, 100BB effective stacks.
- Poker amounts use integer centi-big-blinds and EV uses integer milli-big-blinds; floating-point values are presentation-only.
- Strategy frequencies use integer basis points totaling exactly 10,000 per decision node.
- Strategy truth comes from versioned structured content; generated language never invents actions, frequencies, EV, ranges, or assumptions.
- Multiple actions with close EV must remain acceptable; the UI must not force a false unique answer.
- Decision quality is independent of the eventual runout and pot result.
- Training events are immutable and append-only. Duplicate event IDs must not create duplicate history.
- Development strategy fixtures must be visibly labeled `开发演示数据` and excluded from Release resources.
- Swift strict-concurrency warnings are treated as errors in project-owned code.
- M1A is not the complete M1 milestone; independent identity and synchronization remain required in M1B.

---

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| adaptive-native-shell | 四个核心入口 | iPhone 紧凑导航 | Task 8, 12 |
| adaptive-native-shell | 四个核心入口 | iPad 多栏导航 | Task 8, 12 |
| adaptive-native-shell | 原生平台支持 | 两种设备构建 | Task 1, 8, 13 |
| cash-decision-domain | 精确扑克值 | 精确金额运算 | Task 2 |
| cash-decision-domain | 稳定牌面表示 | 合法牌往返 | Task 2 |
| cash-decision-domain | 稳定牌面表示 | 非法牌拒绝 | Task 2 |
| cash-decision-domain | 合法行动过滤 | 未面对下注 | Task 3 |
| cash-decision-domain | 合法行动过滤 | 面对下注 | Task 3 |
| cash-decision-domain | 稳定行动 JSON | 带金额行动 | Task 3 |
| cash-decision-domain | 稳定行动 JSON | 行动字段不匹配 | Task 3 |
| versioned-strategy-content | 策略包来源可追溯 | 合法策略包加载 | Task 4 |
| versioned-strategy-content | 策略包来源可追溯 | checksum 不匹配 | Task 4 |
| versioned-strategy-content | 决策节点语义校验 | 频率总和错误 | Task 4 |
| versioned-strategy-content | 决策节点语义校验 | 非法行动进入策略 | Task 4 |
| versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核时间 | Task 4 |
| versioned-strategy-content | 审核状态约束 | 开发内容展示 | Task 10, 12 |
| explainable-decision-training | 行动与信心共同提交 | 提交信息不完整 | Task 9 |
| explainable-decision-training | 行动与信心共同提交 | 合法提交 | Task 9 |
| explainable-decision-training | 可解释 EV 评分 | 最高 EV 行动 | Task 5 |
| explainable-decision-training | 可解释 EV 评分 | 接近 EV 的混合行动 | Task 5, 10 |
| explainable-decision-training | 可解释 EV 评分 | 策略节点外行动 | Task 5 |
| explainable-decision-training | 评分与结果无关 | 相同决策不同后续结果 | Task 5, 9 |
| explainable-decision-training | 专业反馈层级 | iPhone 专业反馈 | Task 10, 12 |
| explainable-decision-training | 专业反馈层级 | iPad 专业反馈 | Task 10, 12 |
| explainable-decision-training | 专业反馈层级 | 剥削条件缺失 | Task 10 |
| local-learning-profile | 不可变本地训练事件 | 首次追加 | Task 6 |
| local-learning-profile | 不可变本地训练事件 | 重复事件 | Task 6 |
| local-learning-profile | 不可变本地训练事件 | 损坏事件文件 | Task 6 |
| local-learning-profile | 能力画像归约 | 高信心错误 | Task 7 |
| local-learning-profile | 今日训练优先级 | 高信心弱项优先 | Task 7 |
| local-learning-profile | 今日与复盘使用真实历史 | 决策完成后刷新 | Task 11, 12 |
| m1a-release-safety | 开发策略数据隔离 | Debug 训练 | Task 12 |
| m1a-release-safety | 开发策略数据隔离 | Release 构建 | Task 12, 13 |
| m1a-release-safety | 一键验证 | 从干净检出验证 | Task 13 |

测试代码中的 arrange、act、assert 分别对应表中 Scenario 的 GIVEN、WHEN、THEN；每个测试名称使用 Scenario 的可观察行为命名。

---

## File and module map

### Project configuration

- `project.yml` — XcodeGen source of truth for the app and test targets.
- `Config/Shared.xcconfig` — bundle, deployment, language, and strict-concurrency settings.
- `Config/Debug.xcconfig` — debug-only strategy fixture flag.
- `Config/Release.xcconfig` — release settings that disable development fixtures.

### PokerCore package

- `Packages/PokerCore/Package.swift` — package manifest.
- `Packages/PokerCore/Sources/PokerCore/Card.swift` — rank, suit, and card value types.
- `Packages/PokerCore/Sources/PokerCore/Amounts.swift` — exact `BBAmount` and `EVAmount` types.
- `Packages/PokerCore/Sources/PokerCore/DecisionAction.swift` — fold/check/call/bet/raise/all-in actions.
- `Packages/PokerCore/Sources/PokerCore/BettingDecisionContext.swift` — legal-action calculation for a stored decision node.
- `Packages/PokerCore/Tests/PokerCoreTests/*.swift` — value and legal-action tests.

### StrategyContent package

- `Packages/StrategyContent/Package.swift` — package manifest with local `PokerCore` dependency.
- `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift` — manifest, scenario, option, range-cell, and assumption models.
- `Packages/StrategyContent/Sources/StrategyContent/StrategyPackLoader.swift` — decoding and checksum entry point.
- `Packages/StrategyContent/Sources/StrategyContent/StrategyPackValidator.swift` — semantic validation.
- `Packages/StrategyContent/Tests/StrategyContentTests/*.swift` — decoder and invalid-pack fixtures.

### TrainingDomain package

- `Packages/TrainingDomain/Package.swift` — package manifest with local package dependencies.
- `Packages/TrainingDomain/Sources/TrainingDomain/DecisionScorer.swift` — deterministic EV-loss grading.
- `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEvent.swift` — immutable sync-ready event contract.
- `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEventStore.swift` — store protocol.
- `Packages/TrainingDomain/Sources/TrainingDomain/FileTrainingEventStore.swift` — append-only JSON-lines actor.
- `Packages/TrainingDomain/Sources/TrainingDomain/PlayerModel.swift` — ability dimensions and reducer.
- `Packages/TrainingDomain/Sources/TrainingDomain/TrainingPlanner.swift` — deterministic daily-plan selection.
- `Packages/TrainingDomain/Tests/TrainingDomainTests/*.swift` — grading, store, reducer, and planner tests.

### SwiftUI application

- `PokerCoach/App/PokerCoachApp.swift` — application entry point.
- `PokerCoach/App/AppDependencies.swift` — dependency composition.
- `PokerCoach/App/Root/AdaptiveRootView.swift` — iPhone tab bar and iPad sidebar switching.
- `PokerCoach/Features/Today/*` — daily plan and coach observation.
- `PokerCoach/Features/Learn/*` — M1A cash-path preview.
- `PokerCoach/Features/Train/*` — decision state machine and table UI.
- `PokerCoach/Features/Feedback/*` — professional feedback presentation.
- `PokerCoach/Features/Review/*` — event-derived ability summary.
- `PokerCoach/Shared/*` — reusable card, amount, badge, and loading components.
- `PokerCoach/Resources/zh-Hans.lproj/Localizable.strings` — Chinese copy.
- `PokerCoach/Resources/DevStrategyPack.json` — debug-only, visibly unreviewed fixture.
- `PokerCoachTests/*` — application model tests.
- `PokerCoachUITests/*` — iPhone/iPad happy-path UI tests.
- `scripts/verify-m1a.sh` — one-command package and app verification.

---

### Task 1: Scaffold the generated Xcode project and package boundaries | covers: adaptive-native-shell/原生平台支持, m1a-release-safety/一键验证

**Files:**
- Create: `project.yml`
- Create: `Config/Shared.xcconfig`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Release.xcconfig`
- Create: `scripts/check-project-shape.sh`
- Create: `PokerCoach/App/PokerCoachApp.swift`
- Create: `PokerCoach/App/Root/AdaptiveRootView.swift`
- Create: `Packages/PokerCore/Package.swift`
- Create: `Packages/StrategyContent/Package.swift`
- Create: `Packages/TrainingDomain/Package.swift`

**Interfaces:**
- Produces: Xcode scheme `PokerCoach`; local Swift modules `PokerCore`, `StrategyContent`, and `TrainingDomain`.
- Produces: compile-time flag `DEVELOPMENT_STRATEGY_FIXTURES` in Debug only.

- [x] **Step 1: Write the project-shape assertion**

Create `scripts/check-project-shape.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

test -f project.yml
test -f Config/Shared.xcconfig
test -f Packages/PokerCore/Package.swift
test -f Packages/StrategyContent/Package.swift
test -f Packages/TrainingDomain/Package.swift
test -f PokerCoach/App/PokerCoachApp.swift
```

- [x] **Step 2: Run the shape check and verify it fails**

Run: `bash scripts/check-project-shape.sh`

Expected: non-zero exit because `project.yml` and source files do not exist.

- [x] **Step 3: Define the packages and application**

Use this project skeleton in `project.yml`:

```yaml
name: PokerCoach
options:
  bundleIdPrefix: com.porkhelper
configs:
  Debug: debug
  Release: release
packages:
  PokerCore:
    path: Packages/PokerCore
  StrategyContent:
    path: Packages/StrategyContent
  TrainingDomain:
    path: Packages/TrainingDomain
targets:
  PokerCoach:
    type: application
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - PokerCoach
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
    dependencies:
      - package: PokerCore
      - package: StrategyContent
      - package: TrainingDomain
    info:
      path: PokerCoach/Info.plist
      properties:
        CFBundleDisplayName: 手牌教练
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
  PokerCoachTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "18.0"
    sources: [PokerCoachTests]
    dependencies:
      - target: PokerCoach
  PokerCoachUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "18.0"
    sources: [PokerCoachUITests]
    dependencies:
      - target: PokerCoach
schemes:
  PokerCoach:
    build:
      targets:
        PokerCoach: all
    test:
      targets:
        - PokerCoachTests
        - PokerCoachUITests
```

Set `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, and `DEVELOPMENT_LANGUAGE = zh-Hans` in `Config/Shared.xcconfig`. Include `Shared.xcconfig` from Debug and Release; define `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DEBUG DEVELOPMENT_STRATEGY_FIXTURES` only in Debug. Set `EXCLUDED_SOURCE_FILE_NAMES = DevStrategyPack.json` in `Config/Release.xcconfig`.

Each package manifest must expose one library product, use Swift tools 6.0, and declare `.iOS(.v18)` plus `.macOS(.v15)` so package tests run without a simulator. `StrategyContent` depends on `PokerCore`; `TrainingDomain` depends on both packages.

Create an app entry point that renders a temporary `AdaptiveRootView` containing `Text("手牌教练")`. Do not add feature behavior in this task.

- [x] **Step 4: Generate and compile the skeleton**

Run:

```bash
bash scripts/check-project-shape.sh
xcodegen generate
swift test --package-path Packages/PokerCore
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/TrainingDomain
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach -destination 'generic/platform=iOS Simulator'
```

Expected: all commands exit 0; each empty package reports a successful build.

- [x] **Step 5: Commit**

```bash
git add project.yml Config PokerCoach Packages scripts/check-project-shape.sh
git commit -m "build: scaffold native poker coach modules"
```

---

### Task 2: Add exact poker value types | covers: cash-decision-domain/精确扑克值, cash-decision-domain/稳定牌面表示

**Files:**
- Create: `Packages/PokerCore/Sources/PokerCore/Card.swift`
- Create: `Packages/PokerCore/Sources/PokerCore/Amounts.swift`
- Create: `Packages/PokerCore/Tests/PokerCoreTests/CardTests.swift`
- Create: `Packages/PokerCore/Tests/PokerCoreTests/AmountTests.swift`

**Interfaces:**
- Produces: `Suit`, `Rank`, `Card`.
- Produces: `BBAmount(centiBB:)`, `EVAmount(milliBB:)`.
- Produces: exact comparison and arithmetic used by every later domain module.

- [x] **Step 1: Write failing value tests**

```swift
import Testing
@testable import PokerCore

@Test func cardCodeRoundTrips() throws {
    let card = try #require(Card(code: "As"))
    #expect(card.rank == .ace)
    #expect(card.suit == .spades)
    #expect(card.code == "As")
    #expect(Card(code: "1x") == nil)
}

@Test func exactAmountsAvoidFloatingPointChips() {
    #expect(BBAmount(centiBB: 650) + BBAmount(centiBB: 325) == BBAmount(centiBB: 975))
    #expect(EVAmount(milliBB: 180) - EVAmount(milliBB: 25) == EVAmount(milliBB: 155))
}
```

- [x] **Step 2: Run the tests and verify missing symbols**

Run: `swift test --package-path Packages/PokerCore`

Expected: compile failure for missing `Card`, `BBAmount`, and `EVAmount`.

- [x] **Step 3: Implement the exact value API**

Define:

```swift
public enum Suit: String, CaseIterable, Codable, Sendable {
    case clubs = "c", diamonds = "d", hearts = "h", spades = "s"
}

public enum Rank: String, CaseIterable, Codable, Sendable {
    case two = "2", three = "3", four = "4", five = "5", six = "6"
    case seven = "7", eight = "8", nine = "9", ten = "T"
    case jack = "J", queen = "Q", king = "K", ace = "A"
}

public struct Card: Hashable, Codable, Sendable {
    public let rank: Rank
    public let suit: Suit
    public init(rank: Rank, suit: Suit)
    public init?(code: String)
    public var code: String { rank.rawValue + suit.rawValue }
}

public struct BBAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int)
    public init(centiBB: Int)
    public var centiBB: Int { rawValue }
}

public struct EVAmount: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int)
    public init(milliBB: Int)
    public var milliBB: Int { rawValue }
}
```

Reject negative `BBAmount` values with a precondition. Allow negative `EVAmount` because actions may have negative expected value. Implement only exact integer arithmetic required by the tests.

- [x] **Step 4: Run package tests**

Run: `swift test --package-path Packages/PokerCore`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Packages/PokerCore
git commit -m "feat: add exact poker card and amount types"
```

---

### Task 3: Model legal actions for a stored cash-game decision | covers: cash-decision-domain/合法行动过滤, cash-decision-domain/稳定行动 JSON

**Files:**
- Create: `Packages/PokerCore/Sources/PokerCore/DecisionAction.swift`
- Create: `Packages/PokerCore/Sources/PokerCore/BettingDecisionContext.swift`
- Create: `Packages/PokerCore/Tests/PokerCoreTests/BettingDecisionContextTests.swift`

**Interfaces:**
- Produces: `DecisionAction`.
- Produces: `BettingDecisionContext.legalActions() -> Set<DecisionAction>`.
- Consumes: `BBAmount`.

- [x] **Step 1: Write failing legal-action tests**

```swift
import Testing
@testable import PokerCore

@Test func unopenedNodeOffersCheckAndConfiguredBets() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 650),
        effectiveStack: .init(centiBB: 9_700),
        amountToCall: .init(centiBB: 0),
        minimumRaiseTo: nil,
        configuredBetSizes: [.init(centiBB: 217), .init(centiBB: 488)]
    )
    #expect(context.legalActions() == [
        .check,
        .bet(to: .init(centiBB: 217)),
        .bet(to: .init(centiBB: 488)),
        .allIn(to: .init(centiBB: 9_700))
    ])
}

@Test func facingBetOffersFoldCallAndLegalRaises() {
    let context = BettingDecisionContext(
        pot: .init(centiBB: 1_000),
        effectiveStack: .init(centiBB: 8_000),
        amountToCall: .init(centiBB: 300),
        minimumRaiseTo: .init(centiBB: 900),
        configuredBetSizes: [.init(centiBB: 750), .init(centiBB: 1_200)]
    )
    #expect(context.legalActions() == [
        .fold,
        .call(to: .init(centiBB: 300)),
        .raise(to: .init(centiBB: 1_200)),
        .allIn(to: .init(centiBB: 8_000))
    ])
}
```

- [x] **Step 2: Verify the tests fail**

Run: `swift test --package-path Packages/PokerCore`

Expected: compile failure for missing decision types.

- [x] **Step 3: Implement deterministic legal-action filtering**

Define:

```swift
public enum DecisionAction: Hashable, Codable, Sendable {
    case fold
    case check
    case call(to: BBAmount)
    case bet(to: BBAmount)
    case raise(to: BBAmount)
    case allIn(to: BBAmount)
}

public struct BettingDecisionContext: Hashable, Codable, Sendable {
    public let pot: BBAmount
    public let effectiveStack: BBAmount
    public let amountToCall: BBAmount
    public let minimumRaiseTo: BBAmount?
    public let configuredBetSizes: [BBAmount]
    public func legalActions() -> Set<DecisionAction>
}
```

Give `DecisionAction` a custom stable JSON representation:

```json
{"kind":"check"}
{"kind":"bet","toCentiBB":217}
{"kind":"raise","toCentiBB":1200}
```

Reject a missing `toCentiBB` for call/bet/raise/all-in and reject an unexpected amount for fold/check.

When `amountToCall` is zero, include check, configured positive bet sizes below the effective stack, and all-in. When facing a bet, include fold, call, configured sizes at or above `minimumRaiseTo`, and all-in. Deduplicate all-in if a configured size equals the effective stack. Reject contexts whose call exceeds the effective stack.

- [x] **Step 4: Run all PokerCore tests**

Run: `swift test --package-path Packages/PokerCore`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Packages/PokerCore
git commit -m "feat: validate legal cash decision actions"
```

---

### Task 4: Load and validate immutable strategy packs | covers: versioned-strategy-content/策略包来源可追溯, versioned-strategy-content/决策节点语义校验, versioned-strategy-content/审核状态约束

**Files:**
- Create: `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift`
- Create: `Packages/StrategyContent/Sources/StrategyContent/StrategyPackLoader.swift`
- Create: `Packages/StrategyContent/Sources/StrategyContent/StrategyPackValidator.swift`
- Create: `Packages/StrategyContent/Sources/StrategyContent/StrategyPackProvider.swift`
- Modify: `Packages/StrategyContent/Package.swift`
- Create: `Packages/StrategyContent/Tests/StrategyContentTests/StrategyPackTests.swift`
- Create: `Packages/StrategyContent/Tests/StrategyContentTests/Fixtures/valid-pack.json`
- Create: `Packages/StrategyContent/Tests/StrategyContentTests/Fixtures/invalid-frequency-pack.json`

**Interfaces:**
- Produces: `StrategyPack`, `StrategyPackManifest`, `DecisionScenario`, `StrategyOption`, `SolverAssumptions`, `ReviewStatus`.
- Produces: `StrategyPackLoader.load(data:expectedSHA256:) throws -> StrategyPack`.
- Produces: `StrategyPackValidator.validate(_:) throws`.
- Produces: `StrategyPackProviding` and `InMemoryStrategyPackProvider`.
- Consumes: `Card`, `BBAmount`, `EVAmount`, `BettingDecisionContext`, `DecisionAction`.

- [x] **Step 1: Write failing decoder and semantic validation tests**

```swift
import Foundation
import Testing
@testable import StrategyContent

@Test func validPackLoadsAndPreservesProvenance() throws {
    let data = try fixture("valid-pack.json")
    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    #expect(pack.manifest.id == "cash-6max-100bb-dev")
    #expect(pack.manifest.schemaVersion == 1)
    #expect(pack.scenarios[0].options.reduce(0) { $0 + $1.frequencyBasisPoints } == 10_000)
    #expect(pack.scenarios[0].assumptions.effectiveStack == .init(centiBB: 10_000))
}

@Test func invalidFrequencyTotalIsRejected() throws {
    let data = try fixture("invalid-frequency-pack.json")
    #expect(throws: StrategyPackValidationError.self) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}
```

The `fixture(_:)` helper reads resources from `Bundle.module`.

- [x] **Step 2: Run the StrategyContent tests**

Run: `swift test --package-path Packages/StrategyContent`

Expected: compile failure for missing strategy models and loader.

- [x] **Step 3: Implement the strategy schema and validator**

Use these public contracts:

```swift
public enum ReviewStatus: String, Codable, Sendable {
    case testFixture
    case reviewed
    case retired
}

public struct StrategyPackManifest: Codable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let contentVersion: String
    public let reviewStatus: ReviewStatus
    public let generatedSource: String
    public let reviewedAt: Date?
}

public struct StrategyOption: Codable, Hashable, Sendable {
    public let action: DecisionAction
    public let frequencyBasisPoints: Int
    public let ev: EVAmount
}

public struct SolverAssumptions: Codable, Hashable, Sendable {
    public let gameType: String
    public let tableSize: Int
    public let effectiveStack: BBAmount
    public let rakeDescription: String
    public let allowedBetSizeDescription: String
}

public struct StructuredExplanation: Codable, Hashable, Sendable {
    public let conclusion: String
    public let rangeReasoning: String
    public let boardReasoning: String
    public let opponentReasoning: String
    public let futurePlan: String
    public let gtoBaseline: String
    public let exploitCondition: String?
}

public struct RangeCell: Codable, Hashable, Sendable {
    public let handClass: String
    public let actionWeightsBasisPoints: [String: Int]
}

public struct DecisionScenario: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let abilityDimension: String
    public let heroCards: [Card]
    public let board: [Card]
    public let decision: BettingDecisionContext
    public let options: [StrategyOption]
    public let rangeCells: [RangeCell]
    public let assumptions: SolverAssumptions
    public let explanation: StructuredExplanation
}

public struct StrategyPack: Codable, Sendable {
    public let manifest: StrategyPackManifest
    public let scenarios: [DecisionScenario]
}

public enum StrategyPackLoadingError: Error, Equatable {
    case checksumMismatch
    case decodingFailed
}

public enum StrategyPackValidationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case duplicateScenarioID(String)
    case duplicateCard(String)
    case invalidFrequencyTotal(scenarioID: String, actual: Int)
    case illegalAction(scenarioID: String)
    case duplicateAction(scenarioID: String)
    case emptyGeneratedSource
    case missingReviewedAt
    case emptyScenarios
}

public enum StrategyPackLookupError: Error, Equatable {
    case scenarioNotFound(id: String)
}

public protocol StrategyPackProviding: Sendable {
    func pack() async throws -> StrategyPack
    func scenario(id: String) async throws -> DecisionScenario
}

public struct InMemoryStrategyPackProvider: StrategyPackProviding, Sendable {
    public init(pack: StrategyPack)
    public func pack() async throws -> StrategyPack
    public func scenario(id: String) async throws -> DecisionScenario
}
```

Validation must reject:

- a schema version other than `1`;
- duplicate pack or scenario IDs;
- duplicate cards;
- a frequency total other than `10_000`;
- an option action not returned by `decision.legalActions()`;
- duplicate actions;
- an empty `generatedSource`;
- a reviewed pack without `reviewedAt`;
- zero scenarios.

Use `CryptoKit.SHA256` when `expectedSHA256` is supplied and throw a checksum-specific error before decoding. Configure `JSONDecoder.dateDecodingStrategy = .iso8601`.
Configure the package test target with `.process("Fixtures")`. `InMemoryStrategyPackProvider.scenario(id:)` throws `StrategyPackLookupError.scenarioNotFound(id:)` when absent.

- [x] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/StrategyContent`

Expected: PASS for the valid fixture and the named validation failure for invalid frequency totals.

- [x] **Step 5: Commit**

```bash
git add Packages/StrategyContent
git commit -m "feat: load validated versioned strategy packs"
```

---

### Task 5: Grade decisions by transparent EV loss | covers: explainable-decision-training/可解释 EV 评分, explainable-decision-training/评分与结果无关

**Files:**
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/DecisionScorer.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/DecisionScorerTests.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/Support/ScenarioFixture.swift`

**Interfaces:**
- Produces: `DecisionSubmission`, `DecisionGrade`, `DecisionQuality`, `DecisionScorer.grade(submission:scenario:)`.
- Consumes: `DecisionScenario`, `DecisionAction`, `EVAmount`.

- [x] **Step 1: Write failing grading tests**

```swift
import Testing
import PokerCore
import StrategyContent
@testable import TrainingDomain

@Test func highestEVActionScoresOneHundred() throws {
    let scenario = try ScenarioFixture.mixedStrategy()
    let grade = try DecisionScorer().grade(
        submission: .init(action: scenario.options[0].action, confidence: .verySure),
        scenario: scenario
    )
    #expect(grade.evLoss == .init(milliBB: 0))
    #expect(grade.score == 100)
    #expect(grade.quality == .excellent)
}

@Test func closeMixedActionRemainsAcceptable() throws {
    let scenario = try ScenarioFixture.mixedStrategy()
    let grade = try DecisionScorer().grade(
        submission: .init(action: scenario.options[1].action, confidence: .unsure),
        scenario: scenario
    )
    #expect(grade.evLoss == .init(milliBB: 20))
    #expect(grade.quality == .acceptable)
    #expect(grade.isStrategicallyAvailable)
}

@Test func unlistedActionIsRejected() throws {
    let scenario = try ScenarioFixture.mixedStrategy()
    #expect(throws: DecisionScoringError.actionNotInStrategy) {
        try DecisionScorer().grade(
            submission: .init(action: .fold, confidence: .guessing),
            scenario: scenario
        )
    }
}
```

- [x] **Step 2: Run and verify missing grading symbols**

Run: `swift test --package-path Packages/TrainingDomain`

Expected: compile failure for `DecisionScorer` and related types.

- [x] **Step 3: Implement the scoring policy**

Define:

```swift
public enum DecisionConfidence: String, Codable, Sendable {
    case guessing, unsure, verySure
}

public struct DecisionSubmission: Equatable, Codable, Sendable {
    public let action: DecisionAction
    public let confidence: DecisionConfidence
    public init(action: DecisionAction, confidence: DecisionConfidence)
}

public enum DecisionQuality: String, Codable, Sendable {
    case excellent, acceptable, improvable, blunder
}

public struct DecisionGrade: Codable, Sendable {
    public let selectedAction: DecisionAction
    public let selectedFrequencyBasisPoints: Int
    public let selectedEV: EVAmount
    public let bestEV: EVAmount
    public let evLoss: EVAmount
    public let lossRateBasisPoints: Int
    public let score: Int
    public let quality: DecisionQuality
    public let isStrategicallyAvailable: Bool
}

public enum DecisionScoringError: Error, Equatable {
    case actionNotInStrategy
    case negativeEVLoss
}
```

Calculate `lossRateBasisPoints` as:

```swift
let potMilliBB = max(scenario.decision.pot.centiBB * 10, 1)
let lossRateBasisPoints = evLoss.milliBB * 10_000 / potMilliBB
```

Use exact quality bands:

- `0–10`: excellent;
- `11–100`: acceptable;
- `101–500`: improvable;
- above `500`: blunder.

Calculate `score` as `max(0, 100 - lossRateBasisPoints / 5)`. Preserve the raw EV loss and loss rate in every grade so the score remains explainable. Set `isStrategicallyAvailable` when frequency is greater than zero.

`ScenarioFixture.mixedStrategy()` must construct a 650-centiBB pot with three legal options: best EV `1,000` milliBB, second EV `980` milliBB, and third EV `700` milliBB; frequencies must total 10,000 basis points. This single fixture makes the expected 20-milliBB mixed-action loss explicit.

- [x] **Step 4: Run TrainingDomain tests**

Run: `swift test --package-path Packages/TrainingDomain`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Packages/TrainingDomain
git commit -m "feat: grade decisions with transparent EV loss"
```

---

### Task 6: Persist immutable local training events | covers: local-learning-profile/不可变本地训练事件

**Files:**
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEvent.swift`
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/TrainingEventStore.swift`
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/FileTrainingEventStore.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/FileTrainingEventStoreTests.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/Support/TrainingEventFixture.swift`

**Interfaces:**
- Produces: `TrainingEvent`.
- Produces: `TrainingEventStore.append(_:)`, `allEvents()`, and `events(after:)`.
- Produces: `FileTrainingEventStore`, an actor backed by newline-delimited JSON.
- Consumes: `DecisionSubmission`, `DecisionGrade`, scenario and content version IDs.

- [x] **Step 1: Write failing append and deduplication tests**

```swift
import Foundation
import Testing
@testable import TrainingDomain

@Test func eventStoreAppendsAndDeduplicatesByID() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = try FileTrainingEventStore(directory: directory)
    let event = TrainingEventFixture.correctHighConfidence()

    try await store.append(event)
    try await store.append(event)

    let events = try await store.allEvents()
    #expect(events == [event])
}

@Test func eventsAfterCheckpointAreOrdered() async throws {
    let store = try FileTrainingEventStore.temporary()
    let first = TrainingEventFixture.at(seconds: 1)
    let second = TrainingEventFixture.at(seconds: 2)
    try await store.append(second)
    try await store.append(first)

    #expect(try await store.events(after: first.id) == [second])
}
```

- [x] **Step 2: Run and verify failure**

Run: `swift test --package-path Packages/TrainingDomain`

Expected: compile failure for missing event-store contracts.

- [x] **Step 3: Implement the sync-ready event contract and file actor**

Define:

```swift
public struct TrainingEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let localUserID: UUID
    public let deviceID: UUID
    public let occurredAt: Date
    public let scenarioID: String
    public let strategyPackID: String
    public let strategyContentVersion: String
    public let abilityDimension: String
    public let submission: DecisionSubmission
    public let grade: DecisionGrade
}

public protocol TrainingEventStore: Sendable {
    func append(_ event: TrainingEvent) async throws
    func allEvents() async throws -> [TrainingEvent]
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent]
}

public enum TrainingEventStoreError: Error, Equatable {
    case corruptedLine(Int)
    case checkpointNotFound
}
```

`FileTrainingEventStore` must:

- create its directory and `training-events.jsonl` file when absent;
- decode existing lines during initialization;
- keep an in-memory ID index to make duplicate appends no-ops;
- rewrite to a temporary file and atomically replace the original on append;
- sort reads by `occurredAt`, then UUID string for deterministic ties;
- throw a typed corruption error that contains the invalid line number without logging the event body.

The test-only `TrainingEventFixture` must expose:

```swift
enum TrainingEventFixture {
    static func correctHighConfidence() -> TrainingEvent
    static func at(seconds: TimeInterval) -> TrainingEvent
    static func score(
        _ score: Int,
        confidence: DecisionConfidence,
        dimension: String
    ) -> TrainingEvent
}

extension FileTrainingEventStore {
    static func temporary() throws -> FileTrainingEventStore
}
```

Use fixed UUIDs, a fixed local user/device pair, and `Date(timeIntervalSince1970:)` values so equality and ordering assertions are deterministic. If `events(after:)` receives a checkpoint not present in the log, throw `TrainingEventStoreError.checkpointNotFound`.

- [x] **Step 4: Run store tests twice**

Run:

```bash
swift test --package-path Packages/TrainingDomain
swift test --package-path Packages/TrainingDomain
```

Expected: both runs PASS, proving tests do not depend on process-global state.

- [x] **Step 5: Commit**

```bash
git add Packages/TrainingDomain
git commit -m "feat: persist append-only local training events"
```

---

### Task 7: Reduce events into an explainable ability profile and daily plan | covers: local-learning-profile/能力画像归约, local-learning-profile/今日训练优先级

**Files:**
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/PlayerModel.swift`
- Create: `Packages/TrainingDomain/Sources/TrainingDomain/TrainingPlanner.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/PlayerModelTests.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/TrainingPlannerTests.swift`
- Create: `Packages/TrainingDomain/Tests/TrainingDomainTests/Support/PlannerFixtures.swift`

**Interfaces:**
- Produces: `AbilitySnapshot`, `PlayerProfile`, `PlayerModelReducer.reduce(events:)`.
- Produces: `TrainingCatalogItem`, `DailyPlan`, `TrainingPlanner.makePlan(profile:catalog:now:)`.
- Consumes: ordered `TrainingEvent` records and scenario ability dimensions.

- [x] **Step 1: Write failing reducer and priority tests**

```swift
import Foundation
import Testing
@testable import TrainingDomain

@Test func reducerSeparatesHighConfidenceErrors() {
    let events = [
        TrainingEventFixture.score(40, confidence: .verySure, dimension: "bet-sizing"),
        TrainingEventFixture.score(90, confidence: .guessing, dimension: "preflop-range")
    ]
    let profile = PlayerModelReducer().reduce(events: events)
    #expect(profile["bet-sizing"]?.highConfidenceErrorCount == 1)
    #expect(profile["preflop-range"]?.meanScore == 90)
}

@Test func plannerPrioritizesHighConfidenceWeakness() throws {
    let profile = PlayerProfileFixture.twoDimensions()
    let plan = TrainingPlanner().makePlan(
        profile: profile,
        catalog: TrainingCatalogFixture.items,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )
    #expect(plan.items.first?.abilityDimension == "bet-sizing")
    #expect(plan.items.count == 3)
}
```

- [x] **Step 2: Run and verify failure**

Run: `swift test --package-path Packages/TrainingDomain`

Expected: compile failure for missing profile and planner types.

- [x] **Step 3: Implement deterministic reduction and planning**

`AbilitySnapshot` must expose:

```swift
public struct AbilitySnapshot: Equatable, Codable, Sendable {
    public let dimension: String
    public let sampleCount: Int
    public let meanScore: Int
    public let meanLossRateBasisPoints: Int
    public let highConfidenceErrorCount: Int
    public let lastPracticedAt: Date?
}

public struct PlayerProfile: Equatable, Codable, Sendable {
    public let abilities: [String: AbilitySnapshot]
    public subscript(dimension: String) -> AbilitySnapshot? { abilities[dimension] }
}

public struct TrainingCatalogItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let scenarioID: String
    public let abilityDimension: String
    public let estimatedMinutes: Int
}

public struct DailyPlanItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let catalogItem: TrainingCatalogItem
    public let priority: Int
    public let reason: String
    public var abilityDimension: String { catalogItem.abilityDimension }
}

public struct DailyPlan: Equatable, Codable, Sendable {
    public let generatedAt: Date
    public let items: [DailyPlanItem]
}
```

The reducer groups by `abilityDimension`, uses integer arithmetic for means, and counts a high-confidence error when confidence is `.verySure` and quality is `.improvable` or `.blunder`.

The planner computes:

```swift
priority = (100 - meanScore)
         + min(highConfidenceErrorCount * 15, 45)
         + min(daysSincePractice * 2, 30)
```

Unseen dimensions use `meanScore = 60`, zero confidence errors, and `daysSincePractice = 7`. Select three distinct catalog items ordered by descending priority, then stable item ID. The plan stores the calculation date and a human-readable reason for each item.

`PlannerFixtures.swift` must define `PlayerProfileFixture.twoDimensions()` with bet sizing below preflop range, plus three `TrainingCatalogFixture.items` whose IDs sort deterministically. The fixture dates are fixed relative to `1_800_000_000` seconds since 1970.

- [x] **Step 4: Run all TrainingDomain tests**

Run: `swift test --package-path Packages/TrainingDomain`

Expected: PASS with deterministic ordering.

- [x] **Step 5: Commit**

```bash
git add Packages/TrainingDomain
git commit -m "feat: derive ability profile and daily priorities"
```

---

### Task 8: Compose app dependencies and adaptive navigation | covers: adaptive-native-shell/四个核心入口, adaptive-native-shell/原生平台支持

**Files:**
- Create: `PokerCoach/App/AppDependencies.swift`
- Modify: `PokerCoach/App/PokerCoachApp.swift`
- Modify: `PokerCoach/App/Root/AdaptiveRootView.swift`
- Create: `PokerCoach/Features/Today/TodayView.swift`
- Create: `PokerCoach/Features/Learn/LearnView.swift`
- Create: `PokerCoach/Features/Train/TrainLandingView.swift`
- Create: `PokerCoach/Features/Review/ReviewView.swift`
- Create: `PokerCoachTests/AdaptiveNavigationTests.swift`

**Interfaces:**
- Produces: `AppDependencies.live()` and `AppDependencies.preview`.
- Produces: routes `today`, `learn`, `train`, `review`.
- Consumes: `TrainingEventStore`, strategy-pack provider, scorer, reducer, and planner.

- [x] **Step 1: Write a failing navigation contract test**

```swift
import XCTest
@testable import PokerCoach

final class AdaptiveNavigationTests: XCTestCase {
    func testAllPrimaryDestinationsHaveChineseLabels() {
        XCTAssertEqual(AppDestination.allCases.map(\.title), ["今日", "学习", "训练", "复盘"])
        XCTAssertEqual(AppDestination.train.systemImage, "suit.spade.fill")
    }
}
```

- [x] **Step 2: Run the app unit test and verify failure**

Run:

```bash
xcodegen generate
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/AdaptiveNavigationTests
```

Expected: compile failure for missing `AppDestination`.

- [x] **Step 3: Implement dependency composition and navigation**

Define:

```swift
enum AppDestination: String, CaseIterable, Identifiable {
    case today, learn, train, review
    var id: Self { self }
    var title: String
    var systemImage: String
}

@MainActor
final class AppDependencies {
    let eventStore: any TrainingEventStore
    let strategyProvider: any StrategyPackProviding
    let scorer: DecisionScorer
    let playerModelReducer: PlayerModelReducer
    let planner: TrainingPlanner
}
```

Use a `TabView` in compact horizontal size class and `NavigationSplitView` with a four-item sidebar in regular width. Keep feature views simple but real: each screen renders its title and an empty-state sentence. Inject one `AppDependencies` instance from `PokerCoachApp`.

- [x] **Step 4: Build both application idioms**

Run:

```bash
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach -destination 'generic/platform=iOS Simulator'
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach -destination 'generic/platform=iOS'
```

Expected: both builds succeed without project-owned strict-concurrency warnings.

- [x] **Step 5: Commit**

```bash
git add PokerCoach PokerCoachTests project.yml
git commit -m "feat: add adaptive four-destination app shell"
```

---

### Task 9: Implement the decision-session state machine | covers: explainable-decision-training/行动与信心共同提交, explainable-decision-training/评分与结果无关

**Files:**
- Create: `PokerCoach/Features/Train/DecisionSessionViewModel.swift`
- Create: `PokerCoach/Features/Train/DecisionSessionView.swift`
- Create: `PokerCoach/Shared/PokerCardView.swift`
- Create: `PokerCoach/Shared/ActionButton.swift`
- Create: `PokerCoachTests/DecisionSessionViewModelTests.swift`
- Create: `PokerCoachTests/Support/DecisionSessionFixture.swift`

**Interfaces:**
- Produces: `DecisionSessionState.loading`, `.answering`, `.feedback`, `.completed`.
- Produces: `DecisionSessionViewModel.load()`, `select(action:)`, `setConfidence(_:)`, `submit()`, `continueSession()`.
- Consumes: one `DecisionScenario`, `DecisionScorer`, and `TrainingEventStore`.

- [x] **Step 1: Write failing state-machine tests**

```swift
import XCTest
import PokerCore
@testable import PokerCoach

@MainActor
final class DecisionSessionViewModelTests: XCTestCase {
    func testSubmitRequiresActionAndConfidence() async throws {
        let sut = DecisionSessionFixture.makeViewModel()
        await sut.load()
        XCTAssertEqual(sut.state, .answering)
        await sut.submit()
        XCTAssertEqual(sut.validationMessage, "请选择行动和信心程度")
    }

    func testValidSubmitGradesAndPersistsOneEvent() async throws {
        let fixture = DecisionSessionFixture.make()
        await fixture.viewModel.load()
        fixture.viewModel.select(action: fixture.scenario.options[0].action)
        fixture.viewModel.setConfidence(.verySure)
        await fixture.viewModel.submit()
        XCTAssertEqual(fixture.viewModel.state, .feedback)
        let events = try await fixture.store.allEvents()
        XCTAssertEqual(events.count, 1)
    }
}
```

- [x] **Step 2: Run and verify failure**

Run the `DecisionSessionViewModelTests` with the same simulator command from Task 8.

Expected: compile failure for missing session types.

- [x] **Step 3: Implement the state machine and table screen**

The view model must:

- load exactly one scenario by ID;
- expose only `decision.legalActions()` in stable display order;
- require action and confidence before submit;
- call `DecisionScorer` once;
- append exactly one `TrainingEvent` before showing feedback;
- disable submission while saving;
- surface a Chinese retry message when loading or saving fails;
- never use the runout or session result as scorer input.

Use this public state contract:

```swift
enum DecisionSessionState: Equatable {
    case loading
    case answering
    case feedback
    case completed
    case failed(message: String)
}
```

`DecisionSessionFixture.make()` must return:

```swift
struct DecisionSessionTestContext {
    let viewModel: DecisionSessionViewModel
    let scenario: DecisionScenario
    let store: InMemoryTrainingEventStore
}
```

Add `InMemoryTrainingEventStore` in the test support file as an actor conforming to `TrainingEventStore`. `makeViewModel()` returns the context's view model for tests that do not inspect the store.

The view must show position, effective stack, pot, hero cards, board, legal action buttons, and three confidence choices. Add accessibility identifiers:

- `decision.position`
- `decision.pot`
- `decision.heroCards`
- `decision.board`
- `decision.action.<stable-action-id>`
- `decision.confidence.<raw-value>`
- `decision.submit`

Position is a table-size-independent domain contract:

- keep `SolverAssumptions.tableSize` as the number of players dealt into the hand;
- add `DecisionScenario.heroSeatOffsetFromButton`;
- define and validate a PokerCore position value for 2–9 players;
- derive the display label deterministically (`BTN/SB` for heads-up button; otherwise BTN, SB, BB and the conventional early/middle/late labels);
- the M1A fixture uses 6 players, but the type must not be named or constrained as 6-max-only.

- [x] **Step 4: Run model tests and build**

Run:

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/DecisionSessionViewModelTests
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach -destination 'generic/platform=iOS Simulator'
```

Expected: tests and build PASS.

- [x] **Step 5: Commit**

```bash
git add PokerCoach/Features/Train PokerCoach/Shared PokerCoachTests
git commit -m "feat: add cash decision training flow"
```

---

### Task 10: Present professional feedback without hiding uncertainty | covers: explainable-decision-training/专业反馈层级, versioned-strategy-content/审核状态约束

**Files:**
- Create: `PokerCoach/Features/Feedback/FeedbackPresentation.swift`
- Create: `PokerCoach/Features/Feedback/ProfessionalFeedbackView.swift`
- Create: `PokerCoach/Features/Feedback/ActionFrequencyView.swift`
- Create: `PokerCoach/Features/Feedback/RangeMatrixView.swift`
- Create: `PokerCoachTests/FeedbackPresentationTests.swift`
- Create: `PokerCoachTests/Support/FeedbackFixture.swift`

**Interfaces:**
- Produces: `FeedbackPresentation.init(scenario:submission:grade:)`.
- Produces: Chinese summary, raw EV values, frequency rows, range cells, assumptions, and exploit-condition sections.
- Consumes: `DecisionScenario`, `DecisionSubmission`, and `DecisionGrade`.

- [ ] **Step 1: Write failing presentation tests**

```swift
import XCTest
@testable import PokerCoach

final class FeedbackPresentationTests: XCTestCase {
    func testMixedStrategyKeepsEveryAvailableActionVisible() throws {
        let fixture = FeedbackFixture.mixedStrategy()
        let presentation = FeedbackPresentation(
            scenario: fixture.scenario,
            submission: fixture.submission,
            grade: fixture.grade
        )
        XCTAssertEqual(presentation.frequencyRows.count, 3)
        XCTAssertEqual(presentation.evLossText, "−0.020 BB")
        XCTAssertEqual(presentation.qualityText, "可接受")
        XCTAssertTrue(presentation.assumptions.contains("100BB"))
    }

    func testDevelopmentFixtureIsAlwaysDisclosed() throws {
        let presentation = FeedbackFixture.developmentPresentation()
        XCTAssertEqual(presentation.provenanceBadge, "开发演示数据")
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run the `FeedbackPresentationTests` target.

Expected: compile failure for missing presentation types.

- [ ] **Step 3: Implement the professional feedback hierarchy**

Render, in order:

1. quality, score, confidence calibration, and raw EV loss;
2. one-sentence structured conclusion;
3. all action frequencies and EV values;
4. range matrix and combo weights when present;
5. four-question reasoning: range, board, opponent, future plan;
6. GTO baseline;
7. exploit adjustment only when `StructuredExplanation.exploitCondition` is non-empty;
8. stack, rake, bet-size tree, generated source, content version, and review status.

The presentation formatter must show EV to three decimal BB and frequency to one decimal percent. It must not label an action “错误” when its `DecisionQuality` is `.excellent` or `.acceptable`.

`FeedbackFixture.mixedStrategy()` must return a scenario, submission, and grade whose second action loses exactly 20 milliBB. `developmentPresentation()` uses a pack manifest with `.testFixture`; a reviewed manifest must instead produce the badge `已审核 · <contentVersion>`.

- [ ] **Step 4: Run tests and inspect both size classes**

Run:

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/FeedbackPresentationTests
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach -destination 'generic/platform=iOS Simulator'
```

Expected: PASS. In an iPad preview, range matrix and analysis may share columns; in iPhone previews they remain in one scrollable column.

- [ ] **Step 5: Commit**

```bash
git add PokerCoach/Features/Feedback PokerCoachTests
git commit -m "feat: show professional explainable decision feedback"
```

---

### Task 11: Connect Today and Review to real local events | covers: local-learning-profile/今日与复盘使用真实历史

**Files:**
- Create: `PokerCoach/Features/Today/TodayViewModel.swift`
- Modify: `PokerCoach/Features/Today/TodayView.swift`
- Create: `PokerCoach/Features/Review/ReviewViewModel.swift`
- Modify: `PokerCoach/Features/Review/ReviewView.swift`
- Modify: `PokerCoach/Features/Learn/LearnView.swift`
- Create: `PokerCoachTests/TodayViewModelTests.swift`
- Create: `PokerCoachTests/ReviewViewModelTests.swift`
- Create: `PokerCoachTests/Support/DashboardFixture.swift`

**Interfaces:**
- Produces: `TodayViewModel.refresh()` and `startPrimaryItem()`.
- Produces: `ReviewViewModel.refresh()` with sorted ability snapshots.
- Consumes: event store, profile reducer, planner, and debug training catalog.

- [ ] **Step 1: Write failing Today and Review model tests**

```swift
import XCTest
@testable import PokerCoach

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testWeakestDimensionBecomesPrimaryTraining() async throws {
        let fixture = DashboardFixture.withBetSizingWeakness()
        await fixture.today.refresh()
        XCTAssertEqual(fixture.today.primaryItem?.abilityDimension, "bet-sizing")
        XCTAssertEqual(fixture.today.durationText, "约 8 分钟")
    }
}

@MainActor
final class ReviewViewModelTests: XCTestCase {
    func testReviewSortsWeakestAbilityFirst() async throws {
        let fixture = DashboardFixture.withTwoDimensions()
        await fixture.review.refresh()
        XCTAssertEqual(fixture.review.abilities.map(\.dimension), ["bet-sizing", "preflop-range"])
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run the two app test classes.

Expected: compile failure for missing dashboard view models.

- [ ] **Step 3: Implement event-derived dashboards**

Today must show:

- one primary training item and two supporting items;
- an estimated total of 5–10 minutes;
- the reason the primary item was selected;
- a button that routes to the matching scenario.

Review must show:

- sample count;
- mean score;
- mean EV-loss rate;
- high-confidence error count;
- last practiced time;
- a “生成弱项训练” action.

Learn displays the M1A cash path as a read-only sequence and clearly labels MTT as a later product milestone without showing locked purchase UI.

`DashboardFixture.withBetSizingWeakness()` and `.withTwoDimensions()` must use `InMemoryTrainingEventStore` populated with fixed events from `TrainingEventFixture` equivalents in the app test target. The fixture exposes `today` and `review` view models so tests never reach into private state.

- [ ] **Step 4: Run dashboard tests**

Run:

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/TodayViewModelTests \
  -only-testing:PokerCoachTests/ReviewViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PokerCoach/Features PokerCoachTests
git commit -m "feat: drive today and review from training history"
```

---

### Task 12: Add the debug strategy fixture and end-to-end UI coverage | covers: adaptive-native-shell/四个核心入口, explainable-decision-training/专业反馈层级, m1a-release-safety/开发策略数据隔离

**Files:**
- Create: `PokerCoach/Resources/DevStrategyPack.json`
- Create: `PokerCoach/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `PokerCoach/App/AppDependencies.swift`
- Modify: `project.yml`
- Create: `PokerCoachUITests/CashCoachHappyPathTests.swift`
- Create: `PokerCoachUITests/IPadLayoutTests.swift`

**Interfaces:**
- Produces: one debug-only, schema-valid scenario with three legal actions and mixed frequencies.
- Produces: launch argument `--reset-training-events`.
- Consumes: complete M1A UI flow.

- [ ] **Step 1: Write failing UI tests**

```swift
import XCTest

final class CashCoachHappyPathTests: XCTestCase {
    func testDecisionCreatesProfessionalFeedbackAndReviewHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-training-events"]
        app.launch()

        app.buttons["开始今日训练"].tap()
        app.buttons["decision.action.bet-217"].tap()
        app.buttons["decision.confidence.verySure"].tap()
        app.buttons["decision.submit"].tap()

        XCTAssertTrue(app.staticTexts["开发演示数据"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["EV 损失"].exists)
        XCTAssertTrue(app.staticTexts["行动频率"].exists)

        app.buttons["继续"].tap()
        app.tabBars.buttons["复盘"].tap()
        XCTAssertTrue(app.staticTexts["下注尺度"].exists)
    }
}
```

`IPadLayoutTests` launches on iPad and asserts identifiers `feedback.table-column` and `feedback.analysis-column` both exist after submission.

- [ ] **Step 2: Run UI tests and verify failure**

Run:

```bash
xcodegen generate
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachUITests/CashCoachHappyPathTests
```

Expected: failure because the debug strategy resource and route are absent.

- [ ] **Step 3: Add a disclosed development fixture and reset hook**

The debug pack must:

- use manifest ID `cash-6max-100bb-dev`;
- use schema version `1`;
- use review status `testFixture`;
- identify `generatedSource` as `deterministic-ui-test-fixture`;
- contain one BTN-vs-BB 100BB flop decision;
- contain frequencies totaling exactly 10,000 basis points;
- include three EV values that exercise excellent, acceptable, and improvable grades;
- include a non-empty stack, rake, bet-size-tree, and source assumption;
- include Chinese structured explanations;
- never be copied into Release resources.

Add `--reset-training-events` handling before dependency creation so UI tests begin with an empty file store. In Debug, load the fixture through the same loader and validator used by production content. In Release, `EXCLUDED_SOURCE_FILE_NAMES = DevStrategyPack.json` removes the fixture, and `AppDependencies.live()` must show a visible “未安装已审核策略内容” state when no reviewed pack exists.

- [ ] **Step 4: Run iPhone and iPad UI tests**

Run:

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachUITests/CashCoachHappyPathTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest' \
  -only-testing:PokerCoachUITests/IPadLayoutTests
```

Expected: both UI tests PASS; every feedback screen shows `开发演示数据`.

- [ ] **Step 5: Commit**

```bash
git add PokerCoach/Resources PokerCoach/App project.yml PokerCoachUITests
git commit -m "test: cover cash coach vertical slice on phone and tablet"
```

---

### Task 13: Add one-command verification and M1A handoff documentation | covers: m1a-release-safety/一键验证, m1a-release-safety/开发策略数据隔离

**Files:**
- Create: `scripts/verify-m1a.sh`
- Create: `README.md`
- Create: `docs/architecture/m1a-module-boundaries.md`

**Interfaces:**
- Produces: `bash scripts/verify-m1a.sh`.
- Documents: module ownership and the exact contracts M1B may consume without changing.

- [ ] **Step 1: Write the verification script**

```bash
#!/usr/bin/env bash
set -euo pipefail

xcodegen generate
swift test --package-path Packages/PokerCore
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/TrainingDomain
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachUITests/CashCoachHappyPathTests
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest' \
  -only-testing:PokerCoachUITests/IPadLayoutTests
```

- [ ] **Step 2: Document the executable workflow**

`README.md` must contain:

- required versions: Xcode 26.2, Swift 6.2.3, XcodeGen;
- `xcodegen generate`;
- `bash scripts/verify-m1a.sh`;
- how to run the Debug fixture;
- a warning that fixture strategies are not reviewed poker advice;
- the design and roadmap document links.

`docs/architecture/m1a-module-boundaries.md` must state that M1B may depend on:

```swift
TrainingEvent
TrainingEventStore
FileTrainingEventStore
StrategyPackManifest
```

M1B must add a remote synchronizer around these contracts and may not move HTTP, authentication, or database DTOs into `PokerCore`, `StrategyContent`, or `TrainingDomain`.

- [ ] **Step 3: Run complete verification**

Run: `bash scripts/verify-m1a.sh`

Expected: every package, unit, iPhone UI, and iPad UI test exits 0.

- [ ] **Step 4: Confirm release exclusion and repository cleanliness**

Run:

```bash
xcodebuild build -project PokerCoach.xcodeproj -scheme PokerCoach \
  -configuration Release -destination 'generic/platform=iOS Simulator'
find ~/Library/Developer/Xcode/DerivedData -path '*PokerCoach*.app*' -name 'DevStrategyPack.json' -print
git diff --check
git status --short
```

Expected: Release build succeeds; `find` prints no `DevStrategyPack.json`; diff check is clean; only intended task files are modified.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/architecture scripts/verify-m1a.sh
git commit -m "docs: add m1a verification and module handoff"
```

---

## M1A completion gate

Do not call M1A complete until all of the following are true:

- `bash scripts/verify-m1a.sh` passes from a clean checkout.
- Debug clearly labels every fixture-derived answer as `开发演示数据`.
- Release contains no development strategy fixture.
- A decision can be completed on iPhone and inspected on iPad.
- The persisted event includes scenario ID, pack ID, content version, confidence, raw EV loss, and quality.
- Multiple strategically available actions remain visible.
- Today and Review change after the completed decision.
- No runout or winnings value enters `DecisionScorer`.
- Package boundaries documented for M1B remain intact.
- The branch receives specification-compliance and code-quality review before merge.

## Self-Review Checklist

- [x] Capability 追溯表完整：proposal 中 6 个 Capability、19 个 Requirement、34 个 Scenario 均映射到 Task。
- [x] 每个 Task 的 `covers:` 与 Capability 追溯表一致。
- [x] 每个代码步骤包含确切文件、测试、命令和预期结果。
- [x] 不含 TBD、TODO、“类似 Task N”或“添加适当处理”等占位表达。
- [x] 跨 Task 的类型、函数和属性名称保持一致。
- [x] M1A Non-Goals 未混入任务。

## 下一步

执行 `/harness-apply poker-coach-m1a-cash-coach-20260806-01`，使用 Sub-agent 模式。
