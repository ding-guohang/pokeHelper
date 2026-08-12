import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain

/// What a finished session run leaves behind.
struct SessionRunSummary: Equatable {
    let hands: [SessionHandRecord]

    /// Hero spots this session played that installed content covers. Used by
    /// review to show the content's frequencies beside what the user did — a
    /// comparison, not a grade.
    let contentMatches: [SessionContentMatch]

    /// The three to five hands review opens with.
    ///
    /// Selected by the engine, which cannot see content; the one input that
    /// needs content — how much weight the installed range gives what the hero
    /// did — is computed here and handed in.
    let keyHands: [KeyHand]

    var comparableHandIndices: Set<Int> {
        Set(contentMatches.map(\.handIndex))
    }
}

/// Runs a session and files what happened.
///
/// The app-layer owner of a session: it can see the engine, the session store,
/// installed content and the training event store all at once, which no package
/// can.
///
/// ## Why it holds the event store
///
/// Deliberately, and it never writes to it while hands are played. The rule
/// this milestone rests on — a session hand never becomes a `TrainingEvent` —
/// is only worth asserting about a type that *could* break it. A coordinator
/// built without the store would make `SessionEventIsolationTests` a statement
/// about something with no access rather than about the path a real session
/// takes; the assertion would hold for the same reason a locked door in a wall
/// with no room behind it holds.
///
/// The store is here because this is also the type a review screen asks to
/// replay a spot in training mode, and *that* path does write an event — with
/// an action and a confidence submitted together, through the ordinary
/// pipeline. Playing hands is not that path.
@MainActor
struct SessionRunCoordinator {
    private let sessionStore: FileSessionRecordStore
    private let eventStore: any TrainingEventStore
    private let matcher: SessionContentMatcher

    init(
        sessionStore: FileSessionRecordStore,
        eventStore: any TrainingEventStore,
        scenarios: [DecisionScenario]
    ) {
        self.sessionStore = sessionStore
        self.eventStore = eventStore
        matcher = SessionContentMatcher(scenarios: scenarios)
    }

    /// Plays the session to its recorded hand count, resuming if some of it has
    /// already been played.
    func playToCompletion(
        sessionID: UUID,
        heroPolicy: any SessionActionPolicy = BaselineActionPolicy()
    ) async throws -> SessionRunSummary {
        try await SessionPlaythrough.play(
            sessionID: sessionID,
            store: sessionStore,
            heroPolicy: heroPolicy
        )

        // Read back rather than use what `play` returned: after a resume the
        // return value is the hands played just now, and a summary of a session
        // is a summary of all of it.
        let hands = try await sessionStore.hands(for: sessionID)
        return SessionRunSummary(
            hands: hands,
            contentMatches: hands.flatMap { matcher.matches(in: $0) },
            keyHands: KeyHandSelection.select(
                from: hands,
                heroActionWeightsBasisPoints: matcher.heroActionWeightsBasisPoints(in: hands)
            )
        )
    }
}
