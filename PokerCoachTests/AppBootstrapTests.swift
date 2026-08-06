import XCTest
@testable import PokerCoach

@MainActor
final class AppBootstrapTests: XCTestCase {
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
