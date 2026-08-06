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

    init(
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer = DecisionScorer(),
        playerModelReducer: PlayerModelReducer = PlayerModelReducer(),
        planner: TrainingPlanner = TrainingPlanner(),
        localTrainingCatalog: [TrainingCatalogItem] =
            M1ALocalTrainingCatalog.cashItems
    ) {
        self.eventStore = eventStore
        self.strategyProvider = strategyProvider
        self.scorer = scorer
        self.playerModelReducer = playerModelReducer
        self.planner = planner
        self.localTrainingCatalog = localTrainingCatalog
    }

    static func live() throws -> AppDependencies {
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            throw AppDependencyError.libraryDirectoryUnavailable
        }

        return try make(
            storageDirectory: libraryDirectory.appending(
                path: "PokerCoach",
                directoryHint: .isDirectory
            )
        )
    }

    static let preview: AppDependencies = {
        do {
            return try make(
                storageDirectory: FileManager.default.temporaryDirectory
                    .appending(
                        path: "PokerCoachPreview-\(UUID().uuidString)",
                        directoryHint: .isDirectory
                    )
            )
        } catch {
            preconditionFailure("无法初始化预览依赖：\(error)")
        }
    }()

    private static func make(
        storageDirectory: URL
    ) throws -> AppDependencies {
        AppDependencies(
            eventStore: try FileTrainingEventStore(
                directory: storageDirectory
            ),
            strategyProvider: PendingStrategyPackProvider()
        )
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
