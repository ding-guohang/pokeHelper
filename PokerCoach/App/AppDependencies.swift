import Foundation
import StrategyContent
import TrainingDomain
#if canImport(UIKit)
import UIKit
#endif

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
    let accountSession: AccountSessionController

    init(
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer = DecisionScorer(),
        playerModelReducer: PlayerModelReducer = PlayerModelReducer(),
        planner: TrainingPlanner = TrainingPlanner(),
        localTrainingCatalog: [TrainingCatalogItem],
        localIdentity: LocalIdentity,
        strategyContentAvailability: StrategyContentAvailability,
        accountSession: AccountSessionController? = nil
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
        self.accountSession = accountSession
            ?? AppDependencies.makeAccountSession(localIdentity: localIdentity)
    }

    /// Builds the account stack. Training never depends on it: with no account
    /// and no network the controller simply stays anonymous.
    static func makeAccountSession(
        localIdentity: LocalIdentity
    ) -> AccountSessionController {
        let api = RemoteAccountAPI(client: APIClient(baseURL: accountServiceBaseURL))
        return AccountSessionController(
            api: api,
            credentials: KeychainCredentialStore(vault: KeychainVault()),
            apple: SystemAppleAuthorizationClient(),
            policy: PasswordPolicy(),
            device: DeviceDescriptor(
                deviceID: localIdentity.deviceID,
                displayName: deviceDisplayName,
                platform: devicePlatform,
                appVersion: appVersion
            )
        )
    }

    static func live() throws -> AppDependencies {
        let profile = try startupProfile()
        let storageDirectory = profile.directory
        let localIdentity = LocalIdentity(
            localUserID: profile.localUserID,
            deviceID: profile.deviceID
        )

#if DEVELOPMENT_STRATEGY_FIXTURES
        try resetTrainingEventsIfRequested(
            storageDirectory: storageDirectory
        )
        return availableContent(
            eventStore: try syncTrackingEventStore(in: storageDirectory),
            strategyPack: try developmentStrategyPack(),
            localIdentity: localIdentity,
            strategyContentAvailability: .developmentFixtureAvailable
        )
#else
        return reviewedContentUnavailable(
            eventStore: try syncTrackingEventStore(in: storageDirectory),
            localIdentity: localIdentity
        )
#endif
    }

    static func recoverCorruptedTrainingEvents() throws {
        _ = try recoverCorruptedTrainingEvents(
            in: try startupProfile().directory
        )
    }

    /// Local event store that also queues each locally created event for
    /// upload. The queue lives in the same profile directory, so switching
    /// accounts switches the pending uploads with it.
    static func syncTrackingEventStore(
        in directory: URL
    ) throws -> SyncTrackingTrainingEventStore {
        SyncTrackingTrainingEventStore(
            underlying: try FileTrainingEventStore(directory: directory),
            outbox: try FileOutboxStore(directory: directory)
        )
    }

    /// Resolves the profile to open with, migrating an M1A installation on
    /// first launch. Startup is synchronous, so this reads the profile record
    /// directly instead of going through the actor.
    static func startupProfile() throws -> ActiveProfile {
        let root = try liveStorageDirectory()
        let records = ProfileRecordFile(directory: root)
        let directories = ProfileDirectoryProvider(root: root)

        try ProfileMigration.migrateLegacyInstallIfNeeded(
            root: root,
            records: records,
            directories: directories,
            legacyIdentity: LocalIdentityStore().storedIdentity()
        )

        let id = try records.lastActiveProfile()
        return ActiveProfile(
            id: id,
            localUserID: try records.localUserID(for: id),
            deviceID: try records.deviceID(),
            directory: try directories.createDirectory(for: id)
        )
    }

    static func recoverCorruptedTrainingEvents(
        in storageDirectory: URL,
        backupID: UUID = UUID()
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        let eventFile = storageDirectory.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        guard FileManager.default.fileExists(
            atPath: eventFile.path(percentEncoded: false)
        ) else {
            throw AppDependencyError.trainingHistoryUnavailable
        }

        let backupFile = storageDirectory.appending(
            path: "training-events.corrupted-\(backupID.uuidString).jsonl",
            directoryHint: .notDirectory
        )
        try FileManager.default.copyItem(
            at: eventFile,
            to: backupFile
        )
        try Data().write(to: eventFile, options: .atomic)
        return backupFile
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

    private static func liveStorageDirectory() throws -> URL {
        guard let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            throw AppDependencyError.libraryDirectoryUnavailable
        }

        return libraryDirectory.appending(
            path: "PokerCoach",
            directoryHint: .isDirectory
        )
    }
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
    case trainingHistoryUnavailable
}

extension AppDependencies {
    /// Sync service location. M1B does not ship a production deployment, so
    /// this defaults to a local development service and is overridden by the
    /// `AccountServiceBaseURL` Info.plist key when one is configured.
    static var accountServiceBaseURL: URL {
        if
            let configured = Bundle.main.object(
                forInfoDictionaryKey: "AccountServiceBaseURL"
            ) as? String,
            let url = URL(string: configured)
        {
            return url
        }
        return URL(string: "https://127.0.0.1:8443")!
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    }

    static var deviceDisplayName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        "iPhone"
        #endif
    }

    static var devicePlatform: String {
        #if canImport(UIKit)
        UIDevice.current.systemName
        #else
        "iOS"
        #endif
    }
}

private struct PendingStrategyPackProvider: StrategyPackProviding {
    func pack() async throws -> StrategyPack {
        throw AppDependencyError.strategyPackUnavailable
    }

    func scenario(id: String) async throws -> DecisionScenario {
        throw AppDependencyError.strategyPackUnavailable
    }
}
