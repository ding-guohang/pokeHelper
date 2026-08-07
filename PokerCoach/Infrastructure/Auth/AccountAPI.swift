import Foundation

/// Every account operation the app performs against the sync service.
protocol AccountAPI: Sendable {
    func register(email: String, password: String) async throws
    func verifyEmail(token: String) async throws -> StoredSession
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

    func verifyEmail(token: String) async throws -> StoredSession {
        let tokens: SessionTokensDTO = try await client.send(
            "POST",
            "v1/auth/verify-email",
            body: TokenBody(token: token)
        )
        return tokens.session(email: nil)
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
