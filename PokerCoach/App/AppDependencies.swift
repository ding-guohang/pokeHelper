import Foundation
import StrategyContent
import TrainingDomain
import TrainingPersistence
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppDependencies {
    let eventStore: any TrainingEventStore
    private(set) var strategyProvider: any StrategyPackProviding
    let scorer: DecisionScorer
    let playerModelReducer: PlayerModelReducer
    let planner: TrainingPlanner
    private(set) var localTrainingCatalog: [TrainingCatalogItem]
    private(set) var strategyContentAvailability: StrategyContentAvailability
    /// Review status of each installed pack, keyed by pack ID. Review reads it
    /// to disclose the provenance of a history entry, which it can only do for
    /// packs that are actually present.
    private(set) var installedContent: [String: (ReviewStatus, ContentOrigin)]
    let localUserID: UUID
    let deviceID: UUID
    let accountSession: AccountSessionController

    /// Bumped whenever local history changes, so Today and Review reload after
    /// a remote merge rather than showing a stale reduction.
    private(set) var eventStoreRevision: Int


    init(
        eventStore: any TrainingEventStore,
        strategyProvider: any StrategyPackProviding,
        scorer: DecisionScorer = DecisionScorer(),
        playerModelReducer: PlayerModelReducer = PlayerModelReducer(),
        planner: TrainingPlanner = TrainingPlanner(),
        localTrainingCatalog: [TrainingCatalogItem],
        localIdentity: LocalIdentity,
        strategyContentAvailability: StrategyContentAvailability,
        installedContent: [String: (ReviewStatus, ContentOrigin)] = [:],
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
        self.installedContent = installedContent
        let session = accountSession
            ?? AppDependencies.makeAccountSession(localIdentity: localIdentity)
        self.accountSession = session
        pendingRevocation = PendingRevocationProcessor(
            credentials: KeychainCredentialStore(vault: KeychainVault()),
            api: RemoteAccountAPI(client: APIClient(baseURL: AppDependencies.accountServiceBaseURL))
        )
        self.eventStoreRevision = 0
    }

    /// Revokes tokens parked by an offline logout. Driven by launch,
    /// foreground, and network-restored signals.
    let pendingRevocation: PendingRevocationProcessor

    /// Applies content updates. Present even while no source can offer one, so
    /// the path from launch to `checkForUpdate()` exists and is exercised
    /// rather than being written and left dormant.
    private(set) var contentUpdate: ContentUpdateCoordinator?

    /// Installs the content update path. Separate from `init` because it needs
    /// the resolved pack, which only the content-available constructor has.
    func installContentUpdate(
        pack: StrategyPack,
        availability: StrategyContentAvailability,
        source: any ContentUpdateSource = BundledOnlyContentSource()
    ) {
        contentUpdate = ContentUpdateCoordinator(
            current: pack,
            availability: availability,
            source: source
        )
    }

    /// Checks for newer content. Called on launch; safe to call repeatedly.
    @discardableResult
    func checkForContentUpdate() async -> ContentUpdateOutcome {
        guard let contentUpdate else {
            return .noCandidate
        }
        let outcome = (try? await contentUpdate.checkForUpdate()) ?? .noCandidate
        if case .adopted = outcome {
            adoptContent(
                pack: contentUpdate.currentPack,
                availability: contentUpdate.availability
            )
        }
        return outcome
    }

    /// Makes an adopted pack the content the app actually trains against.
    ///
    /// Without this the coordinator swapped its own `currentPack`, returned
    /// `.adopted`, and nothing else moved: `strategyProvider` still served the
    /// old pack, the catalog still listed the old scenarios, and the
    /// disclosure still described the old review status. The whole update path
    /// reported success and changed nothing a user could reach.
    ///
    /// There is deliberately no "content changed" signal here. Today and Review
    /// capture their catalog when SwiftUI first builds their `@State` view
    /// model, so a pack adopted after that point is not reflected until the
    /// view model is rebuilt. Closing that window needs the two screens to
    /// derive their catalog from the provider instead of from a captured copy;
    /// it is not closed by adding a revision counter nothing reads, which is
    /// the same kind of decoration as an adoption nothing installs. The window
    /// is unreachable today — `BundledOnlyContentSource` never offers a
    /// candidate — and must be closed before a real update source ships.
    ///
    /// Known limitation: `installedContent` is keyed by pack ID alone, so a
    /// pack that changes review status between versions relabels the
    /// provenance of history recorded under the earlier version. Events carry
    /// `strategyContentVersion` too; keying on the pair would be more faithful
    /// to "history keeps its own content version", but every past version
    /// would then miss and fall back to "内容来源未知". Which of those is the
    /// better answer is a product call, not one to settle silently here.
    private func adoptContent(
        pack: StrategyPack,
        availability: StrategyContentAvailability
    ) {
        strategyProvider = InMemoryStrategyPackProvider(pack: pack)
        localTrainingCatalog = RuntimeTrainingCatalog.items(from: pack)
        strategyContentAvailability = availability
        installedContent[pack.manifest.id] = (
            pack.manifest.reviewStatus,
            pack.manifest.origin
        )
    }

    /// Assembles the account, profile, and sync layers. Without it each layer
    /// works in isolation and none of them runs in the product.
    private(set) var syncCoordinator: SyncCoordinator?

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

    /// Installs the coordinator that drives profile switching and sync.
    ///
    /// Kept out of `init` because it needs the fully built dependencies and a
    /// storage root, and because tests construct dependencies without it.
    func installSyncCoordinator(root: URL) {
        let profiles = ActiveProfileController(
            associations: ProfileAssociationStore(directory: root),
            directories: ProfileDirectoryProvider(root: root)
        )
        syncCoordinator = SyncCoordinator(
            account: accountSession,
            profiles: profiles,
            root: root,
            makeEngine: { [weak self] profile in
                guard let self else {
                    throw AppDependencyError.libraryDirectoryUnavailable
                }
                return try AppDependencies.makeSyncEngine(
                    store: try AppDependencies.syncTrackingEventStore(in: profile.directory),
                    directory: profile.directory,
                    authorizer: self.accountSession.authorizer,
                    onHistoryChanged: { [weak self] in
                        await MainActor.run { self?.eventStoreRevision += 1 }
                    }
                )
            }
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
        let dependencies = availableContent(
            eventStore: try syncTrackingEventStore(in: storageDirectory),
            strategyPack: try developmentStrategyPack(),
            localIdentity: localIdentity,
            strategyContentAvailability: .developmentFixtureAvailable
        )
#else
        // First production path that constructs a trainable availability. Until
        // M1C there was no bundled content at all, so this branch could only
        // ever report reviewedContentUnavailable.
        // A bundle with no trainable content is a shippable state -- the
        // "未安装已审核策略内容" screen exists for it -- so it must not abort.
        guard let loaded = try? BundledContentLoader(bundle: .main).loadPreferredPack()
        else {
            let dependencies = reviewedContentUnavailable(
                eventStore: try syncTrackingEventStore(in: storageDirectory),
                localIdentity: localIdentity
            )
            dependencies.installSyncCoordinator(root: try liveProfileRoot())
            return dependencies
        }
        let dependencies = availableContent(
            eventStore: try syncTrackingEventStore(in: storageDirectory),
            strategyPack: loaded.pack,
            localIdentity: localIdentity,
            strategyContentAvailability: loaded.availability,
            installedContent: loaded.installedContent
        )
#endif
        dependencies.installSyncCoordinator(root: try liveProfileRoot())
        return dependencies
    }

    /// Root of the profile layout. Exposed so the coordinator can be installed
    /// against the same directory startup resolved from.
    static func liveProfileRoot() throws -> URL {
        try liveStorageDirectory()
    }

    static func recoverCorruptedTrainingEvents() throws {
        _ = try recoverCorruptedTrainingEvents(
            in: try startupProfile().directory
        )
    }

    /// Synchronization stack for a profile. Training never waits on it: every
    /// failure leaves the local history untouched and retries later.
    static func makeSyncEngine(
        store: SyncTrackingTrainingEventStore,
        directory: URL,
        authorizer: SessionAuthorizer,
        onHistoryChanged: @escaping @Sendable () async -> Void
    ) throws -> SyncEngine {
        SyncEngine(
            store: store,
            outbox: try FileOutboxStore(directory: directory),
            state: try FileSyncStateStore(directory: directory),
            api: RemoteSyncAPI(baseURL: accountServiceBaseURL),
            authorizer: authorizer,
            onHistoryChanged: onHistoryChanged
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
        strategyContentAvailability: StrategyContentAvailability,
        installedContent: [String: (ReviewStatus, ContentOrigin)]? = nil
    ) -> AppDependencies {
        precondition(
            strategyContentAvailability.canStartTraining,
            "Available strategy content requires a trainable availability"
        )
        let dependencies = AppDependencies(
            eventStore: eventStore,
            strategyProvider: InMemoryStrategyPackProvider(
                pack: strategyPack
            ),
            localTrainingCatalog: RuntimeTrainingCatalog.items(
                from: strategyPack
            ),
            localIdentity: localIdentity,
            strategyContentAvailability: strategyContentAvailability,
            installedContent: installedContent ?? [
                strategyPack.manifest.id: (
                    strategyPack.manifest.reviewStatus,
                    strategyPack.manifest.origin
                ),
            ]
        )
        dependencies.installContentUpdate(
            pack: strategyPack,
            availability: strategyContentAvailability
        )
        return dependencies
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
                curriculumNodeID: scenario.curriculumNodeID,
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
