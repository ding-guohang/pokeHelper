/// Hand-history texts for the app-layer import tests, copied verbatim from the
/// `HandHistory` package fixtures so the app tests pin the same input the parser
/// tests do. Kept in the test target only.
enum HandImportFixtureText {
    /// Appendix A: a clean 6-max NLHE cash hand with a non-zero rake. Byte-for-
    /// byte the `sample-ps-6max-nlhe.txt` fixture, trailing newline included.
    static let appendixA = """
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

    /// Appendix B: appendix A with only the hero's preflop verb on line 16
    /// changed to an unrecognized word. Exactly one conflict, on that line.
    static let appendixB = appendixA.replacingOccurrences(
        of: "Hero: raises $2 to $3",
        with: "Hero: sprais $2 to $3"
    )

    /// The 1-based line the hero's preflop action sits on in both appendices.
    static let heroPreflopLine = 16

    /// Two unrecognized verbs — the hero's preflop action (line 16) and the
    /// hero's flop bet (line 21) — so exactly two conflicts are expected.
    static let twoConflicts = appendixA
        .replacingOccurrences(of: "Hero: raises $2 to $3", with: "Hero: sprais $2 to $3")
        .replacingOccurrences(of: "Hero: bets $4", with: "Hero: sbets $4")

    static let heroFlopLine = 21

    /// Two unrecognized verbs on the SAME street (preflop): Villain4's fold
    /// (line 13) and the hero's raise (line 16). Resolving both must reinsert
    /// them in their original positions regardless of the order the user
    /// resolves them, which only holds if the rebuild is order-independent.
    static let twoPreflopConflicts = appendixA
        .replacingOccurrences(of: "Villain4: folds", with: "Villain4: xfolds")
        .replacingOccurrences(of: "Hero: raises $2 to $3", with: "Hero: sprais $2 to $3")

    /// The 1-based line Villain4's preflop fold sits on.
    static let villain4PreflopLine = 13

    /// Appendix G: appendix A with the hero holding `3s 2d` instead of `Ah Kd`.
    /// Everything else — the button seat, the unopened BTN open, the streets —
    /// is byte-for-byte appendix A, so the only thing that changes is the hand
    /// class the preflop open is judged against.
    ///
    /// `32o` is absent from the shipped `rfi-btn` range table, which the loader
    /// reads as "this range folds 32o 100% of the time": an open of it looks the
    /// weight up as 0 out of 10,000, a deviation of the full 10,000 magnitude.
    /// Verified against `CoreStrategyPack.json` at implementation time — 32o has
    /// no cell in rfi-btn, so `rangeWeightBasisPoints(action: .raise)` returns 0.
    static let btnOpenTrash = appendixA.replacingOccurrences(
        of: "Dealt to Hero [Ah Kd]",
        with: "Dealt to Hero [3s 2d]"
    )

    /// Appendix I: the hero opens `32o` from the cutoff. The seats mirror
    /// appendix A's 6-max table, but the hero sits on Seat 6 — the cutoff, offset
    /// 5 from the button — and is first in: the two players before them (UTG and
    /// the hijack) fold, the hero raises, and everyone behind folds. The coverage
    /// key for that decision therefore resolves to `rfi-co`, not `rfi-btn`, which
    /// is the whole point: it is a different covering scenario from appendix G's
    /// button open.
    ///
    /// `32o` has no cell in the shipped `rfi-co` range table either, so opening
    /// it looks the weight up as 0 out of 10,000 — a full 10,000-magnitude
    /// deviation, covered by `rfi-co`. Verified against `CoreStrategyPack.json`
    /// at implementation time: 32o has no cell in rfi-co.
    static let coOpenTrash = """
    PokerStars Hand #240000000009:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 20:45:00 ET
    Table 'Cassiopeia' 6-max Seat #1 is the button
    Seat 1: Villain1 ($100 in chips)
    Seat 2: Villain2 ($100 in chips)
    Seat 3: Villain3 ($100 in chips)
    Seat 4: Villain4 ($100 in chips)
    Seat 5: Villain5 ($100 in chips)
    Seat 6: Hero ($100 in chips)
    Villain2: posts small blind $0.50
    Villain3: posts big blind $1
    *** HOLE CARDS ***
    Dealt to Hero [3s 2d]
    Villain4: folds
    Villain5: folds
    Hero: raises $2 to $3
    Villain1: folds
    Villain2: folds
    Villain3: folds
    Uncalled bet ($2) returned to Hero
    Hero collected $1.50 from pot
    *** SUMMARY ***
    Total pot $1.50 | Rake $0

    """

    /// Appendix H: the hero commits their whole starting stack. After a $3
    /// preflop open and a $4 flop bet the hero has $93 left, and the $93 turn
    /// bet brings their committed chips to exactly their $100 start. `isAllIn`
    /// is decided by that arithmetic — committed reaching the starting stack —
    /// not by any "all-in" wording, so no such wording appears.
    static let heroAllIn = """
    PokerStars Hand #240000000008:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 20:30:00 ET
    Table 'Lyra' 6-max Seat #1 is the button
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
    Hero: bets $93
    Villain3: folds
    Uncalled bet ($93) returned to Hero
    Hero collected $14 from pot
    *** SUMMARY ***
    Total pot $14.50 | Rake $0.50

    """

    /// A constructed hand in which the hero makes six voluntary decisions, one
    /// more than the key-node cap of five. The hero opens the button, calls a
    /// 3-bet, bets the flop, calls a flop raise, bets the turn and bets the
    /// river — six weight-bearing actions across four streets. Their coverage
    /// keys are all distinct (street × facing pairs never repeat), so a content
    /// fixture built from the parsed signatures can cover each node
    /// independently and mark all six as sub-threshold deviations; the selection
    /// must then drop the smallest and keep exactly five, magnitude-descending.
    /// The hero commits $12 + $30 + $20 + $10 = $72 of a $100 stack, so no node
    /// is an all-in that would add a seventh reason.
    static let sixDeviations = """
    PokerStars Hand #240000000020:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 23:00:00 ET
    Table 'Orion' 6-max Seat #1 is the button
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
    Villain3: raises $9 to $12
    Hero: calls $9
    *** FLOP *** [8d 5c 2h]
    Villain3: checks
    Hero: bets $10
    Villain3: raises $20 to $30
    Hero: calls $20
    *** TURN *** [8d 5c 2h] [Ks]
    Villain3: checks
    Hero: bets $20
    Villain3: calls $20
    *** RIVER *** [8d 5c 2h Ks] [4c]
    Villain3: checks
    Hero: bets $10
    Villain3: folds
    Uncalled bet ($10) returned to Hero
    Hero collected $64 from pot
    *** SUMMARY ***
    Total pot $64 | Rake $0

    """
}
