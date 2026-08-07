import Foundation
import XCTest
@testable import PokerCoach

final class CredentialStoreTests: XCTestCase {
    private let session = StoredSession.fixture()

    func testSavedSessionRoundTrips() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())

        try await store.saveActive(session)
        let loaded = try await store.loadActive()

        XCTAssertEqual(loaded, session)
    }

    func testLoadingWithoutASavedSessionReturnsNil() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())

        let loaded = try await store.loadActive()

        XCTAssertNil(loaded)
    }

    func testClearingRemovesTheSession() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())
        try await store.saveActive(session)

        try await store.clearActive()

        let loaded = try await store.loadActive()
        XCTAssertNil(loaded)
    }

    // Rotation is a compare-and-replace: two concurrent refreshes must not both
    // install their result, or one would silently overwrite the other's token.
    func testReplaceActiveSucceedsOnlyForTheExpectedRefreshToken() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())
        try await store.saveActive(session)
        let rotated = StoredSession.fixture(refreshToken: "rotated-refresh")

        try await store.replaceActive(
            expectedRefreshToken: session.refreshToken,
            with: rotated
        )
        let afterFirst = try await store.loadActive()
        XCTAssertEqual(afterFirst, rotated)

        do {
            try await store.replaceActive(
                expectedRefreshToken: session.refreshToken,
                with: StoredSession.fixture(refreshToken: "loser")
            )
            XCTFail("Replacing against a stale refresh token must fail")
        } catch {
            XCTAssertEqual(error as? CredentialStoreError, .staleRefreshToken)
        }

        let afterStale = try await store.loadActive()
        XCTAssertEqual(afterStale, rotated)
    }

    func testReplaceActiveWithoutASessionFails() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())

        do {
            try await store.replaceActive(expectedRefreshToken: "any", with: session)
            XCTFail("Replacing without an active session must fail")
        } catch {
            XCTAssertEqual(error as? CredentialStoreError, .noActiveSession)
        }
    }

    // Logging out offline moves the refresh token to a pending slot so it can
    // be revoked later. The move must clear the active slot in the same write,
    // otherwise a crash between two writes could leave the token usable.
    func testMovingRefreshToPendingRevocationClearsTheActiveSessionAtomically() async throws {
        let vault = InMemoryVault()
        let store = KeychainCredentialStore(vault: vault)
        try await store.saveActive(session)
        let writesBefore = await vault.writeCount

        try await store.moveRefreshToPendingRevocation()

        let cleared = try await store.loadActive()
        XCTAssertNil(cleared)
        let pending = try await store.loadPendingRevocation()
        XCTAssertEqual(pending?.refreshToken, session.refreshToken)
        XCTAssertEqual(pending?.userID, session.userID)

        let writes = await vault.writeCount - writesBefore
        XCTAssertEqual(writes, 1, "the move must be a single vault write")
    }

    func testClearingPendingRevocationRemovesIt() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())
        try await store.saveActive(session)
        try await store.moveRefreshToPendingRevocation()

        try await store.clearPendingRevocation()

        let pending = try await store.loadPendingRevocation()
        XCTAssertNil(pending)
    }

    func testMovingWithoutAnActiveSessionIsANoOp() async throws {
        let store = KeychainCredentialStore(vault: InMemoryVault())

        try await store.moveRefreshToPendingRevocation()

        let pending = try await store.loadPendingRevocation()
        XCTAssertNil(pending)
    }

    // A Keychain failure must never downgrade to insecure storage; it fails
    // closed with a recoverable Chinese error instead.
    func testVaultFailuresFailClosed() async throws {
        let store = KeychainCredentialStore(vault: FailingVault())

        do {
            _ = try await store.loadActive()
            XCTFail("A failing vault must not report a usable session")
        } catch {
            XCTAssertEqual(error as? CredentialStoreError, .unavailable)
        }

        do {
            try await store.saveActive(session)
            XCTFail("A failing vault must not silently accept a save")
        } catch {
            XCTAssertEqual(error as? CredentialStoreError, .unavailable)
        }
    }

    func testCredentialErrorsCarryChineseRecoveryText() {
        for failure in CredentialStoreError.allCases {
            XCTAssertTrue(
                failure.recoverySuggestion.contains(where: \.isChineseCharacter),
                "\(failure) must be described in Chinese"
            )
        }
    }

    // Tokens live only in the Keychain vault. Nothing may leak into
    // UserDefaults, which is unencrypted and backed up in the clear.
    func testTokensNeverReachUserDefaults() async throws {
        let suiteName = "PokerCoachTests.Credentials.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let store = KeychainCredentialStore(vault: InMemoryVault())
        try await store.saveActive(session)

        let contents = defaults.dictionaryRepresentation()
        let serialized = contents.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        XCTAssertFalse(serialized.contains(session.accessToken))
        XCTAssertFalse(serialized.contains(session.refreshToken))
    }
}

extension StoredSession {
    static func fixture(
        accessToken: String = "access-token-value",
        refreshToken: String = "refresh-token-value",
        email: String? = "player@example.test"
    ) -> StoredSession {
        StoredSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: Date(timeIntervalSince1970: 1_786_100_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_788_700_000),
            userID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            sessionID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            recentAuthAt: Date(timeIntervalSince1970: 1_786_099_000),
            email: email
        )
    }
}

actor InMemoryVault: SecureVault {
    private var storage: Data?
    private(set) var writeCount = 0

    func read() throws -> Data? {
        storage
    }

    func write(_ data: Data) throws {
        writeCount += 1
        storage = data
    }

    func delete() throws {
        writeCount += 1
        storage = nil
    }
}

struct FailingVault: SecureVault {
    func read() throws -> Data? {
        throw CredentialStoreError.unavailable
    }

    func write(_ data: Data) throws {
        throw CredentialStoreError.unavailable
    }

    func delete() throws {
        throw CredentialStoreError.unavailable
    }
}
