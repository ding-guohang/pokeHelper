import Foundation
import TrainingDomain
import TrainingPersistence
import XCTest
@testable import PokerCoach

@MainActor
final class ActiveProfileControllerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "ActiveProfile-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStartsOnTheAnonymousProfile() async throws {
        let controller = makeController()

        let profile = try await controller.current()

        XCTAssertEqual(profile.id, .anonymous)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: profile.directory.path(percentEncoded: false))
        )
    }

    // Claiming must not rewrite a single byte of the anonymous log: the events
    // were already recorded, and rewriting them would break their identity and
    // any later idempotent upload.
    func testClaimingKeepsAnonymousEventBytesAndIdentifiersUnchanged() async throws {
        let controller = makeController()
        let anonymous = try await controller.current()
        let event = try TrainingEventFixture.make(
            localUserID: anonymous.localUserID,
            deviceID: anonymous.deviceID
        )
        let store = try FileTrainingEventStore(directory: anonymous.directory)
        try await store.append(event)
        let originalBytes = try Data(contentsOf: eventFile(in: anonymous.directory))

        let claimed = try await controller.claimCurrent(remoteUserID: UUID())

        let claimedBytes = try Data(contentsOf: eventFile(in: claimed.directory))
        XCTAssertEqual(claimedBytes, originalBytes, "claiming must not rewrite the log")

        let claimedStore = try FileTrainingEventStore(directory: claimed.directory)
        let events = try await claimedStore.allEvents()
        XCTAssertEqual(events.map(\.id), [event.id])
        XCTAssertEqual(events.first?.localUserID, anonymous.localUserID)
        XCTAssertEqual(events.first?.deviceID, anonymous.deviceID)
    }

    func testDeviceIDSurvivesAClaimAndAProfileSwitch() async throws {
        let controller = makeController()
        let anonymous = try await controller.current()

        let claimed = try await controller.claimCurrent(remoteUserID: UUID())
        let other = try await controller.activate(remoteUserID: UUID())

        XCTAssertEqual(claimed.deviceID, anonymous.deviceID)
        XCTAssertEqual(other.deviceID, anonymous.deviceID)
    }

    // Account A's cached history must be invisible to account B on the same
    // installation.
    func testSwitchingAccountsIsolatesTrainingHistory() async throws {
        let controller = makeController()
        let accountA = UUID()
        let accountB = UUID()

        let profileA = try await controller.activate(remoteUserID: accountA)
        let storeA = try FileTrainingEventStore(directory: profileA.directory)
        try await storeA.append(
            try TrainingEventFixture.make(
                localUserID: profileA.localUserID,
                deviceID: profileA.deviceID
            )
        )

        try await controller.lockCurrent()
        let profileB = try await controller.activate(remoteUserID: accountB)
        let storeB = try FileTrainingEventStore(directory: profileB.directory)

        let eventsB = try await storeB.allEvents()
        XCTAssertTrue(eventsB.isEmpty, "account B must not read account A's history")
        XCTAssertNotEqual(profileA.directory, profileB.directory)
        XCTAssertNotEqual(profileA.localUserID, profileB.localUserID)
    }

    func testReturningToAnAccountRestoresItsHistory() async throws {
        let controller = makeController()
        let accountA = UUID()

        let firstVisit = try await controller.activate(remoteUserID: accountA)
        let store = try FileTrainingEventStore(directory: firstVisit.directory)
        let event = try TrainingEventFixture.make(
            localUserID: firstVisit.localUserID,
            deviceID: firstVisit.deviceID
        )
        try await store.append(event)

        try await controller.lockCurrent()
        _ = try await controller.activate(remoteUserID: UUID())
        try await controller.lockCurrent()
        let secondVisit = try await controller.activate(remoteUserID: accountA)

        XCTAssertEqual(secondVisit.directory, firstVisit.directory)
        XCTAssertEqual(secondVisit.localUserID, firstVisit.localUserID)
        let restored = try await FileTrainingEventStore(
            directory: secondVisit.directory
        ).allEvents()
        XCTAssertEqual(restored.map(\.id), [event.id])
    }

    func testLockingReturnsToAFreshAnonymousProfileAfterAClaim() async throws {
        let controller = makeController()
        let firstAnonymous = try await controller.current()
        _ = try await controller.claimCurrent(remoteUserID: UUID())

        try await controller.lockCurrent()
        let secondAnonymous = try await controller.current()

        XCTAssertEqual(secondAnonymous.id, .anonymous)
        XCTAssertNotEqual(
            secondAnonymous.localUserID,
            firstAnonymous.localUserID,
            "claimed history belongs to the account, so anonymous starts over"
        )
    }

    // Corrupted-history backups are per profile, so recovering one account
    // never exposes another account's hands.
    func testCorruptHistoryBackupsStayInsideTheirOwnProfile() async throws {
        let controller = makeController()
        let profileA = try await controller.activate(remoteUserID: UUID())
        try writeCorruptHistory(in: profileA.directory)

        let backup = try AppDependencies.recoverCorruptedTrainingEvents(
            in: profileA.directory,
            backupID: UUID()
        )

        try await controller.lockCurrent()
        let profileB = try await controller.activate(remoteUserID: UUID())

        XCTAssertTrue(backup.path(percentEncoded: false).hasPrefix(
            profileA.directory.path(percentEncoded: false)
        ))
        let backupsInB = try FileManager.default.contentsOfDirectory(
            atPath: profileB.directory.path(percentEncoded: false)
        ).filter { $0.contains("corrupted") }
        XCTAssertTrue(backupsInB.isEmpty)
    }

    private func makeController() -> ActiveProfileController {
        ActiveProfileController(
            associations: ProfileAssociationStore(directory: root),
            directories: ProfileDirectoryProvider(root: root)
        )
    }

    private func eventFile(in directory: URL) -> URL {
        directory.appending(path: "training-events.jsonl", directoryHint: .notDirectory)
    }

    private func writeCorruptHistory(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json\n".utf8).write(to: eventFile(in: directory), options: .atomic)
    }
}

