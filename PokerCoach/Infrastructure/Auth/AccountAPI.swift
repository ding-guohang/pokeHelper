import Foundation

/// Every account operation the app performs against the sync service.
protocol AccountAPI: Sendable {
    func register(email: String, password: String) async throws
    func verifyEmail(token: String) async throws
    func resendVerification(email: String) async throws
    func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession
    func requestPasswordReset(email: String) async throws
    func confirmPasswordReset(token: String, newPassword: String) async throws
    func signInWithApple(
        identityToken: String,
        nonce: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession
    func linkApple(identityToken: String, nonce: String, accessToken: String) async throws
    func refresh(refreshToken: String) async throws -> StoredSession
    func logOut(refreshToken: String) async throws

    func reauthenticate(
        _ proof: ReauthenticationRequest,
        accessToken: String
    ) async throws -> Date
    func devices(accessToken: String) async throws -> [DeviceSessionDTO]
    func revokeDevice(sessionID: UUID, accessToken: String) async throws
    func export(accessToken: String) async throws -> RemoteAccountExport
    func deleteAccount(accessToken: String) async throws
}

/// Proof of presence for a sensitive operation. Exactly one method is sent.
struct ReauthenticationRequest: Encodable, Sendable, Equatable {
    var password: String?
    var appleIdentityToken: String?
    var appleNonce: String?

    static func password(_ value: String) -> ReauthenticationRequest {
        ReauthenticationRequest(password: value)
    }

    static func apple(identityToken: String, nonce: String) -> ReauthenticationRequest {
        ReauthenticationRequest(appleIdentityToken: identityToken, appleNonce: nonce)
    }
}

/// The server's structured copy of the account. It deliberately carries no
/// credential material, so it is safe to write to disk as-is.
struct RemoteAccountExport: Decodable, Sendable, Equatable {
    struct Account: Decodable, Sendable, Equatable {
        let userID: UUID
        let createdAt: Date
    }

    let schemaVersion: Int
    let account: Account
    let devices: [DeviceSessionExport]
    let events: [AnyCodableValue]
}

struct DeviceSessionExport: Decodable, Sendable, Equatable {
    let displayName: String
    let platform: String
    let appVersion: String
}

/// Preserves an arbitrary JSON value without interpreting it, so exported
/// events keep exactly the shape the server stored.
struct AnyCodableValue: Codable, Sendable, Equatable {
    let raw: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONAny.self)
        raw = try JSONEncoder().encode(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONDecoder().decode(JSONAny.self, from: raw))
    }
}

/// Minimal any-JSON representation used only to round-trip exported events.
enum JSONAny: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONAny])
    case object([String: JSONAny])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONAny].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONAny].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// `AccountAPI` over the shared JSON transport.
struct RemoteAccountAPI: AccountAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func register(email: String, password: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/register",
            body: EmailPasswordBody(email: email, password: password)
        )
    }

    /// Verification only confirms the address; the server answers 204 and the
    /// user signs in afterwards. Decoding a session here would fail on the
    /// empty body.
    func verifyEmail(token: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/verify-email",
            body: TokenBody(token: token)
        )
    }

    func resendVerification(email: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/resend-verification",
            body: EmailBody(email: email)
        )
    }

    func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        let tokens: SessionTokensDTO = try await client.send(
            "POST",
            "v1/auth/login",
            body: LoginBody(email: email, password: password, device: device)
        )
        return tokens.session(email: email)
    }

    func requestPasswordReset(email: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/password-reset/request",
            body: EmailBody(email: email)
        )
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/password-reset/confirm",
            body: ResetConfirmBody(token: token, password: newPassword)
        )
    }

    func signInWithApple(
        identityToken: String,
        nonce: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        let tokens: SessionTokensDTO = try await client.send(
            "POST",
            "v1/auth/apple",
            body: AppleSignInBody(
                identityToken: identityToken,
                nonce: nonce,
                device: device
            )
        )
        return tokens.session(email: nil)
    }

    func linkApple(identityToken: String, nonce: String, accessToken: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/apple/link",
            body: AppleLinkBody(identityToken: identityToken, nonce: nonce),
            accessToken: accessToken
        )
    }

    func refresh(refreshToken: String) async throws -> StoredSession {
        let tokens: SessionTokensDTO = try await client.send(
            "POST",
            "v1/auth/refresh",
            body: RefreshBody(refreshToken: refreshToken)
        )
        return tokens.session(email: nil)
    }

    func logOut(refreshToken: String) async throws {
        try await client.sendWithoutResponse(
            "POST",
            "v1/auth/logout",
            body: RefreshBody(refreshToken: refreshToken)
        )
    }

    func reauthenticate(
        _ proof: ReauthenticationRequest,
        accessToken: String
    ) async throws -> Date {
        let response: ReauthResponse = try await client.send(
            "POST",
            "v1/auth/reauth",
            body: proof,
            accessToken: accessToken
        )
        return response.recentAuthAt
    }

    func devices(accessToken: String) async throws -> [DeviceSessionDTO] {
        let response: DeviceListResponse = try await client.send(
            "GET",
            "v1/sessions",
            body: Optional<APIClient.Empty>.none,
            accessToken: accessToken
        )
        return response.devices
    }

    func revokeDevice(sessionID: UUID, accessToken: String) async throws {
        try await client.sendWithoutResponse(
            "DELETE",
            "v1/sessions/\(sessionID.uuidString.lowercased())",
            body: Optional<APIClient.Empty>.none,
            accessToken: accessToken
        )
    }

    func export(accessToken: String) async throws -> RemoteAccountExport {
        try await client.send(
            "GET",
            "v1/account/export",
            body: Optional<APIClient.Empty>.none,
            accessToken: accessToken
        )
    }

    func deleteAccount(accessToken: String) async throws {
        try await client.sendWithoutResponse(
            "DELETE",
            "v1/account",
            body: Optional<APIClient.Empty>.none,
            accessToken: accessToken
        )
    }

    private struct ReauthResponse: Decodable, Sendable {
        let recentAuthAt: Date
    }

    private struct DeviceListResponse: Decodable, Sendable {
        let devices: [DeviceSessionDTO]
    }

    private struct EmailBody: Encodable, Sendable {
        let email: String
    }

    private struct EmailPasswordBody: Encodable, Sendable {
        let email: String
        let password: String
    }

    private struct TokenBody: Encodable, Sendable {
        let token: String
    }

    private struct ResetConfirmBody: Encodable, Sendable {
        let token: String
        let password: String
    }

    private struct LoginBody: Encodable, Sendable {
        let email: String
        let password: String
        let device: DeviceDescriptor
    }

    private struct AppleSignInBody: Encodable, Sendable {
        let identityToken: String
        let nonce: String
        let device: DeviceDescriptor
    }

    private struct AppleLinkBody: Encodable, Sendable {
        let identityToken: String
        let nonce: String
    }

    private struct RefreshBody: Encodable, Sendable {
        let refreshToken: String
    }
}
