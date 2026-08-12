import Foundation
import Observation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain

/// Where a session screen is.
enum SessionRunState: Equatable {
    case setup
    case playing
    case finished
    case failed(message: String)
}

/// One of the four disclosed opponent profiles, as the setup screen states it.
///
/// Every number here is copied straight off `OpponentProfile`. Nothing is
/// measured from play and nothing is recomputed: the profile the user is told
/// about has to be the profile the engine is running, and the only way to
/// guarantee that is for the screen to have no arithmetic of its own.
struct OpponentProfileRow: Identifiable, Equatable {
    let id: String
    let name: String
    let entryRateText: String
    let aggressionText: String
    let callingTendencyText: String
    let summary: String

    init(_ profile: OpponentProfile) {
        id = profile.id.rawValue
        name = profile.name
        entryRateText = StrategyNumberText.frequency(basisPoints: profile.entryRateBasisPoints)
        aggressionText = StrategyNumberText.frequency(basisPoints: profile.aggressionBasisPoints)
        callingTendencyText = StrategyNumberText.frequency(
            basisPoints: profile.callingTendencyBasisPoints
        )
        summary = profile.tendencySummary
    }
}

/// Drives a cash session and the review that follows it.
///
/// ## It cannot write a training event
///
/// It plays through `SessionRunCoordinator`, which holds the event store and
/// never writes to it while hands are dealt — that is the milestone's
/// load-bearing rule and `SessionEventIsolationTests` is the observed half of
/// it. This view model adds nothing to that path. The one route from here to an
/// event is `KeyHandReview.replayScenarioID`, which the view turns into an
/// ordinary `DecisionSessionViewModel`: action and confidence submitted
/// together, event stored before feedback appears, same pipeline as Today.
@MainActor
@Observable
final class SessionViewModel {
    /// The lengths the spec offers.
    static let handCountChoices = [15, 30, 60]

    private(set) var state: SessionRunState = .setup
    private(set) var reviews: [KeyHandReview] = []
    private(set) var handsPlayed = 0
    var selectedHandCount = 30

    /// The four profiles and where their behaviour comes from. Constants, so
    /// they are readable before a session starts and unchanged after one ends.
    let profileRows = OpponentProfileTable.profiles.map(OpponentProfileRow.init)
    let opponentDisclosure = OpponentProfileTable.disclosure
    let opponentTableVersion = OpponentProfileTable.version

    private let sessionStore: FileSessionRecordStore
    private let eventStore: any TrainingEventStore
    private let strategyProvider: any StrategyPackProviding
    private let makeSeed: @MainActor () -> UInt64
    private let makeSessionID: @MainActor () -> UUID

    init(
        sessionStore: FileSessionRecordStore,
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        makeSeed: @escaping @MainActor () -> UInt64 = { UInt64.random(in: 0 ..< UInt64.max) },
        makeSessionID: @escaping @MainActor () -> UUID = UUID.init
    ) {
        self.sessionStore = sessionStore
        self.eventStore = eventStore
        self.strategyProvider = strategyProvider
        self.makeSeed = makeSeed
        self.makeSessionID = makeSessionID
    }

    func select(handCount: Int) {
        guard state != .playing, Self.handCountChoices.contains(handCount) else {
            return
        }
        selectedHandCount = handCount
    }

    /// Plays a whole session and prepares its review.
    func start() async {
        guard state != .playing else {
            return
        }
        state = .playing
        reviews = []
        handsPlayed = 0

        do {
            // No installed content is a state a session runs in: the hands are
            // dealt the same either way and the review simply has nothing to
            // compare them against. Failing here would make the whole feature
            // depend on a strategy pack it does not use to deal a single card.
            let scenarios = (try? await strategyProvider.pack())?.scenarios ?? []

            let record = SessionRecord(
                id: makeSessionID(),
                seed: makeSeed(),
                handCount: selectedHandCount
            )
            try await sessionStore.create(record)
            let summary = try await SessionRunCoordinator(
                sessionStore: sessionStore,
                eventStore: eventStore,
                scenarios: scenarios
            ).playToCompletion(sessionID: record.id)

            handsPlayed = summary.hands.count
            reviews = KeyHandReviewBuilder(scenarios: scenarios)
                .reviews(from: summary, seating: record.seating)
            state = .finished
        } catch {
            state = .failed(message: "对局无法完成，请重试")
        }
    }
}
