import Foundation
import Observation
import PokerCore
import StrategyContent
import TrainingDomain

enum TournamentTrainerState: Equatable {
    case unavailable
    case answering
    case feedback
    case failed(message: String)
}

/// Drives the heads-up push/fold trainer over the bundled `unverifiedDraft`
/// tournament packs.
///
/// It deals a spot (depth × position × hero hand), looks up the dealt hand's
/// range cell, synthesizes a per-hand `DecisionScenario` (the pack scenario with
/// the dealt hand's own options), and scores the hero's jam/fold with the
/// unchanged `DecisionScorer`, recording a `TrainingEvent`. Because the content
/// is unverified, the view discloses that; the trainer is absent from the store
/// build where no packs are bundled.
@MainActor
@Observable
final class TournamentPushFoldViewModel {
    enum Position: Equatable {
        case openJam   // SB, unopened
        case callJam   // BB, facing a jam
    }

    private(set) var state: TournamentTrainerState = .unavailable
    private(set) var depth: Int = 0
    private(set) var position: Position = .openJam
    private(set) var heroCards: [Card] = []
    private(set) var handClass: String = ""
    private(set) var promptText: String = ""
    private(set) var candidateActions: [DecisionAction] = []
    private(set) var selectedAction: DecisionAction?
    private(set) var selectedConfidence: DecisionConfidence?
    private(set) var grade: DecisionGrade?
    private(set) var feedbackLines: [String] = []
    private(set) var validationMessage: String?
    private(set) var isSaving = false

    /// Always non-nil for a loaded spot: the packs are `unverifiedDraft`.
    private(set) var disclosure: String?

    private let loader: TournamentPushFoldLoader
    private let scorer: DecisionScorer
    private let eventStore: any TrainingEventStore
    private let localUserID: UUID
    private let deviceID: UUID
    private let makeEventID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    private var packCache: [Int: StrategyPack] = [:]
    private var scenario: DecisionScenario?
    private var strategyPackID: String?
    private var strategyContentVersion: String?

    init(
        loader: TournamentPushFoldLoader,
        scorer: DecisionScorer = DecisionScorer(),
        eventStore: any TrainingEventStore,
        localUserID: UUID,
        deviceID: UUID,
        makeEventID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.loader = loader
        self.scorer = scorer
        self.eventStore = eventStore
        self.localUserID = localUserID
        self.deviceID = deviceID
        self.makeEventID = makeEventID
        self.now = now
    }

    var availableDepths: [Int] { loader.availableDepths() }

    /// Deals a random spot (used by the app).
    func startRandomHand() {
        var rng = SystemRandomNumberGenerator()
        startRandomHand(using: &rng)
    }

    func startRandomHand<R: RandomNumberGenerator>(using rng: inout R) {
        let depths = availableDepths
        guard let depth = depths.randomElement(using: &rng) else {
            state = .unavailable
            return
        }
        // Call-Jam requires the BB to have chips behind (depth >= 2).
        let position: Position = (depth >= 2 && Bool.random(using: &rng)) ? .callJam : .openJam
        let (first, second) = Self.dealTwoCards(using: &rng)
        present(depth: depth, position: position, heroCards: [first, second])
    }

    /// Presents a specific spot. The scoring path is exercised here, so tests
    /// call this directly with a fixed depth/position/hand.
    func present(depth: Int, position: Position, heroCards: [Card]) {
        selectedAction = nil
        selectedConfidence = nil
        grade = nil
        feedbackLines = []
        validationMessage = nil

        do {
            let pack = try loadPack(depth: depth)
            guard let scenario = Self.scenario(in: pack, for: position) else {
                state = .failed(message: "内容缺少该局面")
                return
            }
            let handClass = Self.handClass(for: heroCards)
            guard let cell = scenario.rangeCells.first(where: { $0.handClass == handClass }),
                  let actionEVs = cell.actionEVs
            else {
                state = .failed(message: "内容缺少该手牌")
                return
            }
            let options = Self.options(from: cell, actionEVs: actionEVs, decision: scenario.decision)
            let synthesized = Self.withHand(scenario, heroCards: heroCards, options: options)

            self.depth = depth
            self.position = position
            self.heroCards = heroCards
            self.handClass = handClass
            self.scenario = synthesized
            self.candidateActions = options
                .map(\.action)
                .sorted { Self.isAggressive($0) && !Self.isAggressive($1) }
            self.strategyPackID = pack.manifest.id
            self.strategyContentVersion = pack.manifest.contentVersion
            self.disclosure = StrategyContentMetadata.disclosure(
                forReviewStatus: pack.manifest.reviewStatus,
                origin: pack.manifest.origin
            )
            self.promptText = Self.prompt(depth: depth, position: position, handClass: handClass)
            self.state = .answering
        } catch {
            state = .failed(message: "内容加载失败")
        }
    }

    func select(action: DecisionAction) {
        guard state == .answering else { return }
        selectedAction = action
        validationMessage = nil
    }

    func setConfidence(_ confidence: DecisionConfidence) {
        guard state == .answering else { return }
        selectedConfidence = confidence
        validationMessage = nil
    }

