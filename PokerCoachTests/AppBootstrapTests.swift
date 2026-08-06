import XCTest
import StrategyContent
import TrainingDomain
@testable import PokerCoach

@MainActor
final class AppBootstrapTests: XCTestCase {
    func testAvailableContentKeepsDashboardRecommendationsLoadableAfterExcellentDecision()
        async throws
    {
        let pack = DecisionSessionFixture.makePack(
            scenarioID: "cash-bet-sizing",
            abilityDimension: "bet-sizing"
        )
        let store = InMemoryTrainingEventStore()
        let dependencies = AppDependencies.availableContent(
            eventStore: store,
            strategyPack: pack,
            strategyContentAvailability: .developmentFixtureAvailable
        )
        let scenarioIDs = dependencies.localTrainingCatalog.map(\.scenarioID)

        XCTAssertEqual(scenarioIDs, ["cash-bet-sizing"])
        for scenarioID in scenarioIDs {
            _ = try await dependencies.strategyProvider.scenario(id: scenarioID)
        }

        let session = DecisionSessionViewModel(
            scenarioID: "cash-bet-sizing",
            strategyProvider: dependencies.strategyProvider,
            scorer: dependencies.scorer,
            eventStore: dependencies.eventStore,
            localUserID: DecisionSessionFixture.localUserID,
            deviceID: DecisionSessionFixture.deviceID,
            makeEventID: { DecisionSessionFixture.eventID },
            now: { DecisionSessionFixture.occurredAt }
        )
        await session.load()
        let scenario = try XCTUnwrap(session.scenario)
        let bestAction = try XCTUnwrap(
            scenario.options.max(by: { $0.ev < $1.ev })?.action
        )
        session.select(action: bestAction)
        session.setConfidence(.verySure)
        await session.submit()
        XCTAssertEqual(session.grade?.quality, .excellent)

        let today = TodayViewModel(
            eventStore: dependencies.eventStore,
            reducer: dependencies.playerModelReducer,
            planner: dependencies.planner,
            catalog: dependencies.localTrainingCatalog,
            strategyContentAvailability:
                dependencies.strategyContentAvailability
        )
        let review = ReviewViewModel(
            eventStore: dependencies.eventStore,
            reducer: dependencies.playerModelReducer,
            planner: dependencies.planner,
            catalog: dependencies.localTrainingCatalog,
            strategyContentAvailability:
                dependencies.strategyContentAvailability
        )
        await today.refresh()
        await review.refresh()

        XCTAssertEqual(today.durationText, "约 8 分钟")
        let recommendedScenarioIDs = [
            today.startPrimaryItem(),
            review.startSuggestedTraining(),
        ].compactMap { $0 }
        XCTAssertEqual(
            recommendedScenarioIDs,
            ["cash-bet-sizing", "cash-bet-sizing"]
        )
        for scenarioID in recommendedScenarioIDs {
            _ = try await dependencies.strategyProvider.scenario(id: scenarioID)
        }
    }

    func testRuntimeCatalogKeepsOneToThreePlannedScenariosWithinDailyDuration()
    {
        XCTAssertEqual(
            RuntimeTrainingCatalog.estimatedMinutesPerItem(
                forScenarioCount: 1
            ),
            8
        )

        for scenarioCount in 1...6 {
            let plannedScenarioCount = min(scenarioCount, 3)
            let totalMinutes =
                RuntimeTrainingCatalog.estimatedMinutesPerItem(
                    forScenarioCount: scenarioCount
                ) * plannedScenarioCount

            XCTAssertTrue(
                (5...10).contains(totalMinutes),
                "\(scenarioCount) scenarios produced \(totalMinutes) minutes"
            )
        }
    }

    func testReviewedContentUnavailableHasNoTrainableCatalog()
        async
    {
        let dependencies = AppDependencies.reviewedContentUnavailable(
            eventStore: InMemoryTrainingEventStore()
        )

        XCTAssertEqual(
            dependencies.strategyContentAvailability,
            .reviewedContentUnavailable
        )
        XCTAssertEqual(
            dependencies.localTrainingCatalog.map(\.id),
            []
        )
        XCTAssertEqual(
            dependencies.strategyContentAvailability.disclosureText,
            "未安装已审核策略内容"
        )

        do {
            _ = try await dependencies.strategyProvider.pack()
            XCTFail("Reviewed-content-unavailable mode must not load a pack")
        } catch {
            // Expected: Release has catalog metadata but no strategy content.
        }
    }

    func testSuccessfulLoadPublishesOriginalDependenciesInstance() {
        let expectedDependencies = AppDependencies.preview
        let bootstrap = AppBootstrap {
            expectedDependencies
        }

        guard case .loading = bootstrap.state else {
            return XCTFail("Expected loading before composition")
        }

        bootstrap.loadIfNeeded()

        guard case let .content(actualDependencies) = bootstrap.state else {
            return XCTFail("Expected content after successful composition")
        }
        XCTAssertTrue(actualDependencies === expectedDependencies)
    }

    func testFailedLoadPublishesFailureState() {
        let bootstrap = AppBootstrap {
            throw StubBootstrapError.unavailable
        }

        bootstrap.loadIfNeeded()

        guard case .failure = bootstrap.state else {
            return XCTFail("Expected recoverable failure")
        }
    }

    func testRetryRunsLoaderAgainAfterFailure() {
        let expectedDependencies = AppDependencies.preview
        var loadCount = 0
        let bootstrap = AppBootstrap {
            loadCount += 1
            if loadCount == 1 {
                throw StubBootstrapError.unavailable
            }
            return expectedDependencies
        }
        bootstrap.loadIfNeeded()

        bootstrap.retry()

        XCTAssertEqual(loadCount, 2)
        guard case let .content(actualDependencies) = bootstrap.state else {
            return XCTFail("Expected content after retry")
        }
        XCTAssertTrue(actualDependencies === expectedDependencies)
    }
}

private enum StubBootstrapError: Error {
    case unavailable
}
