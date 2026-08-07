import Foundation
import XCTest
@testable import PokerCoach

final class ProfileAssociationStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "ProfileAssociations-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // The device ID identifies the installation, so every profile on this
    // device reports the same one and reinstalling is what changes it.
    func testDeviceIDIsStableAcrossProfilesAndReopens() async throws {
        let store = ProfileAssociationStore(directory: root)

        let first = try await store.deviceID()
        let second = try await store.deviceID()
        let reopened = try await ProfileAssociationStore(directory: root).deviceID()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, reopened)
    }

    // The local user ID identifies the profile, so two profiles must never
    // share one, or their events would be indistinguishable after a sync.
    func testLocalUserIDIsStablePerProfileAndDistinctBetweenProfiles() async throws {
        let store = ProfileAssociationStore(directory: root)
        let anonymous = ProfileID.anonymous
        let remote = ProfileID(remoteUserID: UUID())

        let anonymousID = try await store.localUserID(for: anonymous)
        let remoteID = try await store.localUserID(for: remote)

        let reread = try await store.localUserID(for: anonymous)
        XCTAssertEqual(reread, anonymousID)
        XCTAssertNotEqual(anonymousID, remoteID)
    }

    func testAnonymousHistoryCanBeClaimedOnlyOnce() async throws {
        let store = ProfileAssociationStore(directory: root)
        let first = UUID()
        let second = UUID()

        let claimed = try await store.claimAnonymous(by: first)
        XCTAssertTrue(claimed)

        let secondAttempt = try await store.claimAnonymous(by: second)
        XCTAssertFalse(
            secondAttempt,
            "anonymous history belongs to whoever claimed it first"
        )
        let claimant = try await store.anonymousClaimant()
        XCTAssertEqual(claimant, first)
    }

    // Claiming carries the anonymous local user ID onto the remote profile, so
    // events written before and after the claim keep one consistent identity.
    func testClaimingCarriesTheAnonymousLocalUserIDToTheRemoteProfile() async throws {
        let store = ProfileAssociationStore(directory: root)
        let anonymousLocalID = try await store.localUserID(for: .anonymous)
        let remoteUserID = UUID()

        _ = try await store.claimAnonymous(by: remoteUserID)

        let claimedLocalID = try await store.localUserID(
            for: ProfileID(remoteUserID: remoteUserID)
        )
        XCTAssertEqual(claimedLocalID, anonymousLocalID)
    }

    func testAssociationsSurviveAReopen() async throws {
        let store = ProfileAssociationStore(directory: root)
        let remoteUserID = UUID()
        let localID = try await store.localUserID(for: ProfileID(remoteUserID: remoteUserID))

        let reopened = ProfileAssociationStore(directory: root)

        let reopenedID = try await reopened.localUserID(
            for: ProfileID(remoteUserID: remoteUserID)
        )
        XCTAssertEqual(reopenedID, localID)
    }
}
