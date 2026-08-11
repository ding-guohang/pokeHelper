import Foundation
import PokerCore
import SessionSimulation

enum SessionFixture {
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "session-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    static func handsFile(in directory: URL, sessionID: UUID) -> URL {
        directory
            .appending(path: sessionID.uuidString, directoryHint: .isDirectory)
            .appending(path: "hands.jsonl", directoryHint: .notDirectory)
    }

    /// The same session played straight through in this process, for the
    /// comparison an interrupted one has to match.
    ///
    /// Deliberately not read back from any store: if the resumed run and the
    /// reference run both came out of the same file, the comparison would be
    /// checking that a file equals itself.
    static func uninterruptedHands(
        record: SessionRecord,
        heroPolicy: any SessionActionPolicy = BaselineActionPolicy()
    ) -> [SessionHandRecord] {
        let runner = SessionRunner(
            seed: record.seed,
            policy: record.policy(heroPolicy: heroPolicy)
        )
        var stacks = SessionRunner.initialStacks
        var hands: [SessionHandRecord] = []
        for handIndex in 0 ..< record.handCount {
            let played = runner.playHand(handIndex: handIndex, stacks: stacks)
            stacks = played.endingStacks
            hands.append(SessionHandRecord(played))
        }
        return hands
    }

    /// Opponent actions as comparable strings: hand, seat, street and action.
    ///
    /// Seat and street included so that two runs which folded the same number
    /// of times in a different order do not compare equal.
    static func opponentActions(_ hands: [SessionHandRecord]) -> [String] {
        hands.flatMap { hand in
            hand.actions
                .filter { $0.seat != TableRules.heroSeat }
                .map { action in
                    "\(hand.handIndex):\(action.seat):\(action.street.rawValue):"
                        + SessionTranscript.describe(action.action)
                }
        }
    }

    static func heroActions(_ hands: [SessionHandRecord]) -> [String] {
        hands.flatMap { hand in
            hand.heroActions.map { "\(hand.handIndex):\(SessionTranscript.describe($0))" }
        }
    }

    static func cards(_ hands: [SessionHandRecord]) -> [String] {
        hands.map { hand in
            let holes = hand.holeCards
                .map { $0.map(\.code).joined() }
                .joined(separator: "/")
            return "\(hand.handIndex) \(holes) | \(hand.board.map(\.code).joined(separator: " "))"
        }
    }
}

/// A hero who is not the default autopilot.
///
/// Used where a rebuild has to prove it is reading the hero's recorded actions
/// rather than re-deriving them: if the test's hero played the same way
/// `BaselineActionPolicy` does, a rebuild that ignored the record entirely
/// would reproduce the session by accident and the test would pass.
///
/// Calls cheaply, checks when it is free and folds to anything expensive. Never
/// raises, so the hero cannot bust and stop turning up in later hands, which
/// would quietly hollow out the very thing being replayed.
struct ScriptedHeroPolicy: SessionActionPolicy {
    static let callCeiling = BBAmount(centiBB: 200)

    func chooseAction(
        at decision: DecisionPoint,
        using _: inout SplitMix64
    ) -> DecisionAction {
        let actions = decision.orderedLegalActions
        if actions.contains(.check) {
            return .check
        }
        if decision.context.amountToCall <= Self.callCeiling,
           let call = actions.first(where: { if case .call = $0 { true } else { false } }) {
            return call
        }
        if actions.contains(.fold) {
            return .fold
        }
        return actions[0]
    }
}
