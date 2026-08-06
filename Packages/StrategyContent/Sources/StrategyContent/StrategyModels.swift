import Foundation
import PokerCore

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
