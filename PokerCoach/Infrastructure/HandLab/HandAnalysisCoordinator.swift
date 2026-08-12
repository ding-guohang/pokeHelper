import HandHistory
import HandHistoryPersistence
import TrainingDomain

/// The app-layer owner of imported-hand analysis: it can see the personal
/// library, the installed content matcher and the training event store at once,
/// which no package can.
///
/// ## Why it holds the event store
///
/// Deliberately, and it never writes to it — the same reason `HandImportCoordinator`
/// holds one. Analyzing an imported hand produces a review, never a
/// `TrainingEvent`: nobody authored frequencies for a stranger's hand, and the
/// analysis asks for no confidence and grades nothing. That rule is only worth
/// asserting about a type that *could* break it. A coordinator built without the
/// store would make `HandAnalysisEventIsolationTests` a statement about
/// something with no access rather than about the path a real analysis takes.
///
/// `HandHistoryPersistence` cannot reach a `TrainingEvent` at all; this
/// coordinator can, and still does not.
@MainActor
struct HandAnalysisCoordinator {
    private let libraryStore: FileHandLibraryStore
    private let eventStore: any TrainingEventStore
    private let matcher: ImportedHandContentMatcher

    init(
        libraryStore: FileHandLibraryStore,
        eventStore: any TrainingEventStore,
        matcher: ImportedHandContentMatcher
    ) {
        self.libraryStore = libraryStore
        self.eventStore = eventStore
        self.matcher = matcher
    }

    /// The review-worthy decisions in the adopted hand with this identity, empty
    /// if the library has no such hand. Reads the library and installed content;
    /// the event store is never touched.
    func analyze(identity: String) async throws -> [KeyNode] {
        guard let hand = try await libraryStore.hand(identity: identity) else {
            return []
        }
        let classified = hand.heroDecisionSignatures().map { signature in
            (signature, matcher.classify(signature))
        }
        return selectKeyNodes(classified)
    }
}
