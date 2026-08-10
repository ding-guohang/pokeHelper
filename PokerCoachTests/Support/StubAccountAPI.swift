import Foundation
@testable import PokerCoach

/// Base test double for `AccountAPI`.
///
/// Every method has a neutral implementation so a test only overrides what it
/// exercises. Centralizing them means adding an operation to the protocol
/// touches this one file instead of every double.
class StubAccountAPI: AccountAPI, @unchecked Sendable {
    func register(email: String, password: String) async throws {}

    func verifyEmail(token: String) async throws -> StoredSession { .fixture() }

    func resendVerification(email: String) async throws {}

    func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession { .fixture() }

    func requestPasswordReset(email: String) async throws {}

    func confirmPasswordReset(token: String, newPassword: String) async throws {}

    func signInWithApple(
        identityToken: String,
        nonce: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession { .fixture() }

    func linkApple(identityToken: String, nonce: String, accessToken: String) async throws {}

    func refresh(refreshToken: String) async throws -> StoredSession { .fixture() }

    func logOut(refreshToken: String) async throws {}

    func reauthenticate(
        _ proof: ReauthenticationRequest,
        accessToken: String
    ) async throws -> Date {
        Date(timeIntervalSince1970: 1_786_300_000)
    }

    func devices(accessToken: String) async throws -> [DeviceSessionDTO] { [] }

    func revokeDevice(sessionID: UUID, accessToken: String) async throws {}

    func export(accessToken: String) async throws -> RemoteAccountExport {
        RemoteAccountExport(
            schemaVersion: 1,
            account: RemoteAccountExport.Account(
                userID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                createdAt: Date(timeIntervalSince1970: 1_785_000_000)
            ),
            devices: [],
            events: []
        )
    }

    func deleteAccount(accessToken: String) async throws {}
}
