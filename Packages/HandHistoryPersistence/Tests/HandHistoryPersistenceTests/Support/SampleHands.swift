import Foundation
import HandHistory

/// Two distinct `ObservedHand`s built by parsing real PokerStars text through
/// `PokerStarsParser`, so the identities under test are the real SHA-256 of the
/// raw text rather than hand-written stand-ins.
///
/// `handA` is the pinned appendix-A sample. `handB` is the same hand with a
/// different hand number and different hero cards — a genuinely different text,
/// so its identity differs from `handA` while it still parses cleanly.
enum SampleHands {
    enum SampleError: Error, CustomStringConvertible {
        case notParsed(String)
        case hasConflicts(String)

        var description: String {
            switch self {
            case let .notParsed(name): "样例未能解析为模型：\(name)"
            case let .hasConflicts(name): "样例解析出冲突，不该发生：\(name)"
            }
        }
    }

    static let rawA = """
    PokerStars Hand #240000000001:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 20:00:00 ET
    Table 'Andromeda' 6-max Seat #1 is the button
    Seat 1: Hero ($100 in chips)
    Seat 2: Villain2 ($100 in chips)
    Seat 3: Villain3 ($100 in chips)
    Seat 4: Villain4 ($100 in chips)
    Seat 5: Villain5 ($100 in chips)
    Seat 6: Villain6 ($100 in chips)
    Villain2: posts small blind $0.50
    Villain3: posts big blind $1
    *** HOLE CARDS ***
    Dealt to Hero [Ah Kd]
    Villain4: folds
    Villain5: folds
    Villain6: folds
    Hero: raises $2 to $3
    Villain2: folds
    Villain3: calls $2
    *** FLOP *** [Ac 7h 2s]
    Villain3: checks
    Hero: bets $4
    Villain3: calls $4
    *** TURN *** [Ac 7h 2s] [Td]
    Villain3: checks
    Hero: checks
    *** RIVER *** [Ac 7h 2s Td] [9c]
    Villain3: checks
    Hero: bets $8
    Villain3: folds
    Uncalled bet ($8) returned to Hero
    Hero collected $14 from pot
    *** SUMMARY ***
    Total pot $14.50 | Rake $0.50
    """

    /// A different valid hand: distinct hand number and hero cards, so the
    /// normalized SHA-256 identity differs from `rawA`.
    static let rawB = """
    PokerStars Hand #240000000002:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 20:05:00 ET
    Table 'Andromeda' 6-max Seat #1 is the button
    Seat 1: Hero ($100 in chips)
    Seat 2: Villain2 ($100 in chips)
    Seat 3: Villain3 ($100 in chips)
    Seat 4: Villain4 ($100 in chips)
    Seat 5: Villain5 ($100 in chips)
    Seat 6: Villain6 ($100 in chips)
    Villain2: posts small blind $0.50
    Villain3: posts big blind $1
    *** HOLE CARDS ***
    Dealt to Hero [Qs Qh]
    Villain4: folds
    Villain5: folds
    Villain6: folds
    Hero: raises $2 to $3
    Villain2: folds
    Villain3: calls $2
    *** FLOP *** [Ac 7h 2s]
    Villain3: checks
    Hero: bets $4
    Villain3: calls $4
    *** TURN *** [Ac 7h 2s] [Td]
    Villain3: checks
    Hero: checks
    *** RIVER *** [Ac 7h 2s Td] [9c]
    Villain3: checks
    Hero: bets $8
    Villain3: folds
    Uncalled bet ($8) returned to Hero
    Hero collected $14 from pot
    *** SUMMARY ***
    Total pot $14.50 | Rake $0.50
    """

    static func parse(_ raw: String, name: String) throws -> ObservedHand {
        switch PokerStarsParser.parse(raw) {
        case let .parsed(hand, conflicts):
            guard conflicts.isEmpty else { throw SampleError.hasConflicts(name) }
            return hand
        case .unsupported:
            throw SampleError.notParsed(name)
        }
    }

    static func handA() throws -> ObservedHand { try parse(rawA, name: "A") }
    static func handB() throws -> ObservedHand { try parse(rawB, name: "B") }
}
