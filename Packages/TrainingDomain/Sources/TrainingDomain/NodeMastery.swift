import Foundation
import StrategyContent

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

    /// Derived rather than stored. Every signal is a "reached at least N"
    /// comparison, and a separately stored flag could disagree with the numbers
    /// shown beside it — which are what the user reads to know how much further
    /// they have to go.
    public var satisfied: Bool { actual >= required }
}

public struct NodeMastery: Sendable, Equatable {
    public let nodeID: String
    /// Always five entries, in `MasterySignal.Kind.allCases` order, so the UI
    /// can render a fixed table and tests can index it.
    public let signals: [MasterySignal]

    public var isMastered: Bool { signals.allSatisfy(\.satisfied) }

    public func signal(_ kind: MasterySignal.Kind) -> MasterySignal {
        // Force-unwrapped deliberately: an evaluator that omits a signal is a
        // programming error, and returning a placeholder would let the omission
        // reach the screen looking like a satisfied row.
        signals.first { $0.kind == kind }!
    }
}

/// Judges node mastery against the five signals `docs/product/learning-rules.md`
/// names, with the thresholds fixed here so each one is testable.
///
/// Every signal reports its current value alongside its requirement. The value is
/// not decoration: a verdict alone can be produced by an implementation that
/// always answers "not mastered", and the negative cases cannot tell the
/// difference. The numbers are what makes them able to.
public struct MasteryEvaluator: Sendable {
    public static let sampleRequirement = 20
    /// How many of the most recent answers are examined for stability and
    /// calibration.
    public static let recentWindow = 10
    public static let recentPassRequirement = 9
    public static let repetitionRequirement = 2
    /// Scenarios the user had never answered in this node before.
    public static let transferRequirement = 3

    private let scheduler = RepetitionScheduler()

    public init() {}

    public func evaluate(
        nodeID: String,
        events: [TrainingEvent],
        pack: StrategyPack
    ) -> NodeMastery {
        let nodeEvents = RepetitionScheduler.chronological(
            CurriculumResolver(pack: pack).eventsByNode(events)[nodeID] ?? []
        )
        let window = nodeEvents.suffix(Self.recentWindow)
        let verySure = window.filter { $0.submission.confidence == .verySure }

        let signals = [
            MasterySignal(
                kind: .sample,
                actual: nodeEvents.count,
                required: Self.sampleRequirement
            ),
            MasterySignal(
                kind: .recentStability,
                actual: window.count { RepetitionScheduler.isPass($0.grade.quality) },
                required: Self.recentPassRequirement
            ),
            // Requirement is the number of very-sure answers in the window, so
            // a user who never claimed certainty is calibrated by default
            // rather than penalised for it.
            MasterySignal(
                kind: .confidenceCalibration,
                actual: verySure.count { RepetitionScheduler.isPass($0.grade.quality) },
                required: verySure.count
            ),
            MasterySignal(
                kind: .repetition,
                actual: scheduler.completedRepetitionCount(events: nodeEvents),
                required: Self.repetitionRequirement
            ),
            MasterySignal(
                kind: .transfer,
                actual: Self.transferPassCount(in: nodeEvents),
                required: Self.transferRequirement
            ),
        ]

        return NodeMastery(nodeID: nodeID, signals: signals)
    }

    /// How many of the last three scenarios the user met for the first time
    /// were answered well.
    ///
    /// Transfer asks whether the skill survives an unfamiliar spot, so only the
    /// first answer to a given scenario counts. Repeat attempts measure recall
    /// of that particular hand instead.
    private static func transferPassCount(in nodeEvents: [TrainingEvent]) -> Int {
        var seen: Set<String> = []
        var firstEncounters: [TrainingEvent] = []
        for event in nodeEvents where seen.insert(event.scenarioID).inserted {
            firstEncounters.append(event)
        }
        return firstEncounters
            .suffix(transferRequirement)
            .count { RepetitionScheduler.isPass($0.grade.quality) }
    }
}
