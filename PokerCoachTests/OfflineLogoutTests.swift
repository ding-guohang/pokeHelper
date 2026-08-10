import Foundation
import XCTest
@testable import PokerCoach

/// Signing out must take effect on this device immediately, even with no
/// network. The refresh token is parked so the server can be told later.
@MainActor
final class OfflineLogoutTests: XCTestCase {
    func testOfflineLogoutEndsTheSessionAndParksTheToken() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        await harness.controller.restore()
        harness.api.offline = true

        await harness.controller.logOut()

        XCTAssertEqual(harness.controller.state, .anonymous)
        let active = try await harness.credentials.loadActive()
        XCTAssertNil(active, "the device must be signed out regardless of the network")
        let pending = try await harness.credentials.loadPendingRevocation()
        XCTAssertEqual(pending?.refreshToken, StoredSession.fixture().refreshToken)
    }

    // A parked token must not be able to restore a session; it exists only to
    // be revoked.
    func testAParkedTokenDoesNotRestoreASession() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        harness.api.offline = true
        await harness.controller.logOut()

        await harness.controller.restore()

        XCTAssertEqual(harness.controller.state, .anonymous)
    }

    func testTheProcessorRevokesTheParkedTokenWhenTheNetworkReturns() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        harness.api.offline = true
        await harness.controller.logOut()
        harness.api.offline = false

        await harness.processor.process(trigger: .networkRestored)

        XCTAssertEqual(harness.api.revokedTokens, [StoredSession.fixture().refreshToken])
        let pending = try await harness.credentials.loadPendingRevocation()
        XCTAssertNil(pending, "a revoked token must be cleared")
    }

    func testTheProcessorKeepsTheTokenWhileStillOffline() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        harness.api.offline = true
        await harness.controller.logOut()

        await harness.processor.process(trigger: .launch)

        let pending = try await harness.credentials.loadPendingRevocation()
        XCTAssertNotNil(pending, "an unreachable server must not drop the revocation")
    }

    // Already revoked or expired server-side is a success from this device's
    // point of view: there is nothing left to revoke.
    func testAnAlreadyRevokedTokenClearsTheSlot() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        harness.api.offline = true
        await harness.controller.logOut()
        harness.api.offline = false
        harness.api.rejectAsUnauthorized = true

        await harness.processor.process(trigger: .foreground)

        let pending = try await harness.credentials.loadPendingRevocation()
        XCTAssertNil(pending)
    }

    func testProcessingWithNothingParkedDoesNothing() async throws {
        let harness = Harness()

        await harness.processor.process(trigger: .launch)

        XCTAssertTrue(harness.api.revokedTokens.isEmpty)
    }

    func testEveryTriggerDrivesTheSameProcessing() async throws {
        for trigger in [
            PendingRevocationProcessor.Trigger.launch,
            .foreground,
            .networkRestored,
        ] {
            let harness = Harness()
            try await harness.credentials.saveActive(.fixture())
            harness.api.offline = true
            await harness.controller.logOut()
            harness.api.offline = false

            await harness.processor.process(trigger: trigger)

            XCTAssertEqual(
                harness.api.revokedTokens.count,
                1,
                "\(trigger) must revoke the parked token"
            )
        }
    }
}

@MainActor
private struct Harness {
    let api = LogoutAPIDouble()
    let credentials: CredentialStore
    let controller: AccountSessionController
    let processor: PendingRevocationProcessor

    init() {
        let store = KeychainCredentialStore(vault: InMemoryVault())
        credentials = store
        controller = AccountSessionController(
            api: api,
            credentials: store,
            apple: LogoutAppleClient(),
            policy: PasswordPolicy(blocklist: []),
            device: DeviceDescriptor(
                deviceID: UUID(),
                displayName: "iPhone",
                platform: "iOS",
                appVersion: "1.0.0"
            )
        )
        processor = PendingRevocationProcessor(credentials: store, api: api)
    }
}

private final class LogoutAPIDouble: StubAccountAPI, @unchecked Sendable {
    var offline = false
    var rejectAsUnauthorized = false
    private(set) var revokedTokens: [String] = []

    override func logOut(refreshToken: String) async throws {
        if offline {
            throw APIError.offline
        }
        if rejectAsUnauthorized {
            throw APIError.unauthorized
        }
        revokedTokens.append(refreshToken)
    }
}

private struct LogoutAppleClient: AppleAuthorizationClient {
    func requestCredential() async throws -> AppleCredential {
        AppleCredential(identityToken: "token", nonce: "nonce")
    }
}

/// A sign-out that cannot clear the credential must say so.
@MainActor
final class LogOutFailureTests: XCTestCase {
    func testLogOutSurfacesASecureStorageFailureInsteadOfReportingSuccess() async throws {
        let store = BrittleCredentialStore()
        try await store.saveActive(.fixture())
        let controller = AccountSessionController(
            api: LogOutFailureAPI(),
            credentials: store,
            apple: LogOutFailureAppleClient(),
            policy: PasswordPolicy(blocklist: []),
            device: DeviceDescriptor(
                deviceID: UUID(),
                displayName: "iPhone",
                platform: "iOS",
                appVersion: "1.0.0"
            )
        )
        await controller.restore()
        XCTAssertNotEqual(controller.state, .anonymous, "precondition: signed in")

        store.failClearAndMove = true
        await controller.logOut()

        XCTAssertNotNil(
            controller.failure,
            "a sign-out that could not clear the credential must not look successful"
        )
        XCTAssertNotEqual(
            controller.state,
            .anonymous,
            "claiming anonymous here would let the next launch restore the session"
        )

        // The credential really is still there, which is why the claim matters.
        let stillStored = try await store.loadActive()
        XCTAssertNotNil(stillStored)
    }
}

private final class LogOutFailureAPI: StubAccountAPI, @unchecked Sendable {}

/// Reads succeed; clearing and parking fail. This is the Keychain-write-denied
/// case, where a naive implementation reports a completed sign-out.
private final class BrittleCredentialStore: CredentialStore, @unchecked Sendable {
    var failClearAndMove = false

    private let backing = KeychainCredentialStore(vault: InMemoryVault())

    func loadActive() async throws -> StoredSession? { try await backing.loadActive() }
    func saveActive(_ session: StoredSession) async throws {
        try await backing.saveActive(session)
    }
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws {
        try await backing.replaceActive(expectedRefreshToken: expectedRefreshToken, with: session)
    }
    func clearActive() async throws {
        if failClearAndMove { throw CredentialStoreError.unavailable }
        try await backing.clearActive()
    }
    func moveRefreshToPendingRevocation() async throws {
        if failClearAndMove { throw CredentialStoreError.unavailable }
        try await backing.moveRefreshToPendingRevocation()
    }
    func loadPendingRevocation() async throws -> PendingSessionRevocation? {
        try await backing.loadPendingRevocation()
    }
    func clearPendingRevocation() async throws { try await backing.clearPendingRevocation() }
}

private struct LogOutFailureAppleClient: AppleAuthorizationClient {
    func requestCredential() async throws -> AppleCredential {
        AppleCredential(identityToken: "token", nonce: "nonce")
    }
}
