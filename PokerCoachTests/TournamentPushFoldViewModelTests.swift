import XCTest
import PokerCore
import TrainingDomain
@testable import PokerCoach

@MainActor
final class TournamentPushFoldViewModelTests: XCTestCase {
    private let localUserID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let deviceID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let eventID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!

    private func makeViewModel(store: RecordingEventStore, loader: TournamentPushFoldLoader) -> TournamentPushFoldViewModel {
        TournamentPushFoldViewModel(
            loader: loader,
            eventStore: store,
            localUserID: localUserID,
            deviceID: deviceID,
            makeEventID: { self.eventID },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    private let aa = [Card(rank: .ace, suit: .spades), Card(rank: .ace, suit: .hearts)]

    func testJammingAAAt10BBScoresPerfect() async throws {
        let store = RecordingEventStore()
        let vm = makeViewModel(store: store, loader: .init(bundle: .main))
        vm.present(depth: 10, position: .openJam, heroCards: aa)
        XCTAssertEqual(vm.state, .answering)
        XCTAssertEqual(vm.handClass, "AA")

        // The aggressive candidate is the all-in (jam).
        let jam = try XCTUnwrap(vm.candidateActions.first { if case .allIn = $0 { return true }; return false })
        vm.select(action: jam)
        vm.setConfidence(.verySure)
        await vm.submit()

        XCTAssertEqual(vm.state, .feedback)
        XCTAssertEqual(vm.grade?.score, 100)
        XCTAssertEqual(vm.grade?.evLoss.milliBB, 0)
        XCTAssertEqual(store.appended.count, 1)
        XCTAssertTrue(store.appended[0].scenarioID.hasSuffix("10bb-open-jam"))
        XCTAssertEqual(store.appended[0].abilityDimension, "tournament-push-fold")
    }

    func testFoldingAAAt10BBIsABlunder() async throws {
        let store = RecordingEventStore()
        let vm = makeViewModel(store: store, loader: .init(bundle: .main))
        vm.present(depth: 10, position: .openJam, heroCards: aa)
        vm.select(action: .fold)
        vm.setConfidence(.unsure)
        await vm.submit()

        // AA raise EV +2978, fold EV -500 milliBB -> EV loss 3478, score 0, blunder.
        XCTAssertEqual(vm.grade?.evLoss.milliBB, 3478)
        XCTAssertEqual(vm.grade?.score, 0)
        XCTAssertEqual(vm.grade?.quality, .blunder)
    }

    func testEmptyBundleMakesTrainerUnavailable() {
        let store = RecordingEventStore()
        let loader = TournamentPushFoldLoader(resource: { _ in nil })  // no packs bundled at all
        let vm = makeViewModel(store: store, loader: loader)
        XCTAssertTrue(vm.availableDepths.isEmpty)
        var rng = SystemRandomNumberGenerator()
        vm.startRandomHand(using: &rng)
        XCTAssertEqual(vm.state, .unavailable)
    }

    func testHandClassMapping() {
        XCTAssertEqual(TournamentPushFoldViewModel.handClass(for: [
            Card(rank: .ace, suit: .spades), Card(rank: .king, suit: .spades)]), "AKs")
        XCTAssertEqual(TournamentPushFoldViewModel.handClass(for: [
            Card(rank: .king, suit: .hearts), Card(rank: .ace, suit: .spades)]), "AKo")
        XCTAssertEqual(TournamentPushFoldViewModel.handClass(for: [
            Card(rank: .seven, suit: .clubs), Card(rank: .seven, suit: .diamonds)]), "77")
    }
}

private final class RecordingEventStore: TrainingEventStore, @unchecked Sendable {
    private(set) var appended: [TrainingEvent] = []
    func append(_ event: TrainingEvent) async throws { appended.append(event) }
    func allEvents() async throws -> [TrainingEvent] { appended }
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent] { appended }
}
