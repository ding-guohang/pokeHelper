import Foundation
import Observation
import PokerCore
import StrategyContent
import TrainingDomain

enum RiverTrainerState: Equatable {
    case unavailable
    case answering
    case feedback
    case failed(message: String)
}

/// Drives the river trainer over the bundled `reviewed` river packs.
///
/// It deals a spot (board × a specific in-range hero combo), looks up that
/// combo's range cell, synthesizes a per-hand `DecisionScenario` (the pack
/// scenario with the dealt combo's own options), and scores the hero's
/// check/bet with the unchanged `DecisionScorer`, recording a `TrainingEvent`.
///
/// The key difference from the push/fold trainer: river range cells are keyed by
/// EXACT combos (suits matter for flushes), not 169 preflop classes, so a spot
/// is dealt by picking one of the scenario's cells (already board-safe and
/// in-range) rather than dealing two cards and bucketing them. The content is
/// `reviewed` + `origin=solver`, so `disclosure` is nil.
@MainActor
@Observable
final class RiverTrainerViewModel {
    private(set) var state: RiverTrainerState = .unavailable
    private(set) var boardID: String = ""
    private(set) var board: [Card] = []
    private(set) var heroCards: [Card] = []
    private(set) var comboLabel: String = ""
    private(set) var promptText: String = ""
    private(set) var candidateActions: [DecisionAction] = []
    private(set) var selectedAction: DecisionAction?
    private(set) var selectedConfidence: DecisionConfidence?
    private(set) var grade: DecisionGrade?
    private(set) var feedbackLines: [String] = []
    private(set) var validationMessage: String?
    private(set) var isSaving = false

    /// Nil for the shipped `reviewed` packs; set only if a lesser-status pack is
    /// ever loaded.
    private(set) var disclosure: String?

    private let loader: RiverTrainerLoader
    private let scorer: DecisionScorer
    private let eventStore: any TrainingEventStore
    private let localUserID: UUID
    private let deviceID: UUID
    private let makeEventID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    private var packCache: [String: StrategyPack] = [:]
    private var scenario: DecisionScenario?
    private var strategyPackID: String?
    private var strategyContentVersion: String?

    init(
        loader: RiverTrainerLoader,
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

    var availableBoards: [String] { loader.availableBoards() }

    func startRandomHand() {
        var rng = SystemRandomNumberGenerator()
        startRandomHand(using: &rng)
    }

    func startRandomHand<R: RandomNumberGenerator>(using rng: inout R) {
        let boards = availableBoards
        guard let boardID = boards.randomElement(using: &rng) else {
            state = .unavailable
            return
        }
        do {
            let pack = try loadPack(boardID: boardID)
            guard let scenario = pack.scenarios.first,
                  let cell = scenario.rangeCells.randomElement(using: &rng)
            else {
                state = .unavailable
                return
            }
            present(boardID: boardID, heroCombo: cell.handClass)
        } catch {
            state = .failed(message: "内容加载失败")
        }
    }

    /// Presents a specific spot. Tests call this directly with a fixed board and
    /// combo so the scoring path is deterministic.
    func present(boardID: String, heroCombo: String) {
        selectedAction = nil
        selectedConfidence = nil
        grade = nil
        feedbackLines = []
        validationMessage = nil

        do {
            let pack = try loadPack(boardID: boardID)
            guard let scenario = pack.scenarios.first else {
                state = .failed(message: "内容缺少该局面")
                return
            }
            guard let cell = scenario.rangeCells.first(where: { $0.handClass == heroCombo }),
                  let actionEVs = cell.actionEVs
            else {
                state = .failed(message: "内容缺少该手牌")
                return
            }
            guard let heroCards = Self.cards(from: heroCombo) else {
                state = .failed(message: "手牌无法解析")
                return
            }
            let options = Self.options(from: cell, actionEVs: actionEVs)
            let synthesized = Self.withHand(scenario, heroCards: heroCards, options: options)

            self.boardID = boardID
            self.board = scenario.board
            self.heroCards = heroCards
            self.comboLabel = heroCombo
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
            self.promptText = Self.prompt(board: scenario.board, combo: heroCombo)
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

    private func loadPack(boardID: String) throws -> StrategyPack {
        if let cached = packCache[boardID] { return cached }
        guard let pack = try loader.loadPack(boardID: boardID) else {
            throw RiverTrainerError.packMissing
        }
        packCache[boardID] = pack
        return pack
    }

    static func cards(from combo: String) -> [Card]? {
        guard combo.count == 4 else { return nil }
        let chars = Array(combo)
        guard let first = Card(code: String(chars[0...1])),
              let second = Card(code: String(chars[2...3]))
        else {
            return nil
        }
        return [first, second]
    }

    private static func options(
        from cell: RangeCell,
        actionEVs: [String: EVAmount]
    ) -> [StrategyOption] {
        var options: [StrategyOption] = []
        for (key, bps) in cell.actionWeightsBasisPoints {
            let action: DecisionAction
            if key == "check" {
                action = .check
            } else if key.hasPrefix("allin"), let size = Int(key.dropFirst(5)) {
                action = .allIn(to: BBAmount(centiBB: size))
            } else if key.hasPrefix("bet"), let size = Int(key.dropFirst(3)) {
                action = .bet(to: BBAmount(centiBB: size))
            } else {
                continue
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

    private static func prompt(board: [Card], combo: String) -> String {
        let boardText = board.map(\.code).joined(separator: " ")
        return "河牌 \(boardText) · 你的手牌 \(combo) · 无人下注，先动"
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
        case .call: "跟注"
        case .allIn: "全下"
        case let .bet(to): "下注至 \(bbText(to))"
        case let .raise(to): "加注至 \(bbText(to))"
        }
    }

    private static func bbText(_ amount: BBAmount) -> String {
        let whole = amount.centiBB / 100
        let frac = (amount.centiBB % 100) / 10
        return "\(whole).\(frac)BB"
    }

    private static func percent(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let frac = (basisPoints % 100) / 10
        return "\(whole).\(frac)%"
    }
}

enum RiverTrainerError: Error, Equatable {
    case packMissing
}
