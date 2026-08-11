import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import TrainingDomain
import XCTest
@testable import PokerCoach

/// The view model that runs a session and hands its key hands to the screen.
///
/// It is a new holder of the training event store, which is the reason the
/// third test here exists: `SessionEventIsolationTests` pins the rule for
/// `SessionRunCoordinator`, and a type that wraps the coordinator is a new
/// chance to break it.
final class SessionViewModelTests: XCTestCase {
    @MainActor
    func testOnlyTheThreeOfferedLengthsCanBeChosen() async throws {
        let viewModel = try await makeViewModel()

        XCTAssertEqual(SessionViewModel.handCountChoices, [15, 30, 60])
        for choice in SessionViewModel.handCountChoices {
            viewModel.select(handCount: choice)
            XCTAssertEqual(viewModel.selectedHandCount, choice)
        }

        viewModel.select(handCount: 30)
        for rejected in [0, 1, 14, 45, 61, 1_000] {
            viewModel.select(handCount: rejected)
            XCTAssertEqual(
                viewModel.selectedHandCount,
                30,
                "\(rejected) 手被接受了"
            )
        }
    }

    @MainActor
    func testPlayingASessionRecordsEveryHandAndOpensOnItsKeyHands() async throws {
        let store = try FileSessionRecordStore(
            directory: SessionReviewFixture.temporaryDirectory()
        )
        let viewModel = try await makeViewModel(sessionStore: store)

        viewModel.select(handCount: 15)
        await viewModel.start()

        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertEqual(viewModel.handsPlayed, 15)
        XCTAssertGreaterThanOrEqual(viewModel.reviews.count, 3)
        XCTAssertLessThanOrEqual(viewModel.reviews.count, 5)
        XCTAssertEqual(
            Set(viewModel.reviews.map(\.handIndex)).count,
            viewModel.reviews.count,
            "同一手被列了两次"
        )
        for review in viewModel.reviews {
            XCTAssertFalse(review.streets.isEmpty)
            XCTAssertLessThan(review.handIndex, 15)
        }

        // The hands are on disk, all fifteen, not just the ones review shows.
        let sessionIDs = try await store.sessionIDs()
        let sessionID = try XCTUnwrap(sessionIDs.first)
        let stored = try await store.hands(for: sessionID)
        XCTAssertEqual(stored.count, 15)
    }

    /// Playing through this view model writes no training event, matched or
    /// not. The store it is handed fails the test if anything reaches it.
    @MainActor
    func testPlayingASessionThroughTheViewModelWritesNoTrainingEvent() async throws {
        let pack = try SessionReviewFixture.corePack()
        let viewModel = try await makeViewModel(pack: pack)

        viewModel.select(handCount: 30)
        await viewModel.start()

        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertTrue(
            viewModel.reviews.contains { $0.comparison != nil },
            "这一局没有一手命中内容，断言没有覆盖「命中也不产生事件」"
        )
    }

    /// The disclosure and the four profiles are the ones the engine defines,
    /// carried through unchanged.
    @MainActor
    func testTheOpponentRowsRestateTheDefinedProfiles() async throws {
        let viewModel = try await makeViewModel()

        XCTAssertEqual(viewModel.opponentDisclosure, OpponentProfileTable.disclosure)
        XCTAssertEqual(viewModel.opponentTableVersion, OpponentProfileTable.version)
        XCTAssertEqual(viewModel.profileRows.count, 4)
        XCTAssertEqual(
            viewModel.profileRows.map(\.name),
            OpponentProfileTable.profiles.map(\.name)
        )
        XCTAssertEqual(
            viewModel.profileRows.map(\.entryRateText),
            OpponentProfileTable.profiles.map {
                StrategyNumberText.frequency(basisPoints: $0.entryRateBasisPoints)
            }
        )
        // Four distinct triples, so a row that lost its own numbers shows up.
        XCTAssertEqual(
            Set(viewModel.profileRows.map {
                [$0.entryRateText, $0.aggressionText, $0.callingTendencyText]
            }).count,
            4
        )
    }

    @MainActor
    private func makeViewModel(
        sessionStore: FileSessionRecordStore? = nil,
        pack: StrategyPack? = nil
    ) async throws -> SessionViewModel {
        SessionViewModel(
            sessionStore: try sessionStore ?? FileSessionRecordStore(
                directory: SessionReviewFixture.temporaryDirectory()
            ),
            eventStore: RefusingEventStore(),
            strategyProvider: InMemoryStrategyPackProvider(
                pack: try pack ?? SessionReviewFixture.corePack()
            ),
            makeSeed: { 16 }
        )
    }
}
