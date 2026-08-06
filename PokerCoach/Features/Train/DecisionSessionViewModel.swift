import Foundation
import Observation
import PokerCore
import StrategyContent
import TrainingDomain

enum DecisionSessionState: Equatable {
    case loading
    case answering
    case feedback
    case completed
    case failed(message: String)
}

@MainActor
@Observable
final class DecisionSessionViewModel {
    typealias Grader = @MainActor (
        DecisionSubmission,
        DecisionScenario
    ) throws -> DecisionGrade

    private(set) var state: DecisionSessionState = .loading
    private(set) var scenario: DecisionScenario?
    private(set) var legalActions: [DecisionAction] = []
    private(set) var selectedAction: DecisionAction?
    private(set) var selectedConfidence: DecisionConfidence?
    private(set) var submission: DecisionSubmission?
    private(set) var grade: DecisionGrade?
    private(set) var validationMessage: String?
    private(set) var isSaving = false

    var canSubmit: Bool {
        state == .answering
            && selectedAction != nil
            && selectedConfidence != nil
            && !isSaving
    }

    private let scenarioID: String
    private let strategyProvider: any StrategyPackProviding
    private let grader: Grader
    private let eventStore: any TrainingEventStore
    private let localUserID: UUID
    private let deviceID: UUID
    private let makeEventID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    private var strategyPackID: String?
    private var strategyContentVersion: String?
    private var pendingEvent: TrainingEvent?

    init(
        scenarioID: String,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer,
        eventStore: any TrainingEventStore,
        localUserID: UUID,
        deviceID: UUID,
        makeEventID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.scenarioID = scenarioID
        self.strategyProvider = strategyProvider
        grader = { submission, scenario in
            try scorer.grade(
                submission: submission,
                scenario: scenario
            )
        }
        self.eventStore = eventStore
        self.localUserID = localUserID
        self.deviceID = deviceID
        self.makeEventID = makeEventID
        self.now = now
    }

    init(
        scenarioID: String,
        strategyProvider: any StrategyPackProviding,
        grader: @escaping Grader,
        eventStore: any TrainingEventStore,
        localUserID: UUID,
        deviceID: UUID,
        makeEventID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.scenarioID = scenarioID
        self.strategyProvider = strategyProvider
        self.grader = grader
        self.eventStore = eventStore
        self.localUserID = localUserID
        self.deviceID = deviceID
        self.makeEventID = makeEventID
        self.now = now
    }

    func load() async {
        guard !isSaving else {
            return
        }

        state = .loading
        validationMessage = nil
        resetLoadedSession()

        do {
            async let scenarioRequest = strategyProvider.scenario(
                id: scenarioID
            )
            async let packRequest = strategyProvider.pack()
            let (loadedScenario, pack) = try await (
                scenarioRequest,
                packRequest
            )

            scenario = loadedScenario
            strategyPackID = pack.manifest.id
            strategyContentVersion = pack.manifest.contentVersion
            legalActions = loadedScenario.decision.legalActions()
                .sorted(by: DecisionAction.stableDisplayOrder)
            state = .answering
        } catch {
            state = .failed(message: "场景加载失败，请重试")
        }
    }

    func select(action: DecisionAction) {
        guard state == .answering, !isSaving else {
            return
        }
        guard legalActions.contains(action) else {
            selectedAction = nil
            return
        }

        selectedAction = action
        validationMessage = nil
    }

    func setConfidence(_ confidence: DecisionConfidence) {
        guard state == .answering, !isSaving else {
            return
        }

        selectedConfidence = confidence
        validationMessage = nil
    }

    func submit() async {
        guard !isSaving else {
            return
        }
        guard state == .answering || pendingEvent != nil else {
            return
        }

        if pendingEvent == nil {
            guard
                let scenario,
                let selectedAction,
                let selectedConfidence,
                legalActions.contains(selectedAction),
                let strategyPackID,
                let strategyContentVersion
            else {
                validationMessage = "请选择行动和信心程度"
                return
            }

            let submission = DecisionSubmission(
                action: selectedAction,
                confidence: selectedConfidence
            )

            do {
                let grade = try grader(submission, scenario)
                self.submission = submission
                self.grade = grade
                pendingEvent = TrainingEvent(
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
            } catch {
                state = .failed(message: "评分失败，请重试")
                return
            }
        }

        guard let pendingEvent else {
            return
        }

        isSaving = true
        validationMessage = nil
        defer {
            isSaving = false
        }

        do {
            try await eventStore.append(pendingEvent)
            state = .feedback
            self.pendingEvent = nil
        } catch {
            state = .failed(message: "保存失败，请重试")
        }
    }

    func continueSession() {
        guard state == .feedback else {
            return
        }
        state = .completed
    }

    private func resetLoadedSession() {
        scenario = nil
        legalActions = []
        selectedAction = nil
        selectedConfidence = nil
        submission = nil
        grade = nil
        strategyPackID = nil
        strategyContentVersion = nil
        pendingEvent = nil
    }
}

extension DecisionAction {
    var stableID: String {
        switch self {
        case .fold:
            "fold"
        case .check:
            "check"
        case let .call(to: amount):
            "call-\(amount.centiBB)"
        case let .bet(to: amount):
            "bet-\(amount.centiBB)"
        case let .raise(to: amount):
            "raise-\(amount.centiBB)"
        case let .allIn(to: amount):
            "all-in-\(amount.centiBB)"
        }
    }

    var displayTitle: String {
        switch self {
        case .fold:
            "弃牌"
        case .check:
            "过牌"
        case let .call(to: amount):
            "跟注 \(amount.displayText)"
        case let .bet(to: amount):
            "下注到 \(amount.displayText)"
        case let .raise(to: amount):
            "加注到 \(amount.displayText)"
        case let .allIn(to: amount):
            "全下 \(amount.displayText)"
        }
    }

    fileprivate static func stableDisplayOrder(
        _ lhs: DecisionAction,
        _ rhs: DecisionAction
    ) -> Bool {
        let left = lhs.displayOrder
        let right = rhs.displayOrder
        if left.kind != right.kind {
            return left.kind < right.kind
        }
        return left.amount < right.amount
    }

    private var displayOrder: (kind: Int, amount: Int) {
        switch self {
        case .fold:
            (0, 0)
        case .check:
            (1, 0)
        case let .call(to: amount):
            (2, amount.centiBB)
        case let .bet(to: amount):
            (3, amount.centiBB)
        case let .raise(to: amount):
            (4, amount.centiBB)
        case let .allIn(to: amount):
            (5, amount.centiBB)
        }
    }
}

extension BBAmount {
    var displayText: String {
        let whole = centiBB / 100
        let remainder = centiBB % 100
        return switch remainder {
        case 0:
            "\(whole) BB"
        case let value where value % 10 == 0:
            "\(whole).\(value / 10) BB"
        default:
            "\(whole).\(String(format: "%02d", remainder)) BB"
        }
    }
}

extension DecisionConfidence {
    static let displayCases: [DecisionConfidence] = [
        .guessing,
        .unsure,
        .verySure
    ]

    var displayTitle: String {
        switch self {
        case .guessing:
            "猜测"
        case .unsure:
            "不确定"
        case .verySure:
            "很确定"
        }
    }
}
