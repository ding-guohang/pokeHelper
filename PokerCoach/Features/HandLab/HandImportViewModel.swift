import Foundation
import HandHistory
import Observation
import PokerCore

/// Drives the hand-import surface: parse text, preview it, clear conflicts, then
/// adopt it.
///
/// ## It cannot write a training event
///
/// Adoption goes through `HandImportCoordinator`, which holds the event store
/// and never writes it — `HandImportEventIsolationTests` is the observed half of
/// that. This view model adds no other path to storage: it parses, maps to a
/// preview, and hands a resolved `ObservedHand` back to the coordinator.
///
/// ## The accept gate lives here
///
/// `canAccept` is false while any conflict is unresolved, and a conflict clears
/// only when the user supplies the value the parser refused to guess. A screen
/// that hard-coded it true would let an incomplete hand into the library; the
/// gate is the point of the preview.
@MainActor
@Observable
final class HandImportViewModel {
    private(set) var preview: HandImportPreview?
    private(set) var unresolvedConflicts: [HandImportConflict] = []
    private(set) var unsupportedMessage: String?
    private(set) var libraryHands: [HandImportPreview] = []
    private(set) var lastAcceptedIdentity: String?

    /// The parser's best-effort model for the current text, before resolutions.
    private var parsedHand: ObservedHand?
    /// User-supplied replacements for flagged fields, keyed by the conflict they
    /// resolve.
    private var resolutions: [HandImportConflict: ObservedAction] = [:]

    private let coordinator: HandImportCoordinator

    init(coordinator: HandImportCoordinator) {
        self.coordinator = coordinator
    }

    /// A hand can be adopted only when it parsed and no flagged field is still
    /// open.
    var canAccept: Bool {
        parsedHand != nil && unresolvedConflicts.isEmpty && unsupportedMessage == nil
    }

    /// Parses `text` and prepares the preview. Resolutions from a previous text
    /// are dropped; nothing is written.
    func load(text: String) {
        resolutions = [:]
        lastAcceptedIdentity = nil
        switch PokerStarsParser.parse(text) {
        case let .parsed(hand, conflicts):
            parsedHand = hand
            unresolvedConflicts = conflicts
            unsupportedMessage = nil
            preview = HandImportPreview(hand)
        case let .unsupported(reason, sourceLine):
            parsedHand = nil
            unresolvedConflicts = []
            preview = nil
            unsupportedMessage = "第 \(sourceLine) 行不受支持：\(reason)"
        }
    }

    /// Supplies the action the parser could not read, clearing that conflict.
    ///
    /// The action is inserted into the flagged street at the position its source
    /// line implies, so the adopted hand carries it in the order it happened
    /// rather than tacked onto the end.
    func resolve(
        _ conflict: HandImportConflict,
        seat: Int,
        kind: ActionKind,
        amountCentiBB: Int?
    ) {
        guard unresolvedConflicts.contains(conflict) else { return }
        resolutions[conflict] = ObservedAction(seat: seat, kind: kind, amountCentiBB: amountCentiBB)
        unresolvedConflicts.removeAll { $0 == conflict }
        if let resolved = resolvedHand() {
            preview = HandImportPreview(resolved)
        }
    }

    /// Writes the resolved hand to the library. A no-op unless `canAccept`.
    func accept() async throws {
        guard canAccept, let hand = resolvedHand() else { return }
        try await coordinator.accept(hand)
        lastAcceptedIdentity = hand.source.identity
        await refreshLibrary()
    }

    /// Reloads the library listing after an adoption.
    func refreshLibrary() async {
        let hands = (try? await coordinator.libraryHands()) ?? []
        libraryHands = hands.map(HandImportPreview.init)
    }

    // MARK: - Resolution

    /// The parsed hand with every resolution applied. Nil until something parses.
    private func resolvedHand() -> ObservedHand? {
        guard let hand = parsedHand else { return nil }
        guard !resolutions.isEmpty else { return hand }

        var streets = hand.streets
        for (conflict, action) in resolutions {
            guard
                let street = Self.street(forField: conflict.field),
                let index = streets.firstIndex(where: { $0.street == street })
            else {
                continue
            }
            var actions = streets[index].actions
            let insertAt = Self.insertionIndex(
                rawText: hand.source.rawText,
                street: street,
                conflictLine: conflict.sourceLine
            )
            actions.insert(action, at: min(insertAt, actions.count))
            streets[index] = ObservedStreet(
                street: streets[index].street,
                board: streets[index].board,
                actions: actions
            )
        }

        return ObservedHand(
            source: hand.source,
            site: hand.site,
            tableSize: hand.tableSize,
            buttonSeat: hand.buttonSeat,
            bigBlindCentiBB: hand.bigBlindCentiBB,
            seats: hand.seats,
            forcedPosts: hand.forcedPosts,
            streets: streets,
            result: hand.result
        )
    }

    /// The street a field like "action.preflop" or "amount.flop" names.
    private static func street(forField field: String) -> Street? {
        for street in Street.allCases where field.hasSuffix(street.rawValue) {
            return street
        }
        return nil
    }

    /// How many recognized player-action lines of `street` appear before
    /// `conflictLine`, which is where the resolved action belongs in that
    /// street's action list.
    private static func insertionIndex(
        rawText: String,
        street: Street,
        conflictLine: Int
    ) -> Int {
        var current: Street?
        var count = 0
        let rawLines = rawText.components(separatedBy: "\n")
        for (offset, raw) in rawLines.enumerated() {
            let lineNumber = offset + 1
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw

            if line.hasPrefix("*** HOLE CARDS ***") { current = .preflop; continue }
            if line.hasPrefix("*** FLOP ***") { current = .flop; continue }
            if line.hasPrefix("*** TURN ***") { current = .turn; continue }
            if line.hasPrefix("*** RIVER ***") { current = .river; continue }
            if line.hasPrefix("*** ") { current = nil; continue }

            guard current == street else { continue }
            if lineNumber >= conflictLine { break }
            if line.hasPrefix("Dealt to ") { continue }
            // "Name: action" — a player line. The flagged line itself is before
            // conflictLine only for earlier conflicts, which this offset accounts
            // for by counting recognized lines only up to the boundary.
            if line.contains(":") { count += 1 }
        }
        return count
    }
}
