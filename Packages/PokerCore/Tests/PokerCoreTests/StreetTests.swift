import Foundation
import Testing
@testable import PokerCore

@Suite("街道")
struct StreetTests {
    /// Each case's community-card count is fixed by the rules of hold'em; a
    /// wrong value here silently mislabels every derived spot, and the byte-frozen
    /// session goldens depend on these exact mappings.
    @Test("每街的公共牌张数固定为 0/3/4/5")
    func boardCardCountPerStreet() {
        #expect(Street.preflop.boardCardCount == 0)
        #expect(Street.flop.boardCardCount == 3)
        #expect(Street.turn.boardCardCount == 4)
        #expect(Street.river.boardCardCount == 5)
    }

    /// The rawValue strings are part of the serialized contract. They must round
    /// trip so that persisted signatures decode back to the same case.
    @Test("rawValue 往返一致")
    func rawValueRoundTrips() {
        for street in Street.allCases {
            #expect(Street(rawValue: street.rawValue) == street)
        }
    }

    @Test("街道由公共牌张数推出，非法张数被拒绝")
    func derivesStreetFromBoardSize() {
        #expect(Street(boardCardCount: 0) == .preflop)
        #expect(Street(boardCardCount: 3) == .flop)
        #expect(Street(boardCardCount: 4) == .turn)
        #expect(Street(boardCardCount: 5) == .river)

        for illegal in [1, 2, 6, 7, -1] {
            #expect(Street(boardCardCount: illegal) == nil, "\(illegal) 张公共牌不该成立")
        }

        for street in Street.allCases {
            #expect(Street(boardCardCount: street.boardCardCount) == street)
        }
    }
}
