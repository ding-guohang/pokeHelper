import Foundation
import HandHistory
import HandHistoryPersistence
import TrainingDomain

/// The outcome of asking the coordinator to import and, when possible, adopt a
/// text hand.
enum HandImportOutcome: Equatable {
    /// Parsed cleanly and written to the library.
    case accepted(ObservedHand)
    /// Parsed well enough to preview, but not adopted: its conflicts must clear
    /// first. The preview hand is the parser's best effort, missing the fields
    /// the conflicts point at.
    case needsResolution(preview: ObservedHand, conflicts: [HandImportConflict])
    /// Text outside the supported class, rejected with the line that decided it.
    case unsupported(reason: String, sourceLine: Int)
}

/// The app-layer owner of a hand import: it can see the parser, the personal
/// library and the training event store at once, which no package can.
///
/// ## Why it holds the event store
///
/// Deliberately, and it never writes to it. The rule this milestone rests on —
/// importing and adopting a hand never becomes a `TrainingEvent` — is only worth
/// asserting about a type that *could* break it. A coordinator built without the
/// store would make `HandImportEventIsolationTests` a statement about something
/// with no access rather than about the path a real import takes; the assertion
/// would hold for the same reason a locked door in a wall with no room behind it
/// holds.
///
/// The store is here because an imported hand and a graded training answer are
/// both things the app files, and the one type that files hands is the natural
/// place to prove it does not file the other. `HandHistoryPersistence` cannot
/// reach a `TrainingEvent` at all; this coordinator can, and still does not.
@MainActor
struct HandImportCoordinator {
    private let libraryStore: FileHandLibraryStore
    private let eventStore: any TrainingEventStore

    init(libraryStore: FileHandLibraryStore, eventStore: any TrainingEventStore) {
        self.libraryStore = libraryStore
        self.eventStore = eventStore
    }

    /// Parses `text` and, if it is a clean supported hand, writes it to the
    /// library. A hand with conflicts is returned for review and not written; the
    /// event store is never touched on any branch.
    func importAndAccept(text: String) async throws -> HandImportOutcome {
        switch PokerStarsParser.parse(text) {
        case let .parsed(hand, conflicts):
            guard conflicts.isEmpty else {
                return .needsResolution(preview: hand, conflicts: conflicts)
            }
            try await libraryStore.accept(hand)
            return .accepted(hand)
        case let .unsupported(reason, sourceLine):
            return .unsupported(reason: reason, sourceLine: sourceLine)
        }
    }

    /// Writes an already-resolved hand to the library. The path a preview screen
    /// takes once its conflicts have cleared; like `importAndAccept`, it does not
    /// write the event store.
    func accept(_ hand: ObservedHand) async throws {
        try await libraryStore.accept(hand)
    }

    /// The library's current hands, latest version of each, for a listing.
    func libraryHands() async throws -> [ObservedHand] {
        try await libraryStore.hands()
    }
}
