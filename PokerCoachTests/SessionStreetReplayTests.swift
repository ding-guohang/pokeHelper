import Foundation
import PokerCore
import SessionSimulation
import XCTest
@testable import PokerCoach

/// Playing a key hand back one street at a time.
///
/// The capability sentence — "the user can look through the streets" — is
/// satisfied by a screen that prints the final board and the final pot four
/// times, so none of these assertions is about a street *existing*. They are
/// about the three numbers a street carries being that street's: its own board,
/// its own closing pot, and only the actions taken on it.
///
/// ## Where the expected numbers come from
///
/// Seed 16 played fifteen hands against the shipped pack. Its second hand
/// reached the river with betting on every street, which is exactly the hand
/// the spec's scenario describes and is rarer than it sounds — most hands end
/// before the flop, and most that do not are all-in by the turn with nothing
/// left to bet. The pots below were measured from that hand and are written out
/// rather than recomputed from the record: a test that derives its expectation
/// the same way the code does agrees with the code by construction.
final class SessionStreetReplayTests: XCTestCase {
    private let seed: UInt64 = 16
    private let handCount = 15

    /// The hand the spec describes: four streets, four boards, four pots, and
    /// the actions belonging to each.
    @MainActor
    func testAKeyHandThatReachedTheRiverShowsEachStreetsOwnBoardPotAndActions() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let review = try played.review(handIndex: 2)
        let hand = try played.hand(2)

        XCTAssertEqual(hand.result.streetReached, .river, "这一手没打到河牌，夹具选错了")
        XCTAssertEqual(review.streets.map(\.street), [.preflop, .flop, .turn, .river])

        // 0 / 3 / 4 / 5, and each street's board is a prefix of the next one's
        // rather than four copies of the final board.
        XCTAssertEqual(review.streets.map(\.board.count), [0, 3, 4, 5])
        for street in review.streets {
            XCTAssertEqual(
                street.board,
                Array(hand.board.prefix(street.street.boardCardCount)),
                "\(street.id) 显示的公共牌不是该街道当时的牌"
            )
        }

        // Each street's closing pot. Four different numbers, so a screen
        // showing the final pot on every street fails here.
        XCTAssertEqual(
            review.streets.map(\.potAtEnd.centiBB),
            [1_100, 3_300, 9_900, 19_800]
        )
        XCTAssertEqual(
            Set(review.streets.map(\.potAtEnd)).count,
            4,
            "四个街道的底池不是四个不同的数"
        )
        XCTAssertEqual(
            review.streets.last?.potAtEnd,
            hand.result.potTotal,
            "最后一个街道的底池应当等于整手的底池"
        )

        // Only the actions taken on that street, in the order they were taken.
        XCTAssertEqual(review.streets.map(\.actions.count), [7, 3, 3, 3])
        for street in review.streets {
            let recorded = hand.actions.filter { $0.street == street.street }
            XCTAssertEqual(
                street.actions.map(\.actionTitle),
                recorded.map(\.action.displayTitle),
                "\(street.id) 显示的行动与该街道实际发生的行动不一致"
            )
            XCTAssertEqual(
                street.actions.map(\.potAfterText),
                recorded.map(\.potAfter.displayText)
            )
        }

        // And the hero is named as the hero on the actions that were theirs.
        let heroLines = review.streets.flatMap(\.actions).filter(\.isHero)
        XCTAssertEqual(heroLines.count, hand.heroActions.count)
        XCTAssertFalse(heroLines.isEmpty, "英雄一次都没行动，上面的断言是空转的")
        for line in heroLines {
            XCTAssertTrue(line.actorLabel.hasPrefix("你"), line.actorLabel)
        }

