import HandHistory
import PokerCore
import XCTest
@testable import PokerCoach

/// The street-by-street replay of an imported hand is a verbatim copy of what
/// the parser recorded: the streets actually reached, each with its own visible
/// board and its own voluntary actions, in order. No pot is derived, no street
/// is padded, no action is invented.
final class HandReplayTests: XCTestCase {
    // GIVEN 附录 A（干净四街的现金手）
    // WHEN 逐街回放
    // THEN 四街、序 [翻前,翻牌,转牌,河牌]、每街 board/行动逐字等于记录
    func testAppendixAReplaysFourStreetsVerbatim() throws {
        let hand = try ObservedHand.parsed(HandImportFixtureText.appendixA)
        let streets = replayStreets(of: hand)

        // Self-check: the replay actually produced streets, so the assertions
        // below are about content rather than satisfied by an empty result.
        XCTAssertFalse(streets.isEmpty, "回放应产出街，实测为空")

        XCTAssertEqual(streets.count, 4)
        XCTAssertEqual(streets.map(\.street), [.preflop, .flop, .turn, .river])

        // Board grows street by street — the flop's three, the turn's four, the
        // river's five — never the final board on every street.
        XCTAssertEqual(streets[0].board.map(\.code), [])
        XCTAssertEqual(streets[1].board.map(\.code), ["Ac", "7h", "2s"])
        XCTAssertEqual(streets[2].board.map(\.code), ["Ac", "7h", "2s", "Td"])
        XCTAssertEqual(streets[3].board.map(\.code), ["Ac", "7h", "2s", "Td", "9c"])

        // Every voluntary action on every street, not only the hero's.
        XCTAssertEqual(streets.map(\.actions.count), [6, 3, 2, 3])

        // Each street's actions equal the observed street's, element for element
        // (seat, kind, amount) — a verbatim copy.
        for (index, street) in streets.enumerated() {
            XCTAssertEqual(
                street.actions,
                hand.streets[index].actions,
                "第 \(index) 街的行动应与记录逐一相同"
            )
        }
    }

    // GIVEN 附录 I（CO 开池后众人弃牌，翻前结束）
    // WHEN 逐街回放
    // THEN 只有一街、board 为空，不补空街
    func testPreflopOnlyHandReplaysExactlyOneStreet() throws {
        let hand = try ObservedHand.parsed(HandImportFixtureText.coOpenTrash)
        let streets = replayStreets(of: hand)

        XCTAssertEqual(streets.count, 1)
        XCTAssertEqual(streets[0].street, .preflop)
        XCTAssertTrue(streets[0].board.isEmpty)
        XCTAssertEqual(streets[0].actions, hand.streets[0].actions)
    }
}
