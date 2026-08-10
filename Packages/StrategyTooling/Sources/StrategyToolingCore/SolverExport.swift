import Foundation
import PokerCore

/// The input format the importer reads.
///
/// It stays close to the shape of a strategy pack on purpose. The importer's
/// job is to validate, stamp provenance, and encode deterministically — not to
/// translate vocabularies. A translation layer would be a second place where
/// the meaning of a frequency or an EV could be got wrong, and there is no
/// independent source of truth available to check it against.
public struct SolverExport: Codable, Sendable {
    public let packID: String
    public let generatedSource: String
    public let exportedAt: Date
    public let gameType: String
    public let tableSize: Int
    public let effectiveStack: BBAmount
    public let rakeDescription: String
    public let allowedBetSizeDescription: String
    public let curriculum: [SolverCurriculumNode]
    public let nodes: [SolverNode]

    public init(
        packID: String,
        generatedSource: String,
        exportedAt: Date,
        gameType: String,
        tableSize: Int,
        effectiveStack: BBAmount,
        rakeDescription: String,
        allowedBetSizeDescription: String,
        curriculum: [SolverCurriculumNode],
        nodes: [SolverNode]
    ) {
        self.packID = packID
        self.generatedSource = generatedSource
        self.exportedAt = exportedAt
        self.gameType = gameType
        self.tableSize = tableSize
        self.effectiveStack = effectiveStack
        self.rakeDescription = rakeDescription
        self.allowedBetSizeDescription = allowedBetSizeDescription
        self.curriculum = curriculum
        self.nodes = nodes
    }
}

public struct SolverCurriculumNode: Codable, Sendable {
    public let id: String
    public let title: String
    public let prerequisiteNodeIDs: [String]

    public init(id: String, title: String, prerequisiteNodeIDs: [String]) {
        self.id = id
        self.title = title
        self.prerequisiteNodeIDs = prerequisiteNodeIDs
    }
}

public struct SolverAction: Codable, Sendable {
    public let action: DecisionAction
    public let frequencyBasisPoints: Int
    public let ev: EVAmount

    public init(action: DecisionAction, frequencyBasisPoints: Int, ev: EVAmount) {
        self.action = action
        self.frequencyBasisPoints = frequencyBasisPoints
        self.ev = ev
    }
}

public struct SolverRangeCell: Codable, Sendable {
    public let handClass: String
    public let actionWeightsBasisPoints: [String: Int]

    public init(handClass: String, actionWeightsBasisPoints: [String: Int]) {
        self.handClass = handClass
        self.actionWeightsBasisPoints = actionWeightsBasisPoints
    }
}

public struct SolverExplanation: Codable, Sendable {
    public let conclusion: String
    public let rangeReasoning: String
    public let boardReasoning: String
    public let opponentReasoning: String
    public let futurePlan: String
    public let gtoBaseline: String
    public let exploitCondition: String?

    public init(
        conclusion: String,
        rangeReasoning: String,
        boardReasoning: String,
        opponentReasoning: String,
        futurePlan: String,
        gtoBaseline: String,
        exploitCondition: String?
    ) {
        self.conclusion = conclusion
        self.rangeReasoning = rangeReasoning
        self.boardReasoning = boardReasoning
        self.opponentReasoning = opponentReasoning
        self.futurePlan = futurePlan
        self.gtoBaseline = gtoBaseline
        self.exploitCondition = exploitCondition
    }
}

public struct SolverNode: Codable, Sendable {
    public let id: String
    public let title: String
    public let abilityDimension: String
    public let curriculumNodeID: String
    public let heroSeatOffsetFromButton: Int
    /// Card codes such as "As". Parsed by the importer so a typo fails the
    /// build rather than reaching the app as an undecodable pack.
    public let heroCards: [String]
    public let board: [String]
    public let pot: BBAmount
    public let amountToCall: BBAmount
    public let minimumRaiseTo: BBAmount?
    public let configuredBetSizes: [BBAmount]
    public let actions: [SolverAction]
    public let rangeCells: [SolverRangeCell]
    public let explanation: SolverExplanation

    public init(
        id: String,
        title: String,
        abilityDimension: String,
        curriculumNodeID: String,
        heroSeatOffsetFromButton: Int,
        heroCards: [String],
        board: [String],
        pot: BBAmount,
        amountToCall: BBAmount,
        minimumRaiseTo: BBAmount?,
        configuredBetSizes: [BBAmount],
        actions: [SolverAction],
        rangeCells: [SolverRangeCell],
        explanation: SolverExplanation
    ) {
        self.id = id
        self.title = title
        self.abilityDimension = abilityDimension
        self.curriculumNodeID = curriculumNodeID
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.heroCards = heroCards
        self.board = board
        self.pot = pot
        self.amountToCall = amountToCall
        self.minimumRaiseTo = minimumRaiseTo
        self.configuredBetSizes = configuredBetSizes
        self.actions = actions
        self.rangeCells = rangeCells
        self.explanation = explanation
    }
}