        // Opponents are named by position and by the profile that seat is
        // playing — which is the point of disclosing the profiles at all. A
        // three-bet from the maniac and one from the rock are different facts
        // about the hand.
        let opponentLines = review.streets.flatMap(\.actions).filter { !$0.isHero }
        XCTAssertFalse(opponentLines.isEmpty, "没有对手行动，下面的断言是空转的")
        let profileNames = Set(OpponentProfileTable.profiles.map(\.name))
        for line in opponentLines {
            XCTAssertTrue(
                profileNames.contains { line.actorLabel.hasSuffix($0) },
                "对手行动 \(line.actorLabel) 没有写明它是哪一种档案"
            )
        }
        // The seats really are playing different profiles here, so a label that
        // printed one fixed name would not satisfy the loop above by accident.
        XCTAssertGreaterThan(
            Set(opponentLines.map(\.actorLabel)).count,
            1
        )
        XCTAssertGreaterThan(
            Set(profileNames.filter { name in
                opponentLines.contains { $0.actorLabel.hasSuffix(name) }
            }).count,
            1,
            "这一手的对手全是同一种档案，档案名无从区分"
        )
    }

    /// A street nobody could bet on keeps the pot it inherited.
    ///
    /// Seed 16's tenth hand is all in before the flop, so the turn and the
    /// river have no actions at all. Carrying the pot forward is the only
    /// honest answer: the pot at the end of that street really was that. Zero
    /// would be a lie, and it is what a naive "last action on this street"
    /// lookup returns.
    @MainActor
    func testAStreetWithNoBettingKeepsThePotItInherited() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let review = try played.review(handIndex: 9)

        XCTAssertEqual(review.streets.map(\.actions.count), [8, 0, 0, 0])
        XCTAssertEqual(
            review.streets.map(\.potAtEnd.centiBB),
            [11_250, 11_250, 11_250, 11_250]
        )
    }

    /// A hand that ended before the flop has one street, not four.
    ///
    /// Padding it out to four would put three empty boards and three repeats of
    /// the same pot in front of the user and call it a replay.
    @MainActor
    func testAHandThatEndedPreflopHasOnlyThePreflopStreet() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let foldedOut = try XCTUnwrap(
            played.hands.first { $0.result.streetReached == .preflop },
            "这一局没有在翻前结束的手牌，断言无从谈起"
        )

        let streets = KeyHandReviewBuilder.streets(
            of: foldedOut,
            seating: played.record.seating
        )
        XCTAssertEqual(streets.map(\.street), [.preflop])
        XCTAssertEqual(streets[0].board, [])
        XCTAssertGreaterThan(
            streets[0].potAtEnd.centiBB,
            0,
            "翻前结束的手牌底池为 0，盲注不见了"
        )
    }

    /// A hand nobody was asked to act in still shows the blinds that went in.
    ///
    /// Blind posts are not in the action log, so the pot before the first
    /// logged action has to be computed. Every hand these seeds deal has
    /// preflop betting, which overwrites that starting value immediately — so
    /// the only way to observe it is a hand with no actions at all. That is
    /// reachable: a busted seat stays at zero for the rest of the session, and
    /// with one seat left holding chips the state machine asks nobody to act.
    /// It is also rare enough that no seed in this suite produces one, so the
    /// record is built by editing a real one into that shape rather than waited
    /// for.
    ///
    /// The short small blind is the second half: it posts what it has, not what
    /// it owes, so 0.2BB + 1BB is 1.2BB and not 1.5BB.
    @MainActor
    func testAHandNobodyCouldActInStillShowsTheBlindsThatWerePosted() async throws {
        let played = try await SessionReviewFixture.play(seed: seed, handCount: handCount)
        let hand = try played.hand(0)
        XCTAssertFalse(hand.actions.isEmpty, "起点这一手本来就没有行动，编辑没有意义")

        let smallBlindSeat = TableRules.seat(atOffset: 1, buttonSeat: hand.buttonSeat)
        let bigBlindSeat = TableRules.seat(atOffset: 2, buttonSeat: hand.buttonSeat)
        let walk = try Self.editing(hand) { json in
            json["actions"] = []
            var stacks = [[String: Int]](
                repeating: ["centiBB": 0],
                count: TableRules.seatCount
            )
            stacks[smallBlindSeat] = ["centiBB": 20]
            stacks[bigBlindSeat] = ["centiBB": 10_000]
            json["startingStacks"] = stacks
            var result = json["result"] as! [String: Any]
            result["streetReached"] = "preflop"
            result["board"] = []
            result["potTotal"] = ["centiBB": 120]
            json["result"] = result
            json["board"] = []
        }

        let streets = KeyHandReviewBuilder.streets(
            of: walk,
            seating: played.record.seating
        )
        XCTAssertEqual(streets.map(\.street), [.preflop])
        XCTAssertEqual(streets.map(\.actions.count), [0])
        XCTAssertEqual(
            streets[0].potAtEnd.centiBB,
            120,
            "无人行动的一手底池是 \(streets[0].potAtEnd.centiBB)，应当是实际贴出的 0.2BB + 1BB"
        )
    }

    /// A stored record with some of its fields rewritten.
    ///
    /// Through the record's own JSON, which is how the store produces one —
    /// `SessionHandRecord` is only constructible from a `PlayedHand`, and a
    /// `PlayedHand` is only constructible by the engine.
    private static func editing(
        _ hand: SessionHandRecord,
        _ edit: (inout [String: Any]) -> Void
    ) throws -> SessionHandRecord {
        let encoded = try JSONEncoder().encode(hand)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        edit(&json)
        return try JSONDecoder().decode(
            SessionHandRecord.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )
    }

    /// The same three properties over every hand of twelve sessions.
    ///
    /// The pinned hand above is one shape. This is the claim that the shape is
    /// general: streets stop where the hand stopped, boards are the prefixes
    /// they should be, and the streets between them partition the action log —
    /// every action shown exactly once, on the street it happened on.
    @MainActor
    func testEveryHandsStreetsPartitionItsActionsAndMatchItsBoard() async throws {
        var streetCountsSeen: Set<Int> = []
        var handsChecked = 0

        for seed in UInt64(1) ... 12 {
            let played = try await SessionReviewFixture.play(seed: seed, handCount: 15)
            for hand in played.hands {
                let streets = KeyHandReviewBuilder.streets(
                    of: hand,
                    seating: played.record.seating
                )
                handsChecked += 1
                streetCountsSeen.insert(streets.count)

                XCTAssertEqual(
                    streets.count,
                    hand.result.streetReached.boardCardCount == 0
                        ? 1
                        : hand.result.streetReached.boardCardCount - 1,
                    "第 \(hand.handIndex) 手打到 \(hand.result.streetReached)，却给了 \(streets.count) 个街道"
                )
                XCTAssertEqual(
                    streets.map(\.board.count),
                    streets.map(\.street.boardCardCount)
                )
                XCTAssertEqual(
                    streets.flatMap(\.actions).map(\.actionTitle),
                    hand.actions.map(\.action.displayTitle),
                    "第 \(hand.handIndex) 手的行动没有被四个街道恰好分完"
                )
                XCTAssertEqual(
                    streets.map(\.potAtEnd),
                    streets.map(\.potAtEnd).sorted { $0.centiBB < $1.centiBB },
                    "第 \(hand.handIndex) 手的底池在某个街道上变小了"
                )
                XCTAssertEqual(streets.last?.potAtEnd, hand.result.potTotal)
            }
        }

        XCTAssertGreaterThan(handsChecked, 150)
        XCTAssertEqual(
            streetCountsSeen,
            [1, 2, 3, 4],
            "十二局里没有跑到全部四种街道深度，属性只在一部分形态上验证过：\(streetCountsSeen.sorted())"
        )
    }
}
