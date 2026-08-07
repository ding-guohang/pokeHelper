import Foundation

/// A remote session as it is persisted on device. Tokens live only inside a
/// `SecureVault`; nothing here may be written to UserDefaults, a JSON fixture,
/// a log, or a crash report.
struct StoredSession: Equatable, Sendable, Codable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    let userID: UUID
    let sessionID: UUID
    let recentAuthAt: Date
    let email: String?

    init(
        accessToken: String,
        refreshToken: String,
        accessExpiresAt: Date,
        refreshExpiresAt: Date,
        userID: UUID,
        sessionID: UUID,
        recentAuthAt: Date,
        email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.userID = userID
        self.sessionID = sessionID
        self.recentAuthAt = recentAuthAt
        self.email = email
    }
}

/// A refresh token kept only so it can be revoked once the network returns.
/// It can never re-authenticate; the pending processor may only call logout.
struct PendingSessionRevocation: Equatable, Sendable, Codable {
    let refreshToken: String
    let userID: UUID
}

enum CredentialStoreError: Error, Equatable, CaseIterable {
    /// Secure storage could not be read or written. The app fails closed
    /// rather than falling back to insecure storage.
    case unavailable
    case staleRefreshToken
    case noActiveSession

    var recoverySuggestion: String {
        switch self {
        case .unavailable:
            "无法访问系统安全存储，账号功能暂不可用。训练记录仍然保存在本机，请稍后重试。"
        case .staleRefreshToken:
            "登录状态已在其他位置更新，请重新尝试当前操作。"
        case .noActiveSession:
            "当前没有已登录的账号，请先登录。"
        }
    }
}

protocol CredentialStore: Sendable {
    func loadActive() async throws -> StoredSession?
    func saveActive(_ session: StoredSession) async throws

    /// Installs `session` only if the stored refresh token still matches
    /// `expectedRefreshToken`. This makes token rotation a compare-and-replace,
    /// so a losing concurrent refresh cannot overwrite the winner's tokens.
    func replaceActive(expectedRefreshToken: String, with session: StoredSession) async throws

    func clearActive() async throws

    /// Atomically clears the active session and parks its refresh token for
    /// later revocation, in a single vault write.
    func moveRefreshToPendingRevocation() async throws

    func loadPendingRevocation() async throws -> PendingSessionRevocation?
    func clearPendingRevocation() async throws
}

/// Backing store for credential material. The production implementation is
/// Keychain-backed; tests inject an in-memory or deliberately failing vault.
protocol SecureVault: Sendable {
    func read() async throws -> Data?
    func write(_ data: Data) async throws
    func delete() async throws
}
