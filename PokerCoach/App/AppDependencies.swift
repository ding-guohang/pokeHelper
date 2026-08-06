import Foundation
import StrategyContent
import TrainingDomain

@MainActor
final class AppDependencies {
    let eventStore: any TrainingEventStore
    let strategyProvider: any StrategyPackProviding
    let scorer: DecisionScorer
    let playerModelReducer: PlayerModelReducer
    let planner: TrainingPlanner
    let localTrainingCatalog: [TrainingCatalogItem]
    let strategyContentAvailability: StrategyContentAvailability

    init(
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer = DecisionScorer(),
        playerModelReducer: PlayerModelReducer = PlayerModelReducer(),
        planner: TrainingPlanner = TrainingPlanner(),
        localTrainingCatalog: [TrainingCatalogItem] =
            M1ALocalTrainingCatalog.cashItems,
        strategyContentAvailability: StrategyContentAvailability
    ) {
        self.eventStore = eventStore
        self.strategyProvider = strategyProvider
        self.scorer = scorer
        self.playerModelReducer = playerModelReducer
        self.planner = planner
        self.localTrainingCatalog = localTrainingCatalog
        self.strategyContentAvailability = strategyContentAvailability
    }

    static func live() throws -> AppDependencies {
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            throw AppDependencyError.libraryDirectoryUnavailable
        }

        let storageDirectory = libraryDirectory.appending(
            path: "PokerCoach",
            directoryHint: .isDirectory
        )

#if DEVELOPMENT_STRATEGY_FIXTURES
        try resetTrainingEventsIfRequested(
            storageDirectory: storageDirectory
        )
        return AppDependencies(
            eventStore: try FileTrainingEventStore(
                directory: storageDirectory
            ),
            strategyProvider: try developmentStrategyProvider(),
            strategyContentAvailability: .developmentFixtureAvailable
        )
#else
        return reviewedContentUnavailable(
            eventStore: try FileTrainingEventStore(
                directory: storageDirectory
            )
        )
#endif
    }

    static let preview: AppDependencies = {
        do {
            return reviewedContentUnavailable(
                eventStore: try FileTrainingEventStore(
                    directory: FileManager.default.temporaryDirectory
                        .appending(
                            path: "PokerCoachPreview-\(UUID().uuidString)",
                            directoryHint: .isDirectory
                        )
                )
            )
        } catch {
            preconditionFailure("无法初始化预览依赖：\(error)")
        }
    }()

    static func reviewedContentUnavailable(
        eventStore: any TrainingEventStore
    ) -> AppDependencies {
        AppDependencies(
            eventStore: eventStore,
            strategyProvider: PendingStrategyPackProvider(),
            strategyContentAvailability: .reviewedContentUnavailable
        )
    }

#if DEVELOPMENT_STRATEGY_FIXTURES
    private static func resetTrainingEventsIfRequested(
        storageDirectory: URL
    ) throws {
        guard CommandLine.arguments.contains("--reset-training-events") else {
            return
        }

        let eventFile = storageDirectory.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        guard FileManager.default.fileExists(atPath: eventFile.path()) else {
            return
        }

        try FileManager.default.removeItem(at: eventFile)
    }

    private static func developmentStrategyProvider() throws
        -> any StrategyPackProviding
    {
        guard let fixtureURL = Bundle.main.url(
            forResource: "DevStrategyPack",
            withExtension: "json"
        ) else {
            throw AppDependencyError.strategyPackUnavailable
        }

        let pack = try StrategyPackLoader().load(
            data: Data(contentsOf: fixtureURL),
            expectedSHA256: nil
        )
        return InMemoryStrategyPackProvider(pack: pack)
    }
#endif
}

private enum AppDependencyError: Error {
    case libraryDirectoryUnavailable
    case strategyPackUnavailable
}

private struct PendingStrategyPackProvider: StrategyPackProviding {
    func pack() async throws -> StrategyPack {
        throw AppDependencyError.strategyPackUnavailable
    }

    func scenario(id: String) async throws -> DecisionScenario {
        throw AppDependencyError.strategyPackUnavailable
    }
}
