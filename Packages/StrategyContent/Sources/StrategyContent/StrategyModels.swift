import Foundation
import PokerCore

public enum ReviewStatus: String, Codable, Sendable {
    case testFixture
    /// Content that is internally consistent and safe to train against, but
    /// whose frequencies and EVs no human has checked against a solver. It
    /// exists so generated content can carry an honest label: calling it
    /// `reviewed` would assert a verification nobody performed.
    case unverifiedDraft
    case reviewed
    case retired
}

/// Where a pack's frequencies, EVs and ranges actually came from.
///
/// Separate from `ReviewStatus` because origin and endorsement are different
/// claims. `implicit-contracts.md` requires strategy truth to come from
/// versioned structured content and deterministic computation; a human review
/// raises confidence in content but cannot change where its numbers originated,
/// so review alone must not silence the disclosure.
public enum ContentOrigin: String, Codable, Sendable {
    /// Produced by a solver whose run is recorded in the manifest.
    case solver
    /// Authored by a generative model. Always disclosed, however reviewed.
    case generativeModel
    /// Hand-written for tests and demonstrations.
    case fixture
}

public struct StrategyPackManifest: Codable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let contentVersion: String
    public let reviewStatus: ReviewStatus
    public let generatedSource: String
    public let origin: ContentOrigin
    /// Who signed off on the strategy. Required on `reviewed` content and
    /// absent elsewhere — `reviewed` with nobody accountable for it is the
    /// precise false guarantee `unverifiedDraft` exists to prevent.
    public let reviewedBy: String?
    public let reviewedAt: Date?

    public init(
        id: String,
        schemaVersion: Int,
        contentVersion: String,
        reviewStatus: ReviewStatus,
        generatedSource: String,
        origin: ContentOrigin,
        reviewedBy: String?,
        reviewedAt: Date?
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.reviewStatus = reviewStatus
        self.generatedSource = generatedSource
        self.origin = origin
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
    }
}

/// A node in the cash-game curriculum tree.
///
/// Node membership is a property of the content, not of a training event.
/// An event already records the scenario it answered, so its node is looked up
/// through that scenario. Putting the node on the event instead would mean
/// changing the cross-language upload contract in `Contracts/`, which is
/// byte-frozen and asserted from both the Swift and Go sides.
public struct CurriculumNode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let prerequisiteNodeIDs: [String]

    public init(id: String, title: String, prerequisiteNodeIDs: [String]) {
        self.id = id
        self.title = title
        self.prerequisiteNodeIDs = prerequisiteNodeIDs
    }
}

public struct StrategyOption: Codable, Hashable, Sendable {
    public let action: DecisionAction
    public let frequencyBasisPoints: Int
    public let ev: EVAmount

    public init(action: DecisionAction, frequencyBasisPoints: Int, ev: EVAmount) {
        self.action = action
        self.frequencyBasisPoints = frequencyBasisPoints
        self.ev = ev
    }
}

public struct SolverAssumptions: Codable, Hashable, Sendable {
    public let gameType: String
    public let tableSize: Int
    public let effectiveStack: BBAmount
    public let rakeDescription: String
    public let allowedBetSizeDescription: String
    public let tournament: TournamentSolverAssumptions?

    public init(
        gameType: String,
        tableSize: Int,
        effectiveStack: BBAmount,
        rakeDescription: String,
        allowedBetSizeDescription: String,
        tournament: TournamentSolverAssumptions? = nil
    ) {
        self.gameType = gameType
        self.tableSize = tableSize
        self.effectiveStack = effectiveStack
        self.rakeDescription = rakeDescription
        self.allowedBetSizeDescription = allowedBetSizeDescription
        self.tournament = tournament
    }
}

public struct StructuredExplanation: Codable, Hashable, Sendable {
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

public struct RangeCell: Codable, Hashable, Sendable {
    public let handClass: String
    public let actionWeightsBasisPoints: [String: Int]
    public let actionEVs: [String: EVAmount]?

