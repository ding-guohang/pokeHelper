import Foundation
import PokerCore
import StrategyContent

/// Hand-class arithmetic shared by the content audit.
///
/// These live beside the importer rather than in `StrategyContent` because they
/// reason about *authoring* notation — "AKs-AJs", "99-77" — which the shipped
/// content model never sees. The app only ever loads expanded packs.
public enum ContentAudit {
    /// Ranks high to low, so a range written "AKs-AJs" walks downward.
    public static let ranks = Array("AKQJT98765432")

    /// Total two-card combinations in a 52-card deck.
    public static let totalCombinations = 1_326

    public static func combinations(of hand: String) -> Int {
        if hand.count == 2, hand.first == hand.last {
            return 6
        }
        return hand.hasSuffix("s") ? 4 : 12
    }

    /// Expands authoring notation into individual hand classes.
    ///
    /// Supports a bare class ("AKs"), a pair range ("99-77") and a
    /// fixed-high-card range ("AKs-AJs", "AKo-A2o"). Anything else is returned
    /// as written so an unrecognised form shows up in a failing assertion
    /// rather than being silently dropped from the total.
    public static func expand(_ handClass: String) -> [String] {
        guard let separator = handClass.firstIndex(of: "-") else {
            return [handClass]
        }
        let high = String(handClass[handClass.startIndex ..< separator])
        let low = String(handClass[handClass.index(after: separator)...])

        if isPair(high), isPair(low) {
            return between(high.first!, low.first!).map { "\($0)\($0)" }
        }
        if let (highCard, highKicker, suitedness) = parse(high),
           let (lowCard, lowKicker, lowSuitedness) = parse(low),
           highCard == lowCard,
           suitedness == lowSuitedness
        {
            return between(highKicker, lowKicker).map {
                "\(highCard)\($0)\(suitedness)"
            }
        }
        return [high, low]
    }

    /// Combination-weighted aggression across a range table, in basis points of
    /// all 1,326 starting combinations.
    public static func combinationWeightedBasisPoints(
        _ cells: [SolverRangeCell]
    ) -> Int {
        var weighted = 0
        for cell in cells {
            let aggression = cell.actionWeightsBasisPoints
                .filter { $0.key != "fold" }
                .values
                .reduce(0, +)
            for hand in expand(cell.handClass) {
                weighted += combinations(of: hand) * aggression
            }
        }
        return weighted / totalCombinations
    }

    public static func handsWithNonZeroAggression(
        _ cells: [SolverRangeCell]
    ) -> Set<String> {
        var hands: Set<String> = []
        for cell in cells {
            let aggression = cell.actionWeightsBasisPoints
                .filter { $0.key != "fold" }
                .values
                .reduce(0, +)
            guard aggression > 0 else { continue }
            hands.formUnion(expand(cell.handClass))
        }
        return hands
    }

    /// How much of the range that opened continues when facing a raise, in
    /// basis points of the opening range.
    ///
    /// Weighted by the opening frequency of each hand: a hand opened half the
    /// time reaches this node half as often, and counting it whole would report
    /// a defence that does not exist.
    public static func continuationBasisPoints(
        facing: [SolverRangeCell],
        openedWith opening: [SolverRangeCell]
    ) -> Int {
        var openWeights: [String: Int] = [:]
        for cell in opening {
            let aggression = cell.actionWeightsBasisPoints
                .filter { $0.key != "fold" }
                .values
                .reduce(0, +)
            for hand in expand(cell.handClass) {
                openWeights[hand] = aggression
            }
        }

        var opened = 0
        var continued = 0
        for (hand, weight) in openWeights where weight > 0 {
            let reach = combinations(of: hand) * weight
            opened += reach

            let response = facing.first { expand($0.handClass).contains(hand) }
            let continuing = (response?.actionWeightsBasisPoints ?? [:])
                .filter { $0.key != "fold" }
                .values
                .reduce(0, +)
            continued += reach / 10_000 * continuing
        }
        guard opened > 0 else { return 0 }
        return continued * 10_000 / opened
    }

    /// The hand class covering a concrete two-card holding, e.g. Ad Kc → AKo.
    public static func rangeCell(
        forHeroHand cards: [String],
        in cells: [SolverRangeCell]
    ) -> SolverRangeCell? {
        guard let hand = handClass(for: cards) else { return nil }
        return cells.first { expand($0.handClass).contains(hand) }
    }

    public static func handClass(for cards: [String]) -> String? {
        guard cards.count == 2,
              let first = cards.first.flatMap(Card.init(code:)),
              let second = cards.last.flatMap(Card.init(code:))
        else {
            return nil
        }

        let firstRank = String(cards[0].prefix(1)).uppercased()
        let secondRank = String(cards[1].prefix(1)).uppercased()
        guard let firstIndex = ranks.firstIndex(of: Character(firstRank)),
              let secondIndex = ranks.firstIndex(of: Character(secondRank))
        else {
            return nil
        }

        if firstRank == secondRank {
            return firstRank + secondRank
        }
        let high = firstIndex < secondIndex ? firstRank : secondRank
        let low = firstIndex < secondIndex ? secondRank : firstRank
        let suited = first.suit == second.suit
        return "\(high)\(low)\(suited ? "s" : "o")"
    }

