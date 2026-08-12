import Foundation
import PokerCore

/// Turns a supported PokerStars No-Limit Hold'em cash hand-history text into an
/// `ObservedHand`, deterministically. Text outside the supported class is
/// rejected with the line that triggered the decision; a field that cannot be
/// read unambiguously is registered as a conflict rather than guessed.
///
/// Amounts are converted to centi-big-blinds as `cents * 100 / bigBlindCents`,
/// which must divide exactly — no rounding. A dollar figure that does not divide
/// (a rake that is a fraction of the blind at these stakes) becomes a conflict
/// on its line, and no rounded value reaches the model.
public enum PokerStarsParser {
    public static func parse(_ text: String) -> HandImportResult {
        // Line numbers are 1-based and refer to the raw text; a trailing "\r"
        // (a Windows export) is stripped for matching but does not shift lines.
        let lines = text.components(separatedBy: "\n").map { line -> String in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }

        guard let headerIndex = lines.firstIndex(where: { $0.contains("PokerStars Hand") }) else {
            return .unsupported(reason: "not a PokerStars hand history", sourceLine: 1)
        }
        let header = lines[headerIndex]

        // Tournaments change stack semantics (chips, not money), position count
        // and antes; out of scope for this slice.
        if header.contains("Tournament") {
            return .unsupported(
                reason: "PokerStars tournament hands are not supported",
                sourceLine: headerIndex + 1
            )
        }
        guard header.contains("Hold'em No Limit") else {
            return .unsupported(
                reason: "only No-Limit Hold'em is supported",
                sourceLine: headerIndex + 1
            )
        }

        // Stakes: "($0.50/$1.00 USD)". The big blind is the conversion base.
        guard
            let stakes = firstMatch(#"\(\$([0-9]+(?:\.[0-9]+)?)/\$([0-9]+(?:\.[0-9]+)?)"#, in: header),
            let bigBlindCents = dollarsToCents(stakes[2])
        else {
            return .unsupported(reason: "could not read the blinds", sourceLine: headerIndex + 1)
        }
        guard bigBlindCents > 0 else {
            return .unsupported(reason: "big blind is zero", sourceLine: headerIndex + 1)
        }

        // Table: "Table 'Andromeda' 6-max Seat #1 is the button".
        guard
            let tableIndex = lines.firstIndex(where: { $0.hasPrefix("Table ") }),
            let sizeMatch = firstMatch(#"([0-9]+)-max"#, in: lines[tableIndex]),
            let tableSize = Int(sizeMatch[1]),
            let buttonMatch = firstMatch(#"Seat #([0-9]+) is the button"#, in: lines[tableIndex]),
            let buttonSeatNumber = Int(buttonMatch[1])
        else {
            return .unsupported(
                reason: "could not read the table size or button",
                sourceLine: (lines.firstIndex(where: { $0.hasPrefix("Table ") }) ?? headerIndex) + 1
            )
        }
        guard (2...9).contains(tableSize) else {
            return .unsupported(
                reason: "table size \(tableSize) is outside 2...9",
                sourceLine: tableIndex + 1
            )
        }

        var conflicts: [HandImportConflict] = []

        // Converts a dollar figure to centi-BB, or records a conflict and
        // returns nil if it does not divide exactly. Never rounds.
        func convert(_ dollars: String, field: String, line: Int) -> Int? {
            guard let cents = dollarsToCents(dollars) else {
                conflicts.append(HandImportConflict(field: field, sourceLine: line))
                return nil
            }
            let numerator = cents * 100
            guard numerator % bigBlindCents == 0 else {
                conflicts.append(HandImportConflict(field: field, sourceLine: line))
                return nil
            }
            return numerator / bigBlindCents
        }

        // MARK: - Accumulators

        struct RawSeat {
            let seat: Int
            let name: String
            let startingStackCentiBB: Int
        }
        var rawSeats: [RawSeat] = []
        var nameToSeat: [String: Int] = [:]
        var forcedPosts: [ForcedPost] = []
        var heroName: String?
        var heroCards: (Card, Card)?
        var rakeCentiBB = 0

        struct StreetBuilder {
            let street: Street
            var board: [Card]
            var actions: [ObservedAction]
        }
        var streets: [StreetBuilder] = []
        // Money each seat has put in on the current street, so a call records the
        // total "to" amount rather than only the increment it added.
        var streetInvestment: [Int: Int] = [:]

        var sawHoleCards = false
        var inShowdownOrSummary = false

        // MARK: - Post and action handling (declared before the pass that calls them)

        func handlePost(_ post: (name: String, rest: String), lineNumber: Int) {
            guard let seat = nameToSeat[post.name] else { return }
            if post.rest.hasPrefix("small blind"), let amt = amount(in: post.rest) {
                if let value = convert(amt, field: "forcedPost.smallBlind", line: lineNumber) {
                    forcedPosts.append(ForcedPost(seat: seat, kind: .smallBlind, amountCentiBB: value))
                }
            } else if post.rest.hasPrefix("big blind"), let amt = amount(in: post.rest) {
                if let value = convert(amt, field: "forcedPost.bigBlind", line: lineNumber) {
                    forcedPosts.append(ForcedPost(seat: seat, kind: .bigBlind, amountCentiBB: value))
                }
            } else if post.rest.hasPrefix("ante"), let amt = amount(in: post.rest) {
                if let value = convert(amt, field: "forcedPost.ante", line: lineNumber) {
                    forcedPosts.append(ForcedPost(seat: seat, kind: .ante, amountCentiBB: value))
                }
            } else if post.rest.hasPrefix("straddle") {
                // A straddle changes the action order and the first seat to act;
                // modeling it correctly is out of scope, so it is flagged, not guessed.
                conflicts.append(HandImportConflict(field: "straddle", sourceLine: lineNumber))
            } else {
                conflicts.append(HandImportConflict(field: "post", sourceLine: lineNumber))
            }
        }

        func handleAction(_ line: String, lineNumber: Int) {
            guard let colon = line.firstIndex(of: ":") else { return }
            let name = String(line[line.startIndex..<colon])
            guard let seat = nameToSeat[name] else { return }
            guard !streets.isEmpty else { return }
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let streetName = streets[streets.count - 1].street.rawValue

            func appendAction(_ kind: ActionKind, _ amountCentiBB: Int?) {
                streets[streets.count - 1].actions.append(
                    ObservedAction(seat: seat, kind: kind, amountCentiBB: amountCentiBB)
                )
            }

            if rest == "folds" {
                appendAction(.fold, nil)
            } else if rest == "checks" {
                appendAction(.check, nil)
            } else if rest.hasPrefix("calls "), let amt = amount(in: rest) {
                let delta = convert(amt, field: "amount.\(streetName)", line: lineNumber)
                let toAmount = delta.map { (streetInvestment[seat] ?? 0) + $0 }
                if let toAmount { streetInvestment[seat] = toAmount }
                appendAction(.call, toAmount)
            } else if rest.hasPrefix("bets "), let amt = amount(in: rest) {
                let delta = convert(amt, field: "amount.\(streetName)", line: lineNumber)
                let toAmount = delta.map { (streetInvestment[seat] ?? 0) + $0 }
                if let toAmount { streetInvestment[seat] = toAmount }
                appendAction(.bet, toAmount)
            } else if rest.hasPrefix("raises "),
                      let raise = firstMatch(#"raises \$?[0-9.]+ to \$([0-9]+(?:\.[0-9]+)?)"#, in: rest) {
                let toAmount = convert(raise[1], field: "amount.\(streetName)", line: lineNumber)
                if let toAmount { streetInvestment[seat] = toAmount }
                appendAction(.raiseTo, toAmount)
            } else if rest.hasPrefix("shows") || rest.hasPrefix("mucks") || rest.hasPrefix("doesn't show") {
                // Showdown reveal, not a betting decision.
            } else {
                // An action verb the supported grammar does not define; do not
                // invent a value for it.
                conflicts.append(HandImportConflict(field: "action.\(streetName)", sourceLine: lineNumber))
            }
        }

        // MARK: - Line pass

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1

            if line.hasPrefix("*** ") {
                if line.hasPrefix("*** HOLE CARDS ***") {
                    sawHoleCards = true
                    streets.append(StreetBuilder(street: .preflop, board: [], actions: []))
                    streetInvestment.removeAll()
                    for post in forcedPosts {
                        // Antes are dead money and do not count toward the amount
                        // owed on the street.
                        if post.kind != .ante {
                            streetInvestment[post.seat] = post.amountCentiBB
                        }
                    }
                } else if let street = streetMarker(line) {
                    let board = boardCards(in: line)
                    streets.append(StreetBuilder(street: street, board: board, actions: []))
                    streetInvestment.removeAll()
                } else if line.hasPrefix("*** SHOW DOWN ***") || line.hasPrefix("*** SUMMARY ***") {
                    inShowdownOrSummary = true
                }
                continue
            }

            if !sawHoleCards {
                if let seat = seatLine(line) {
                    let stack = convert(seat.stack, field: "seat.\(seat.number).stack", line: lineNumber)
                    rawSeats.append(
                        RawSeat(seat: seat.number, name: seat.name, startingStackCentiBB: stack ?? 0)
                    )
                    nameToSeat[seat.name] = seat.number
                } else if let post = postLine(line) {
                    handlePost(post, lineNumber: lineNumber)
                }
                continue
            }

            if inShowdownOrSummary {
                if line.contains("Rake"), let match = firstMatch(#"Rake \$([0-9]+(?:\.[0-9]+)?)"#, in: line) {
                    rakeCentiBB = convert(match[1], field: "amount.rake", line: lineNumber) ?? 0
                }
                continue
            }

            // Action region.
            if line.hasPrefix("Dealt to ") {
                if let dealt = dealtLine(line) {
                    heroName = dealt.name
                    heroCards = dealt.cards
                }
                continue
            }
            handleAction(line, lineNumber: lineNumber)
        }

        guard !rawSeats.isEmpty else {
            return .unsupported(reason: "no seats found", sourceLine: tableIndex + 1)
        }

        let sortedSeats = rawSeats.sorted { $0.seat < $1.seat }
        guard let buttonIndex = sortedSeats.firstIndex(where: { $0.seat == buttonSeatNumber }) else {
            return .unsupported(reason: "button seat not among seated players", sourceLine: tableIndex + 1)
        }

        let observedSeats: [ObservedSeat] = sortedSeats.map { raw in
            let offset = ((raw.seat - buttonSeatNumber) % tableSize + tableSize) % tableSize
            let holeCards: HoleCards
            if raw.name == heroName, let cards = heroCards {
                holeCards = .known(cards.0, cards.1)
            } else {
                holeCards = .unknown
            }
            return ObservedSeat(
                seat: raw.seat,
                seatOffsetFromButton: offset,
                startingStackCentiBB: raw.startingStackCentiBB,
                holeCards: holeCards
            )
        }

        let hand = ObservedHand(
            source: HandSource(rawText: text),
            site: .pokerStars,
            tableSize: tableSize,
            buttonSeat: buttonIndex,
            bigBlindCentiBB: convertBigBlind(bigBlindCents),
            seats: observedSeats,
            forcedPosts: forcedPosts,
            streets: streets.map { ObservedStreet(street: $0.street, board: $0.board, actions: $0.actions) },
            result: ObservedResult(rakeCentiBB: rakeCentiBB)
        )
        return .parsed(hand, conflicts: conflicts)
    }

    // The big blind is 1 BB by definition, so it converts to 100 centi-BB. This
    // is a plain identity (bigBlindCents * 100 / bigBlindCents), kept explicit so
    // the model records 100 rather than re-deriving it.
    private static func convertBigBlind(_ bigBlindCents: Int) -> Int {
        bigBlindCents == 0 ? 0 : (bigBlindCents * 100) / bigBlindCents
    }

    // MARK: - Line helpers

    private static func streetMarker(_ line: String) -> Street? {
        if line.hasPrefix("*** FLOP ***") { return .flop }
        if line.hasPrefix("*** TURN ***") { return .turn }
        if line.hasPrefix("*** RIVER ***") { return .river }
        return nil
    }

    private static func boardCards(in line: String) -> [Card] {
        // Collect every card inside every [ ... ] group, in order.
        var cards: [Card] = []
        var scanning = false
        var token = ""
        func flush() {
            if let card = Card(code: token) { cards.append(card) }
            token = ""
        }
        for character in line {
            switch character {
            case "[": scanning = true; token = ""
            case "]": if scanning { flush() }; scanning = false
            case " ": if scanning { flush() }
            default: if scanning { token.append(character) }
            }
        }
        return cards
    }

    private static func seatLine(_ line: String) -> (number: Int, name: String, stack: String)? {
        guard
            let match = firstMatch(#"^Seat ([0-9]+): (.+) \(\$([0-9]+(?:\.[0-9]+)?) in chips\)"#, in: line),
            let number = Int(match[1])
        else {
            return nil
        }
        return (number, match[2], match[3])
    }

    private static func postLine(_ line: String) -> (name: String, rest: String)? {
        guard let range = line.range(of: ": posts ") else { return nil }
        let name = String(line[line.startIndex..<range.lowerBound])
        let rest = String(line[range.upperBound...])
        return (name, rest)
    }

    private static func dealtLine(_ line: String) -> (name: String, cards: (Card, Card))? {
        guard let match = firstMatch(#"^Dealt to (.+) \[([2-9TJQKA][cdhs]) ([2-9TJQKA][cdhs])\]"#, in: line),
              let first = Card(code: match[2]),
              let second = Card(code: match[3])
        else {
            return nil
        }
        return (match[1], (first, second))
    }

    private static func amount(in text: String) -> String? {
        firstMatch(#"\$([0-9]+(?:\.[0-9]+)?)"#, in: text).map { $0[1] }
    }

    /// Parses "$0.50" / "0.50" / "1" / "100" to integer cents.
    private static func dollarsToCents(_ raw: String) -> Int? {
        var text = raw
        if text.hasPrefix("$") { text.removeFirst() }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let dollars = Int(parts[0]) else { return nil }
        if parts.count == 1 {
            return dollars * 100
        }
        let fractionRaw = String(parts[1])
        guard fractionRaw.allSatisfy(\.isNumber) else { return nil }
        let padded = fractionRaw.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let fraction = Int(padded) else { return nil }
        return dollars * 100 + fraction
    }

    /// Returns capture groups (index 0 is the whole match) of the first match,
    /// or nil.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: text) else {
                groups.append("")
                continue
            }
            groups.append(String(text[r]))
        }
        return groups
    }
}