    func submit() async {
        guard state == .answering, !isSaving else { return }
        guard
            let scenario,
            let action = selectedAction,
            let confidence = selectedConfidence,
            let strategyPackID,
            let strategyContentVersion
        else {
            validationMessage = "请选择行动和信心程度"
            return
        }

        let submission = DecisionSubmission(action: action, confidence: confidence)
        let grade: DecisionGrade
        do {
            grade = try scorer.grade(submission: submission, scenario: scenario)
        } catch {
            validationMessage = "评分失败，请重试"
            return
        }

        let event = TrainingEvent(
            id: makeEventID(),
            localUserID: localUserID,
            deviceID: deviceID,
            occurredAt: now(),
            scenarioID: scenario.id,
            strategyPackID: strategyPackID,
            strategyContentVersion: strategyContentVersion,
            abilityDimension: scenario.abilityDimension,
            submission: submission,
            grade: grade
        )

        isSaving = true
        defer { isSaving = false }
        do {
            try await eventStore.append(event)
        } catch {
            state = .failed(message: "保存失败，请重试")
            return
        }

        self.grade = grade
        self.feedbackLines = Self.feedback(for: scenario, grade: grade)
        self.state = .feedback
    }

    // MARK: - Pure helpers

    private func loadPack(depth: Int) throws -> StrategyPack {
        if let cached = packCache[depth] { return cached }
        guard let pack = try loader.loadPack(depth: depth) else {
            throw TournamentTrainerError.packMissing
        }
        packCache[depth] = pack
        return pack
    }

    private static func scenario(in pack: StrategyPack, for position: Position) -> DecisionScenario? {
        let seat = position == .openJam ? 0 : 1
        return pack.scenarios.first { $0.heroSeatOffsetFromButton == seat }
    }

    private static func options(
        from cell: RangeCell,
        actionEVs: [String: EVAmount],
        decision: BettingDecisionContext
    ) -> [StrategyOption] {
        var options: [StrategyOption] = []
        for (key, bps) in cell.actionWeightsBasisPoints {
            let action: DecisionAction
            switch key {
            case "fold": action = .fold
            case "raise": action = .allIn(to: decision.effectiveStack)
            case "call": action = .call(to: decision.amountToCall)
            default: continue
            }
            options.append(StrategyOption(
                action: action,
                frequencyBasisPoints: bps,
                ev: actionEVs[key] ?? EVAmount(milliBB: 0)
            ))
        }
        return options
    }

    private static func withHand(
        _ scenario: DecisionScenario,
        heroCards: [Card],
        options: [StrategyOption]
    ) -> DecisionScenario {
        DecisionScenario(
            id: scenario.id,
            title: scenario.title,
            abilityDimension: scenario.abilityDimension,
            curriculumNodeID: scenario.curriculumNodeID,
            heroSeatOffsetFromButton: scenario.heroSeatOffsetFromButton,
            facing: scenario.facing,
            heroCards: heroCards,
            board: scenario.board,
            decision: scenario.decision,
            options: options,
            rangeCells: scenario.rangeCells,
            assumptions: scenario.assumptions,
            explanation: scenario.explanation
        )
    }

    private static func isAggressive(_ action: DecisionAction) -> Bool {
        switch action {
        case .fold, .check: false
        default: true
        }
    }

    static func handClass(for cards: [Card]) -> String {
        guard cards.count == 2 else { return "" }
        let order = Rank.allCases // two ... ace
        func index(_ r: Rank) -> Int { order.firstIndex(of: r) ?? 0 }
        let a = cards[0], b = cards[1]
        let (hi, lo) = index(a.rank) >= index(b.rank) ? (a, b) : (b, a)
        if hi.rank == lo.rank {
            return hi.rank.rawValue + lo.rank.rawValue
        }
        let suited = hi.suit == lo.suit ? "s" : "o"
        return hi.rank.rawValue + lo.rank.rawValue + suited
    }

    private static func dealTwoCards<R: RandomNumberGenerator>(using rng: inout R) -> (Card, Card) {
        var deck: [Card] = []
        for rank in Rank.allCases {
            for suit in Suit.allCases {
                deck.append(Card(rank: rank, suit: suit))
            }
        }
        deck.shuffle(using: &rng)
        return (deck[0], deck[1])
    }

    private static func prompt(depth: Int, position: Position, handClass: String) -> String {
        let seat = position == .openJam ? "小盲开局（未加注）" : "大盲面对全下"
        return "\(depth)BB · \(seat) · 你的手牌 \(handClass)"
    }

    private static func feedback(for scenario: DecisionScenario, grade: DecisionGrade) -> [String] {
        var lines: [String] = []
        lines.append("得分 \(grade.score) · \(qualityText(grade.quality))")
        lines.append("EV 损失 \(grade.evLoss.milliBB) milliBB")
        for option in scenario.options.sorted(by: { $0.ev.milliBB > $1.ev.milliBB }) {
            lines.append("\(actionText(option.action))：频率 \(percent(option.frequencyBasisPoints)) · EV \(option.ev.milliBB) milliBB")
        }
        return lines
    }

    private static func qualityText(_ quality: DecisionQuality) -> String {
        switch quality {
        case .excellent: "优秀"
        case .acceptable: "可接受"
        case .improvable: "有待改进"
        case .blunder: "失误"
        }
    }

    private static func actionText(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "弃牌"
        case .check: "过牌"
        case .call: "跟注全下"
        case .allIn: "全下"
        case .bet: "下注"
        case .raise: "加注"
        }
    }

    private static func percent(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let frac = (basisPoints % 100) / 10
        return "\(whole).\(frac)%"
    }
}

enum TournamentTrainerError: Error, Equatable {
    case packMissing
}
