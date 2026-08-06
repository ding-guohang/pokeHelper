import XCTest
import TrainingDomain
@testable import PokerCoach

@MainActor
final class AppBootstrapTests: XCTestCase {
    func testReviewedContentUnavailableKeepsCatalogMetadataIndependent()
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
            [
                "cash-bet-sizing",
                "cash-preflop-range",
                "cash-flop-cbet",
            ]
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
