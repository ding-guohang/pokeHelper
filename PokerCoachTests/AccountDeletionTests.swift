import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

@MainActor
final class AccountDeletionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Deletion-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // Keeping the data detaches it from the account: the same hands stay
    // trainable, just without a cloud identity.
    func testKeepingLocalDataAnonymizesTheProfileAndPreservesHistory() async throws {
        let controller = makeProfileController()
        let account = UUID()
        let profile = try await controller.activate(remoteUserID: account)
        let event = try TrainingEventFixture.make(
            localUserID: profile.localUserID,
            deviceID: profile.deviceID
        )
        try await FileTrainingEventStore(directory: profile.directory).append(event)

        let anonymous = try await controller.applyLocalDeletion(
            .keepAnonymized,
            remoteUserID: account
        )

        XCTAssertEqual(anonymous.id, .anonymous)
        let events = try await FileTrainingEventStore(
            directory: anonymous.directory
        ).allEvents()
        XCTAssertEqual(events.map(\.id), [event.id], "kept history must survive intact")
    }

    // Deleting must take the events, the upload queue, the sync state, and the
    // corrupted backups together. Any one left behind keeps a deleted
    // account's hands readable on this device.
    func testDeletingEverythingRemovesTheWholeProfileDirectory() async throws {
        let controller = makeProfileController()
        let account = UUID()
        let profile = try await controller.activate(remoteUserID: account)

        try await FileTrainingEventStore(directory: profile.directory).append(
            try TrainingEventFixture.make(
                localUserID: profile.localUserID,
                deviceID: profile.deviceID
            )
        )
        let outbox = try FileOutboxStore(directory: profile.directory)
        try await outbox.enqueue(UUID())
        let state = try FileSyncStateStore(directory: profile.directory)
        try await state.setCheckpoint(7)
        let backup = profile.directory.appending(
            path: "training-events.corrupted-\(UUID().uuidString).jsonl",
            directoryHint: .notDirectory
        )
        try Data("broken".utf8).write(to: backup)

        _ = try await controller.applyLocalDeletion(.deleteEverything, remoteUserID: account)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: profile.directory.path(percentEncoded: false)
            ),
            "the profile directory and everything in it must be gone"
        )
    }

    func testDeletingOneAccountLeavesAnotherProfileUntouched() async throws {
        let controller = makeProfileController()
        let deleted = UUID()
        let bystander = UUID()

        let bystanderProfile = try await controller.activate(remoteUserID: bystander)
        let event = try TrainingEventFixture.make(
            localUserID: bystanderProfile.localUserID,
            deviceID: bystanderProfile.deviceID
        )
        try await FileTrainingEventStore(directory: bystanderProfile.directory).append(event)
        _ = try await controller.activate(remoteUserID: deleted)

        _ = try await controller.applyLocalDeletion(.deleteEverything, remoteUserID: deleted)

        let restored = try await controller.activate(remoteUserID: bystander)
        let events = try await FileTrainingEventStore(
            directory: restored.directory
        ).allEvents()
        XCTAssertEqual(events.map(\.id), [event.id])
    }

    // The remote deletion happens first. Clearing local data for a deletion
    // that never happened would destroy the user's hands for nothing.
    func testRemoteFailureLeavesTheAccountAndLocalDataAlone() async throws {
        let harness = try Harness(root: root)
        await harness.controller.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )
        harness.api.failEverything = .offline

        await harness.controller.deleteAccount(localChoice: .deleteEverything)

        XCTAssertFalse(harness.localDeletionApplied)
        XCTAssertNotNil(harness.controller.failure)
        let stored = try await harness.credentials.loadActive()
        XCTAssertNotNil(stored, "a failed deletion must not sign the user out")
    }

    func testSuccessfulDeletionClearsCredentialsAndAppliesTheLocalChoice() async throws {
        let harness = try Harness(root: root)
        await harness.controller.login(
            email: "player@example.test",
            password: "a-sufficiently-long-passphrase"
        )

        await harness.controller.deleteAccount(localChoice: .keepAnonymized)

        XCTAssertEqual(harness.controller.state, .anonymous)
        XCTAssertEqual(harness.appliedChoice, .keepAnonymized)
        let stored = try await harness.credentials.loadActive()
        XCTAssertNil(stored)
    }

    func testDeletingWithoutAnAccountIsRefused() async throws {
        let harness = try Harness(root: root)

        await harness.controller.deleteAccount(localChoice: .deleteEverything)

        XCTAssertFalse(harness.localDeletionApplied)
        XCTAssertNotNil(harness.controller.failure)
    }

    private func makeProfileController() -> ActiveProfileController {
        ActiveProfileController(
            associations: ProfileAssociationStore(directory: root),
            directories: ProfileDirectoryProvider(root: root)
        )
    }
}

@MainActor
private final class Harness {
    let api = DeletionAPIDouble()
    let credentials: CredentialStore
    let controller: AccountSessionController

    private(set) var localDeletionApplied = false
    private(set) var appliedChoice: LocalDeletionChoice?

    init(root: URL) throws {
        credentials = KeychainCredentialStore(vault: InMemoryVault())
        controller = AccountSessionController(
            api: api,
            credentials: credentials,
            apple: NoopAppleClient(),
            policy: PasswordPolicy(blocklist: []),
            device: DeviceDescriptor(
                deviceID: UUID(),
                displayName: "iPhone",
                platform: "iOS",
                appVersion: "1.0.0"
            )
        )
        controller.onAccountDeleted = { [weak self] _, choice in
            self?.localDeletionApplied = true
            self?.appliedChoice = choice
        }
    }
}

private final class DeletionAPIDouble: StubAccountAPI, @unchecked Sendable {
    enum Behavior {
        case offline
    }

    var failEverything: Behavior?

    override func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        try failIfConfigured()
        return .fixture()
    }

    override func deleteAccount(accessToken: String) async throws {
        try failIfConfigured()
    }

    private func failIfConfigured() throws {
        if failEverything == .offline {
            throw APIError.offline
        }
    }
}

private struct NoopAppleClient: AppleAuthorizationClient {
    func requestCredential() async throws -> AppleCredential {
        AppleCredential(identityToken: "token", nonce: "nonce")
    }
}