    public init(
        handClass: String,
        actionWeightsBasisPoints: [String: Int],
        actionEVs: [String: EVAmount]? = nil
    ) {
        self.handClass = handClass
        self.actionWeightsBasisPoints = actionWeightsBasisPoints
        self.actionEVs = actionEVs
    }
}

public struct DecisionScenario: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let abilityDimension: String
    /// Not optional on purpose: a pack that predates the curriculum should fail
    /// to decode rather than silently land every scenario in a default node.
    public let curriculumNodeID: String
    public let heroSeatOffsetFromButton: Int
    /// How much aggression the hero is answering.
    ///
    /// Declared rather than derived, and not optional, for the same reason
    /// `curriculumNodeID` is not: a pack that predates the field should fail to
    /// decode rather than land every scenario in a default bucket. Defaulting
    /// to `.unopened` would file every 3-bet scenario under the open-raising
    /// baseline, which is the one mistake this field exists to prevent.
    ///
    /// It cannot be recovered from `decision`. Chips a caller puts in and chips
    /// a raiser puts in are indistinguishable inside `pot`, so the number of
    /// prior raises is simply not present in the betting context —
    /// `SolverNode.facingRaiseTo` carries the same observation for MDF.
    public let facing: FacingAction
    public let heroCards: [Card]
    public let board: [Card]
    public let decision: BettingDecisionContext
    public let options: [StrategyOption]
    public let rangeCells: [RangeCell]
    public let assumptions: SolverAssumptions
    public let explanation: StructuredExplanation

    public init(
        id: String,
        title: String,
        abilityDimension: String,
        curriculumNodeID: String,
        heroSeatOffsetFromButton: Int,
        facing: FacingAction,
        heroCards: [Card],
        board: [Card],
        decision: BettingDecisionContext,
        options: [StrategyOption],
        rangeCells: [RangeCell],
        assumptions: SolverAssumptions,
        explanation: StructuredExplanation
    ) {
        self.id = id
        self.title = title
        self.abilityDimension = abilityDimension
        self.curriculumNodeID = curriculumNodeID
        self.heroSeatOffsetFromButton = heroSeatOffsetFromButton
        self.facing = facing
        self.heroCards = heroCards
        self.board = board
        self.decision = decision
        self.options = options
        self.rangeCells = rangeCells
        self.assumptions = assumptions
        self.explanation = explanation
    }
}

public struct StrategyPack: Codable, Sendable {
    public let manifest: StrategyPackManifest
    public let curriculum: [CurriculumNode]
    public let scenarios: [DecisionScenario]

    public init(
        manifest: StrategyPackManifest,
        curriculum: [CurriculumNode],
        scenarios: [DecisionScenario]
    ) {
        self.manifest = manifest
        self.curriculum = curriculum
        self.scenarios = scenarios
    }
}

public enum StrategyPackLoadingError: Error, Equatable {
    case checksumMismatch
    case decodingFailed
}

public enum StrategyPackValidationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case duplicateScenarioID(String)
    case invalidTableSize(scenarioID: String, tableSize: Int)
    case invalidHeroSeatOffset(
        scenarioID: String,
        tableSize: Int,
        heroSeatOffsetFromButton: Int
    )
    case duplicateCard(String)
    case invalidFrequencyTotal(scenarioID: String, actual: Int)
    case illegalAction(scenarioID: String)
    case duplicateAction(scenarioID: String)
    case emptyGeneratedSource
    case missingReviewedAt
    case missingReviewedBy
    case emptyScenarios
    case unknownCurriculumNode(scenarioID: String, nodeID: String)
    case unknownPrerequisite(nodeID: String, prerequisiteID: String)
    case cyclicCurriculum(nodeIDs: [String])
    case duplicateCurriculumNodeID(String)
    case invalidTournamentAssumptions(scenarioID: String)
    case inconsistentTournamentEffectiveStack(scenarioID: String)
    case invalidTournamentRangeCoverage(scenarioID: String)
    case invalidTournamentRangeActions(scenarioID: String, handClass: String)
    case invalidTournamentRangeFrequency(scenarioID: String, handClass: String)
}

public enum StrategyPackLookupError: Error, Equatable {
    case scenarioNotFound(id: String)
}