@MainActor
final class ProfileMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "ProfileMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // An M1A installation kept its log directly under the app directory. It has
    // to land in the anonymous profile byte for byte, or an upgrading user
    // opens M1B to an empty history.
    func testAnM1AInstallationKeepsItsHistoryAndIdentity() throws {
        let legacyIdentity = LocalIdentity(
            localUserID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        )
        let legacyLog = root.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        let legacyBytes = Data("{\"legacy\":true}\n".utf8)
        try legacyBytes.write(to: legacyLog, options: .atomic)
        let records = ProfileRecordFile(directory: root)
        let directories = ProfileDirectoryProvider(root: root)

        try ProfileMigration.migrateLegacyInstallIfNeeded(
            root: root,
            records: records,
            directories: directories,
            legacyIdentity: legacyIdentity
        )

        let migrated = directories.directory(for: .anonymous).appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        XCTAssertEqual(try Data(contentsOf: migrated), legacyBytes)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyLog.path(percentEncoded: false)),
            "the legacy log is moved, not duplicated"
        )
        XCTAssertEqual(try records.localUserID(for: .anonymous), legacyIdentity.localUserID)
        XCTAssertEqual(try records.deviceID(), legacyIdentity.deviceID)
    }

    func testAFreshInstallationIsNotTreatedAsAnUpgrade() throws {
        let records = ProfileRecordFile(directory: root)
        let directories = ProfileDirectoryProvider(root: root)

        try ProfileMigration.migrateLegacyInstallIfNeeded(
            root: root,
            records: records,
            directories: directories,
            legacyIdentity: nil
        )

        let anonymousLog = directories.directory(for: .anonymous).appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: anonymousLog.path(percentEncoded: false))
        )
    }

    func testMigrationIsIdempotent() throws {
        let legacyLog = root.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        try Data("{\"legacy\":true}\n".utf8).write(to: legacyLog, options: .atomic)
        let records = ProfileRecordFile(directory: root)
        let directories = ProfileDirectoryProvider(root: root)

        for _ in 0 ..< 2 {
            try ProfileMigration.migrateLegacyInstallIfNeeded(
                root: root,
                records: records,
                directories: directories,
                legacyIdentity: nil
            )
        }

        let migrated = directories.directory(for: .anonymous).appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        XCTAssertEqual(try Data(contentsOf: migrated), Data("{\"legacy\":true}\n".utf8))
    }
}
