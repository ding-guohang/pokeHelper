import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

/// These tests assert the app is assembled, not that its parts work.
///
/// Every other suite builds its own harness, so profile switching, sync, and
/// local deletion were all fully tested and simultaneously unreachable in the
/// shipped app: nothing constructed them. A unit test cannot notice that. These
/// drive the coordinator the way the app does.
@MainActor
final class SyncCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Coordinator-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLaunchActivatesAProfileAndRunsOneSynchronization() async throws {
        let harness = try Harness(root: root)

        await harness.coordinator.start()

        XCTAssertNotNil(
            harness.account.activeProfile,
            "the account controller needs a profile before it can export"
        )
        XCTAssertEqual(harness.engineRuns, 1, "launch must install an engine for the active profile")
    }

    // Signing in must adopt the anonymous history exactly once, then keep the
    // account's own profile on later state changes.
    func testSigningInClaimsTheAnonymousProfile() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()
        let anonymous = harness.account.activeProfile

        await harness.account.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )
        await harness.coordinator.accountStateChanged()

        let claimed = harness.account.activeProfile
        XCTAssertNotEqual(claimed?.id, anonymous?.id)
        XCTAssertEqual(
            claimed?.localUserID,
            anonymous?.localUserID,
            "the first account adopts the anonymous history"
        )
    }

    func testSigningOutReturnsToAnAnonymousProfile() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()
        await harness.account.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )
        await harness.coordinator.accountStateChanged()

        await harness.account.logOut()
        await harness.coordinator.accountStateChanged()

        XCTAssertEqual(harness.account.activeProfile?.id, .anonymous)
    }

    // Two accounts on one installation must not share a directory.
    func testASecondAccountGetsItsOwnProfile() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()

        harness.api.userID = UUID()
        await harness.account.login(email: "a@example.test", password: "a-sufficiently-long-passphrase")
        await harness.coordinator.accountStateChanged()
        let first = harness.account.activeProfile

        await harness.account.logOut()
        await harness.coordinator.accountStateChanged()

        harness.api.userID = UUID()
        await harness.account.login(email: "b@example.test", password: "a-sufficiently-long-passphrase")
        await harness.coordinator.accountStateChanged()
        let second = harness.account.activeProfile

        XCTAssertNotEqual(first?.directory, second?.directory)
        XCTAssertNotEqual(first?.localUserID, second?.localUserID)
    }

    // The UI promises "同时删除本机训练记录". Something has to honour it.
    func testDeletingAnAccountAppliesTheLocalChoice() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()
        await harness.account.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )
        await harness.coordinator.accountStateChanged()
        let profile = try XCTUnwrap(harness.account.activeProfile)
        try Data("{}\n".utf8).write(
            to: profile.directory.appending(
                path: "training-events.jsonl",
                directoryHint: .notDirectory
            )
        )

        await harness.account.deleteAccount(localChoice: .deleteEverything)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: profile.directory.path(percentEncoded: false)
            ),
            "choosing full deletion must remove the profile directory"
        )
    }

    // The engine owns the in-flight batch and the outbox handle, so rebuilding
    // it on every foreground would discard a retry already in progress.
    func testTheEngineIsBuiltOncePerProfileNotOncePerSync() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()

        await harness.coordinator.synchronize(reason: .foreground)
        await harness.coordinator.synchronize(reason: .manualRetry)

        XCTAssertEqual(harness.engineRuns, 1)
    }

    func testSwitchingProfilesRebuildsTheEngineForTheNewDirectory() async throws {
        let harness = try Harness(root: root)
        await harness.coordinator.start()

        await harness.account.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )
        await harness.coordinator.accountStateChanged()

        XCTAssertEqual(
            harness.engineRuns,
            2,
            "the claimed profile has its own directory, so it needs its own engine"
        )
    }
}

@MainActor
private final class Harness {
    let api = CoordinatorAPIDouble()
    let account: AccountSessionController
    let coordinator: SyncCoordinator

    private let counter = RunCounter()

    var engineRuns: Int { counter.value }

    init(root: URL) throws {
        account = AccountSessionController(
            api: api,
            credentials: KeychainCredentialStore(vault: InMemoryVault()),
            apple: CoordinatorAppleClient(),
            policy: PasswordPolicy(blocklist: []),
            device: DeviceDescriptor(
                deviceID: UUID(),
                displayName: "iPhone",
                platform: "iOS",
                appVersion: "1.0.0"
            )
        )

        let counter = self.counter
        coordinator = SyncCoordinator(
            account: account,
            profiles: ActiveProfileController(
                associations: ProfileAssociationStore(directory: root),
                directories: ProfileDirectoryProvider(root: root)
            ),
            root: root,
            makeEngine: { profile in
                counter.increment()
                return try AppDependencies.makeSyncEngine(
                    store: try AppDependencies.syncTrackingEventStore(in: profile.directory),
                    directory: profile.directory,
                    authorizer: SessionAuthorizer(
                        store: KeychainCredentialStore(vault: InMemoryVault()),
                        api: StubAccountAPI()
                    ),
                    onHistoryChanged: {}
                )
            }
        )
    }
}

@MainActor
private final class RunCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private final class CoordinatorAPIDouble: StubAccountAPI, @unchecked Sendable {
    var userID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    override func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        session(for: userID)
    }

    private func session(for userID: UUID) -> StoredSession {
        StoredSession(
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: Date(timeIntervalSince1970: 1_786_400_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_788_000_000),
            userID: userID,
            sessionID: UUID(),
            recentAuthAt: Date(timeIntervalSince1970: 1_786_300_000),
            email: "player@example.test"
        )
    }
}

private struct CoordinatorAppleClient: AppleAuthorizationClient {
    func requestCredential() async throws -> AppleCredential {
        AppleCredential(identityToken: "token", nonce: "nonce")
    }
}