    /// The key a range table uses for an action, matching the shipped
    /// development pack's convention ("check", "bet-217", "raise", "fold").
    public static func rangeKey(for action: DecisionAction) -> String {
        switch action {
        case .fold: "fold"
        case .check: "check"
        case .call: "call"
        case .bet: "bet"
        case .raise: "raise"
        case .allIn: "all-in"
        }
    }

    public static func isAggressive(_ action: DecisionAction) -> Bool {
        switch action {
        case .fold, .check, .call: false
        case .bet, .raise, .allIn: true
        }
    }

    /// The bet-tree size an action commits to, or nil when the amount is not a
    /// declared sizing.
    ///
    /// A call's associated value is the amount owed, which the pot state
    /// determines — `legalActions()` builds it as `.call(to: amountToCall)`.
    /// An all-in is the stack. Neither belongs in a bet tree, and checking them
    /// against one would fail correct content.
    public static func targetCentiBB(_ action: DecisionAction) -> Int? {
        switch action {
        case .fold, .check, .call, .allIn: nil
        case let .bet(to), let .raise(to): to.centiBB
        }
    }

    /// Position labels a title might name, longest first so "UTG+1" is not
    /// matched as "UTG".
    private static let positionLabels = [
        "UTG+2", "UTG+1", "BTN", "UTG", "SB", "BB", "LJ", "HJ", "CO",
    ]

    /// The hero's position, taken as the first label that appears in the title.
    ///
    /// Earliest by position in the string, not by order in the list above: a
    /// title like "CO 开池面对 BTN 3bet" names two positions and the hero is the
    /// one it opens with.
    public static func positionMentioned(in title: String) -> String? {
        positionLabels
            .compactMap { label -> (Int, String)? in
                guard let range = title.range(of: label) else { return nil }
                return (title.distance(from: title.startIndex, to: range.lowerBound), label)
            }
            .min { $0.0 < $1.0 }?
            .1
    }

    /// The range-wide frequency a scenario's prose claims, in basis points.
    ///
    /// Since option frequencies became per-hand, this is the only place a claim
    /// about the whole range survives — so it is the thing that has to match
    /// what the range table actually weighs.
    public static func statedFrequencyBasisPoints(in prose: String) -> Int? {
        guard let percentRange = prose.range(of: "%") else { return nil }
        let head = prose[prose.startIndex ..< percentRange.lowerBound]
        let digits = head.reversed().prefix { $0.isNumber || $0 == "." }
        let text = String(digits.reversed())
        guard let value = Double(text) else { return nil }
        return Int((value * 100).rounded())
    }

    /// Bet sizes named in a prose bet-tree description, in big blinds.
    ///
    /// Multipliers such as "3x 3bet" are resolved against the open size, which
    /// is why the description has to state the open in BB.
    public static func declaredSizesBB(_ description: String) -> [Double] {
        var sizes: [Double] = []
        let scanner = description.replacingOccurrences(of: ",", with: " ")

        var openSize: Double?
        // Punctuation is stripped first: a size written "(3BB from SB)" would
        // otherwise be skipped because the token starts with a bracket.
        let punctuation = CharacterSet(charactersIn: "()，,。;；")
        for rawToken in scanner.split(separator: " ") {
            let token = rawToken.trimmingCharacters(in: punctuation)
            if token.hasSuffix("BB") || token.hasSuffix("bb") {
                if let value = Double(token.dropLast(2)) {
                    sizes.append(value)
                    if openSize == nil { openSize = value }
                }
            }
        }
        guard let open = openSize else { return sizes }

        for rawToken in scanner.split(separator: " ") {
            let token = rawToken.trimmingCharacters(in: punctuation)
            guard token.hasSuffix("x") else { continue }
            if let multiplier = Double(token.dropLast()) {
                sizes.append(open * multiplier)
                // A four-bet is a multiple of the three-bet, not of the open.
                if let threeBet = sizes.dropFirst().first {
                    sizes.append(threeBet * multiplier)
                }
            }
        }
        return sizes
    }

    private static func isPair(_ text: String) -> Bool {
        text.count == 2 && text.first == text.last
    }

    private static func parse(_ text: String) -> (Character, Character, String)? {
        guard text.count == 3,
              let suitedness = text.last.map(String.init),
              suitedness == "s" || suitedness == "o"
        else {
            return nil
        }
        let characters = Array(text)
        return (characters[0], characters[1], suitedness)
    }

    private static func between(_ high: Character, _ low: Character) -> [Character] {
        guard let start = ranks.firstIndex(of: high),
              let end = ranks.firstIndex(of: low)
        else {
            return []
        }
        return Array(ranks[min(start, end) ... max(start, end)])
    }
}
