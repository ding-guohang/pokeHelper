import PokerCore
import StrategyContent

public enum DecisionConfidence: String, Codable, Sendable {
    case guessing
    case unsure
    case verySure
}

public struct DecisionSubmission: Equatable, Codable, Sendable {
    public let action: DecisionAction
    public let confidence: DecisionConfidence

    public init(action: DecisionAction, confidence: DecisionConfidence) {
        self.action = action
        self.confidence = confidence
    }
}

public enum DecisionQuality: String, Codable, Sendable {
    case excellent
    case acceptable
    case improvable
    case blunder
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

public struct DecisionScorer: Sendable {
    public init() {}

    public func grade(
        submission: DecisionSubmission,
        scenario: DecisionScenario
    ) throws -> DecisionGrade {
        guard let selectedOption = scenario.options.first(where: { $0.action == submission.action }) else {
            throw DecisionScoringError.actionNotInStrategy
        }
        guard let bestEV = scenario.options.map(\.ev).max() else {
            throw DecisionScoringError.actionNotInStrategy
        }

        let evLoss = bestEV - selectedOption.ev
        guard evLoss.milliBB >= 0 else {
            throw DecisionScoringError.negativeEVLoss
        }

        let potMilliBB = max(scenario.decision.pot.centiBB * 10, 1)
        let lossRateBasisPoints = evLoss.milliBB * 10_000 / potMilliBB

        return DecisionGrade(
            selectedAction: selectedOption.action,
            selectedFrequencyBasisPoints: selectedOption.frequencyBasisPoints,
            selectedEV: selectedOption.ev,
            bestEV: bestEV,
            evLoss: evLoss,
            lossRateBasisPoints: lossRateBasisPoints,
            score: max(0, 100 - lossRateBasisPoints / 5),
            quality: quality(for: lossRateBasisPoints),
            isStrategicallyAvailable: selectedOption.frequencyBasisPoints > 0
        )
    }

    private func quality(for lossRateBasisPoints: Int) -> DecisionQuality {
        switch lossRateBasisPoints {
        case 0 ... 10:
            .excellent
        case 11 ... 100:
            .acceptable
        case 101 ... 500:
            .improvable
        default:
            .blunder
        }
    }
}
