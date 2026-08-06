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
    let localUserID: UUID
    let deviceID: UUID

    init(
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer = DecisionScorer(),
        playerModelReducer: PlayerModelReducer = PlayerModelReducer(),
        planner: TrainingPlanner = TrainingPlanner(),
        localTrainingCatalog: [TrainingCatalogItem],
        localIdentity: LocalIdentity,
        strategyContentAvailability: StrategyContentAvailability
    ) {
        self.eventStore = eventStore
        self.strategyProvider = strategyProvider
        self.scorer = scorer
        self.playerModelReducer = playerModelReducer
        self.planner = planner
        self.localTrainingCatalog = localTrainingCatalog
        localUserID = localIdentity.localUserID
        deviceID = localIdentity.deviceID
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
        let localIdentity = LocalIdentityStore().loadOrCreate()

#if DEVELOPMENT_STRATEGY_FIXTURES
        try resetTrainingEventsIfRequested(
            storageDirectory: storageDirectory
        )
        return availableContent(
            eventStore: try FileTrainingEventStore(
                directory: storageDirectory
            ),
            strategyPack: try developmentStrategyPack(),
            localIdentity: localIdentity,
            strategyContentAvailability: .developmentFixtureAvailable
        )
#else
        return reviewedContentUnavailable(
            eventStore: try FileTrainingEventStore(
                directory: storageDirectory
            ),
            localIdentity: localIdentity
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
                ),
                localIdentity: .preview
            )
        } catch {
            preconditionFailure("无法初始化预览依赖：\(error)")
        }
    }()

    static func reviewedContentUnavailable(
        eventStore: any TrainingEventStore,
        localIdentity: LocalIdentity = .preview
    ) -> AppDependencies {
        AppDependencies(
            eventStore: eventStore,
            strategyProvider: PendingStrategyPackProvider(),
            localTrainingCatalog: [],
            localIdentity: localIdentity,
            strategyContentAvailability: .reviewedContentUnavailable
        )
    }

    static func availableContent(
        eventStore: any TrainingEventStore,
        strategyPack: StrategyPack,
        localIdentity: LocalIdentity = .preview,
        strategyContentAvailability: StrategyContentAvailability
    ) -> AppDependencies {
        precondition(
            strategyContentAvailability.canStartTraining,
            "Available strategy content requires a trainable availability"
        )
        return AppDependencies(
            eventStore: eventStore,
            strategyProvider: InMemoryStrategyPackProvider(
                pack: strategyPack
            ),
            localTrainingCatalog: RuntimeTrainingCatalog.items(
                from: strategyPack
            ),
            localIdentity: localIdentity,
            strategyContentAvailability: strategyContentAvailability
        )
    }

    func makeDecisionSessionViewModel(
        scenarioID: String
    ) -> DecisionSessionViewModel {
        DecisionSessionViewModel(
            scenarioID: scenarioID,
            strategyProvider: strategyProvider,
            scorer: scorer,
            eventStore: eventStore,
            localUserID: localUserID,
            deviceID: deviceID
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
        guard FileManager.default.fileExists(
            atPath: eventFile.path(percentEncoded: false)
        ) else {
            return
        }

        try FileManager.default.removeItem(at: eventFile)
    }

    private static func developmentStrategyPack() throws -> StrategyPack {
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
        return pack
    }
#endif
}

enum RuntimeTrainingCatalog {
    static func items(from pack: StrategyPack) -> [TrainingCatalogItem] {
        let estimatedMinutes = estimatedMinutesPerItem(
            forScenarioCount: pack.scenarios.count
        )
        return pack.scenarios.map { scenario in
            TrainingCatalogItem(
                id: scenario.id,
                scenarioID: scenario.id,
                abilityDimension: scenario.abilityDimension,
                estimatedMinutes: estimatedMinutes
            )
        }
    }

    static func estimatedMinutesPerItem(
        forScenarioCount scenarioCount: Int
    ) -> Int {
        let plannedScenarioCount = min(max(scenarioCount, 0), 3)
        guard plannedScenarioCount > 0 else {
            return 0
        }

        return max(3, 8 / plannedScenarioCount)
    }
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
