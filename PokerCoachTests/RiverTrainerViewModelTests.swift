import XCTest
import PokerCore
import StrategyContent
import TrainingDomain
@testable import PokerCoach

private final class RiverRecordingEventStore: TrainingEventStore, @unchecked Sendable {
    private(set) var appended: [TrainingEvent] = []
    func append(_ event: TrainingEvent) async throws { appended.append(event) }
    func allEvents() async throws -> [TrainingEvent] { appended }
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent] { appended }
}

@MainActor
final class RiverTrainerViewModelTests: XCTestCase {
    private let localUserID = UUID(uuidString: "10000000-0000-0000-0000-0000000000A1")!
    private let deviceID = UUID(uuidString: "20000000-0000-0000-0000-0000000000A1")!
    private let eventID = UUID(uuidString: "30000000-0000-0000-0000-0000000000A1")!

    private func makeViewModel(store: RiverRecordingEventStore, loader: RiverTrainerLoader) -> RiverTrainerViewModel {
        RiverTrainerViewModel(
            loader: loader,
            eventStore: store,
            localUserID: localUserID,
            deviceID: deviceID,
            makeEventID: { self.eventID },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    /// Loads the first bundled board + its first combo so the test does not
    /// depend on specific solved numbers, only on the pipeline being wired.
    private func firstBoardAndCombo() throws -> (String, String, DecisionScenario) {
        let loader = RiverTrainerLoader(bundle: .main)
        let boardID = try XCTUnwrap(loader.availableBoards().first, "no bundled river packs")
        let pack = try XCTUnwrap(try loader.loadPack(boardID: boardID))
        let scenario = try XCTUnwrap(pack.scenarios.first)
        let combo = try XCTUnwrap(scenario.rangeCells.first?.handClass)
        return (boardID, combo, scenario)
    }

    func testPresentDealsReviewedRiverSpotWithNoDisclosure() throws {
        let (boardID, combo, scenario) = try firstBoardAndCombo()
        let vm = makeViewModel(store: RiverRecordingEventStore(), loader: .init(bundle: .main))
        vm.present(boardID: boardID, heroCombo: combo)

        XCTAssertEqual(vm.state, .answering)
        XCTAssertEqual(vm.board.count, 5)
        XCTAssertEqual(vm.board, scenario.board)
        XCTAssertEqual(vm.heroCards, RiverTrainerViewModel.cards(from: combo))
        XCTAssertTrue(vm.candidateActions.contains(.check))
        // reviewed + solver content shows no unverified disclosure.
        XCTAssertNil(vm.disclosure)
    }

    func testSubmitScoresAndRecordsEvent() async throws {
        let (boardID, combo, scenario) = try firstBoardAndCombo()
        let store = RiverRecordingEventStore()
        let vm = makeViewModel(store: store, loader: .init(bundle: .main))
        vm.present(boardID: boardID, heroCombo: combo)

        let action = try XCTUnwrap(vm.candidateActions.first)
        vm.select(action: action)
        vm.setConfidence(.unsure)
        await vm.submit()

        XCTAssertEqual(vm.state, .feedback)
        XCTAssertNotNil(vm.grade)
        XCTAssertEqual(store.appended.count, 1)
        XCTAssertEqual(store.appended[0].scenarioID, scenario.id)
        XCTAssertEqual(store.appended[0].abilityDimension, "river-decision")
    }

    func testEmptyBundleMakesTrainerUnavailable() {
        let loader = RiverTrainerLoader(index: { [] }, resource: { _ in nil })
        let vm = makeViewModel(store: RiverRecordingEventStore(), loader: loader)
        XCTAssertTrue(vm.availableBoards.isEmpty)
        var rng = SystemRandomNumberGenerator()
        vm.startRandomHand(using: &rng)
        XCTAssertEqual(vm.state, .unavailable)
    }

    func testComboParsingHandlesSuitsExactly() {
        let cards = try? XCTUnwrap(RiverTrainerViewModel.cards(from: "6d6c"))
        XCTAssertEqual(cards, [Card(rank: .six, suit: .diamonds), Card(rank: .six, suit: .clubs)])
        XCTAssertNil(RiverTrainerViewModel.cards(from: "6d6"))
        XCTAssertNil(RiverTrainerViewModel.cards(from: "XX6c"))
    }
}
