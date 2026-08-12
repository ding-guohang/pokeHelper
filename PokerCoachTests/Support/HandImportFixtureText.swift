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
}
