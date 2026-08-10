import Foundation
import PokerCore
@testable import StrategyContent

/// Builds packs for tests that care about manifest and curriculum shape rather
/// than about scenario content. The scenario body is taken from the checked-in
/// valid pack so these tests stay focused on the field under test and do not
/// duplicate a full hand of poker data.
enum StrategyPackFixture {
    enum FixtureError: Error {
        case missingResource(String)
    }

    /// The scenario ID carried by `valid-pack.json`. Tests assert against it
    /// when a validation error is expected to name the offending scenario.
    static let scenarioID = "btn-check"

    static let defaultCurriculum = [
        CurriculumNode(id: "postflop-cbet", title: "翻牌持续下注", prerequisiteNodeIDs: []),
    ]

    static func pack(
        reviewStatus: ReviewStatus = .testFixture,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil,
        curriculum: [CurriculumNode] = defaultCurriculum,
        scenarioNodeID: String = "postflop-cbet"
    ) throws -> StrategyPack {
        let source = try loadedValidPack()
        return StrategyPack(
            manifest: StrategyPackManifest(
                id: source.manifest.id,
                schemaVersion: source.manifest.schemaVersion,
                contentVersion: source.manifest.contentVersion,
                reviewStatus: reviewStatus,
                generatedSource: source.manifest.generatedSource,
                origin: .fixture,
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
            ),
            curriculum: curriculum,
            scenarios: source.scenarios.map {
                $0.replacingCurriculumNodeID(with: scenarioNodeID)
            }
        )
    }

    private static func loadedValidPack() throws -> StrategyPack {
        guard let url = Bundle.module.url(
            forResource: "valid-pack",
            withExtension: "json"
        ) else {
            throw FixtureError.missingResource("valid-pack.json")
        }
        return try StrategyPackLoader().load(
            data: Data(contentsOf: url),
            expectedSHA256: nil
        )
    }
}

private extension DecisionScenario {
    func replacingCurriculumNodeID(with nodeID: String) -> DecisionScenario {
        DecisionScenario(
            id: id,
            title: title,
            abilityDimension: abilityDimension,
            curriculumNodeID: nodeID,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton,
            heroCards: heroCards,
            board: board,
            decision: decision,
            options: options,
            rangeCells: rangeCells,
            assumptions: assumptions,
            explanation: explanation
        )
    }
}
