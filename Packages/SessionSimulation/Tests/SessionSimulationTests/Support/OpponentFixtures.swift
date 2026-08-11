import Foundation
import PokerCore
@testable import SessionSimulation

/// Reads the committed fixtures under `Tests/Fixtures/`.
///
/// The files are read from disk rather than bundled as SwiftPM resources so
/// that they sit at the paths the spec names, and are located from this file's
/// own position rather than from the working directory — a test does not choose
/// its working directory.
enum OpponentFixtures {
    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)
        case malformed(spot: Int, reason: String)

        var description: String {
            switch self {
            case let .missing(path):
                "夹具缺失：\(path)"
            case let .malformed(spot, reason):
                "第 \(spot) 个局面无效：\(reason)"
            }
        }
    }

    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpponentFixtures.swift
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // SessionSimulationTests
            .appendingPathComponent("Fixtures")
    }
    // MARK: - The twenty fixed spots

    struct SpotSet: Decodable {
        /// Where the twenty came from. Prose, not asserted — the file is the
        /// fixed set, and this says how it was arrived at.
        let provenance: String
        let spots: [Spot]
    }

    /// One spot, flat enough to read in a diff.
    ///
    /// Deliberately stores the betting context rather than a whole hand state:
    /// what a policy sees is the context and the cards, and a fixture that
    /// stored a hand state would be asserting things about the state machine
    /// instead of about the opponents.
    struct Spot: Decodable, Hashable {
        let id: Int
        let label: String
        let handIndex: Int
        let seatOffsetFromButton: Int
        let street: String
        let facing: String
        let holeCards: [String]
        let board: [String]
        let potCentiBB: Int
        let effectiveStackCentiBB: Int
        let amountToCallCentiBB: Int
        let minimumRaiseToCentiBB: Int?
        let configuredBetSizesCentiBB: [Int]

        /// The generator seed every profile is given at this spot. One seed per
        /// spot, shared by all four, so a difference between two profiles is a
        /// difference of choice rather than of dice.
        let rngSeed: UInt64

        /// Rebuilds the decision point.
        ///
        /// The legal set is **recomputed** from the context rather than read
        /// out of the file. A fixture that carried its own answer to "what is
        /// legal here" could drift from the state machine, and every legality
        /// assertion in this suite would then be checking the fixture against
        /// itself.
        func decisionPoint() throws -> DecisionPoint {
            let hole = try holeCards.map { try card($0) }
            let boardCards = try board.map { try card($0) }
            guard hole.count == 2 else {
                throw FixtureError.malformed(spot: id, reason: "底牌不是两张")
            }
            guard Set(hole + boardCards).count == hole.count + boardCards.count else {
                throw FixtureError.malformed(spot: id, reason: "同一局面里出现了重复的牌")
            }
            guard let street = Street(rawValue: street) else {
                throw FixtureError.malformed(spot: id, reason: "未知街道 \(street)")
            }
            guard boardCards.count == street.boardCardCount else {
                throw FixtureError.malformed(
                    spot: id,
                    reason: "\(street.rawValue) 应有 \(street.boardCardCount) 张公共牌，实际 \(boardCards.count)"
                )
            }
            guard let facing = FacingAction(rawValue: facing) else {
                throw FixtureError.malformed(spot: id, reason: "未知面对情形 \(facing)")
            }
            guard amountToCallCentiBB <= effectiveStackCentiBB else {
                throw FixtureError.malformed(spot: id, reason: "须跟注额超过有效筹码")
            }

            let context = BettingDecisionContext(
                pot: BBAmount(centiBB: potCentiBB),
                effectiveStack: BBAmount(centiBB: effectiveStackCentiBB),
                amountToCall: BBAmount(centiBB: amountToCallCentiBB),
                minimumRaiseTo: minimumRaiseToCentiBB.map { BBAmount(centiBB: $0) },
                configuredBetSizes: configuredBetSizesCentiBB.map { BBAmount(centiBB: $0) }
            )
            let handClass = HandClass(hole[0], hole[1])

            return DecisionPoint(
                handIndex: handIndex,
                seat: TableRules.seat(atOffset: seatOffsetFromButton, buttonSeat: 0),
                seatOffsetFromButton: seatOffsetFromButton,
                street: street,
                holeCards: hole,
                board: boardCards,
                pot: BBAmount(centiBB: potCentiBB),
                context: context,
                legalActions: context.legalActions(),
                facing: facing,
                handClass: handClass,
                signature: SpotSignature(
                    street: street,
                    heroSeatOffsetFromButton: seatOffsetFromButton,
                    handClass: handClass,
                    facing: facing,
                    stackBucket: StackBucket(
                        effectiveStack: BBAmount(centiBB: effectiveStackCentiBB)
                    )
                )
            )
        }

        private func card(_ code: String) throws -> Card {
            guard let card = Card(code: code) else {
                throw FixtureError.malformed(spot: id, reason: "无法解析的牌 \(code)")
            }
            return card
        }
    }

    static func loadSpotSet() throws -> SpotSet {
        try decode(SpotSet.self, from: "opponent-spots-20.json")
    }

    // MARK: - The per-profile golden sequences

    static func loadGolden(_ id: OpponentProfileID) throws -> OpponentActionGolden {
        try decode(OpponentActionGolden.self, from: "opponent-\(id.rawValue)-seed42.json")
    }

    /// How to rebuild a golden sequence, quoted in failure messages so that the
    /// fix is in front of whoever broke it.
    static func regenerationCommand(_ id: OpponentProfileID) -> String {
        "swift run session-transcript --profile \(id.rawValue) --seed 42 --hands 30 --golden "
            + "> Tests/Fixtures/opponent-\(id.rawValue)-seed42.json"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let url = fixtureDirectory.appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw FixtureError.missing(url.path)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
