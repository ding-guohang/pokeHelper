import CryptoKit
import Foundation
import PokerCore
import StrategyContent

public enum PackBuildError: Error, Equatable {
    case unparseableCard(scenarioID: String, code: String)
    /// The pack the importer assembled did not satisfy the content model.
    ///
    /// The importer does not restate rules such as "frequencies total 10,000":
    /// it runs `StrategyPackValidator` and surfaces its typed error. A second
    /// copy of those rules is a second thing that can drift away from the model
    /// the app actually loads.
    case invalidPack(StrategyPackValidationError)
}

public struct PackBuildResult: Sendable, Equatable {
    public let sha256: String
    public let byteCount: Int
}

public struct PackBuilder: Sendable {
    public init() {}

    public func build(
        from export: SolverExport,
        contentVersion: String,
        reviewStatus: ReviewStatus,
        reviewedBy: String?,
        reviewedAt: Date?
    ) throws -> StrategyPack {
        let pack = StrategyPack(
            manifest: StrategyPackManifest(
                id: export.packID,
                schemaVersion: 1,
                contentVersion: contentVersion,
                reviewStatus: reviewStatus,
                generatedSource: Self.provenance(for: export),
                reviewedBy: reviewedBy,
                reviewedAt: reviewedAt
            ),
            curriculum: export.curriculum.map {
                CurriculumNode(
                    id: $0.id,
                    title: $0.title,
                    prerequisiteNodeIDs: $0.prerequisiteNodeIDs
                )
            },
            scenarios: try export.nodes.map { try scenario(from: $0, in: export) }
        )

        do {
            try StrategyPackValidator().validate(pack)
        } catch let error as StrategyPackValidationError {
            throw PackBuildError.invalidPack(error)
        }
        return pack
    }

    /// Builds, validates, and only then writes.
    ///
    /// Assembly happens entirely in memory so a rejected export cannot leave a
    /// half-written pack on disk for the next step to pick up.
    @discardableResult
    public func write(
        from export: SolverExport,
        contentVersion: String,
        reviewStatus: ReviewStatus,
        reviewedBy: String?,
        reviewedAt: Date?,
        to url: URL
    ) throws -> PackBuildResult {
        let pack = try build(
            from: export,
            contentVersion: contentVersion,
            reviewStatus: reviewStatus,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt
        )
        let data = try Self.makeEncoder().encode(pack)
        let digest = Self.sha256Hex(data)

        try data.write(to: url, options: .atomic)
        try Data("\(digest)\n".utf8).write(
            to: url.deletingPathExtension().appendingPathExtension("sha256"),
            options: .atomic
        )
        return PackBuildResult(sha256: digest, byteCount: data.count)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Encoding fixed so the same export always produces the same bytes.
    ///
    /// `sortedKeys` is load bearing: `RangeCell.actionWeightsBasisPoints` is a
    /// dictionary, and Swift seeds its hashing per process, so without this the
    /// key order — and therefore the checksum — changes from one run to the
    /// next. That failure is invisible to a test that imports twice inside one
    /// process, because a single process uses a single seed.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func provenance(for export: SolverExport) -> String {
        let exportedAt = ISO8601DateFormatter().string(from: export.exportedAt)
        return "\(export.generatedSource) · exported \(exportedAt)"
    }

    private func scenario(
        from node: SolverNode,
        in export: SolverExport
    ) throws -> DecisionScenario {
        DecisionScenario(
            id: node.id,
            title: node.title,
            abilityDimension: node.abilityDimension,
            curriculumNodeID: node.curriculumNodeID,
            heroSeatOffsetFromButton: node.heroSeatOffsetFromButton,
            heroCards: try cards(node.heroCards, scenarioID: node.id),
            board: try cards(node.board, scenarioID: node.id),
            decision: BettingDecisionContext(
                pot: node.pot,
                effectiveStack: export.effectiveStack,
                amountToCall: node.amountToCall,
                minimumRaiseTo: node.minimumRaiseTo,
                configuredBetSizes: node.configuredBetSizes
            ),
            options: node.actions.map {
                StrategyOption(
                    action: $0.action,
                    frequencyBasisPoints: $0.frequencyBasisPoints,
                    ev: $0.ev
                )
            },
            rangeCells: node.rangeCells.map {
                RangeCell(
                    handClass: $0.handClass,
                    actionWeightsBasisPoints: $0.actionWeightsBasisPoints
                )
            },
            assumptions: SolverAssumptions(
                gameType: export.gameType,
                tableSize: export.tableSize,
                effectiveStack: export.effectiveStack,
                rakeDescription: export.rakeDescription,
                allowedBetSizeDescription: export.allowedBetSizeDescription
            ),
            explanation: StructuredExplanation(
                conclusion: node.explanation.conclusion,
                rangeReasoning: node.explanation.rangeReasoning,
                boardReasoning: node.explanation.boardReasoning,
                opponentReasoning: node.explanation.opponentReasoning,
                futurePlan: node.explanation.futurePlan,
                gtoBaseline: node.explanation.gtoBaseline,
                exploitCondition: node.explanation.exploitCondition
            )
        )
    }

    private func cards(_ codes: [String], scenarioID: String) throws -> [Card] {
        try codes.map { code in
            guard let card = Card(code: code) else {
                throw PackBuildError.unparseableCard(
                    scenarioID: scenarioID,
                    code: code
                )
            }
            return card
        }
    }
}
