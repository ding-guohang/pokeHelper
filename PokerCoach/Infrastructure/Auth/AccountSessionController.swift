import Foundation
import Observation

struct AccountSummary: Equatable, Sendable {
    let userID: UUID
    let email: String?
}

enum AccountSessionState: Equatable, Sendable {
    /// The M1A experience: full offline training with no account at all.
    case anonymous
    case awaitingVerification(email: String)
    case authenticated(AccountSummary)
    /// Credentials were rejected and removed. Local training history is intact.
    case locked
}

struct AccountFailure: Equatable, Sendable {
    let message: String
}

/// Bridges the account use cases to SwiftUI.
///
/// Every operation is failable but non-throwing: a failure becomes recoverable
/// Chinese text in `failure` and never removes the user's ability to train.
@MainActor
@Observable
final class AccountSessionController {
    private(set) var state: AccountSessionState = .anonymous
    private(set) var failure: AccountFailure?
    private(set) var needsReauthentication = false
    /// Set once an address is confirmed, so the sign-in form can prefill it.
    private(set) var verifiedEmail: String?
    private(set) var isBusy = false

    @ObservationIgnored
    let authorizer: SessionAuthorizer

    @ObservationIgnored
    fileprivate let api: any AccountAPI
    @ObservationIgnored
    fileprivate let credentials: any CredentialStore
    @ObservationIgnored
    fileprivate let apple: any AppleAuthorizationClient
    @ObservationIgnored
    private let policy: PasswordPolicy
    @ObservationIgnored
    private let device: DeviceDescriptor

    /// The profile whose data an export bundles. Set by the profile lifecycle.
    @ObservationIgnored
    var activeProfile: ActiveProfile?

    /// Applies the local half of an account deletion. Injected so the account
    /// layer never needs to know how profiles are laid out on disk.
    @ObservationIgnored
    var onAccountDeleted: (@MainActor (UUID, LocalDeletionChoice) async -> Void)?

    init(
        api: any AccountAPI,
        credentials: any CredentialStore,
        apple: any AppleAuthorizationClient,
        policy: PasswordPolicy,
        device: DeviceDescriptor
    ) {
        self.api = api
        self.credentials = credentials
        self.apple = apple
        self.policy = policy
        self.device = device

        let signal = SessionLockSignal()
        authorizer = SessionAuthorizer(store: credentials, api: api, lockSignal: signal)
        signal.onLock { [weak self] in
            await MainActor.run { self?.lockProfile() }
        }
    }

    func restore() async {
        failure = nil
        do {
            guard let active = try await credentials.loadActive() else {
                state = .anonymous
                return
            }
            state = .authenticated(summary(for: active))
        } catch {
            // Secure storage is unreadable. Surface it, but keep the app usable
            // anonymously so training is never blocked by an account problem.
            state = .anonymous
            report(error)
        }
    }

    func register(email: String, password: String) async {
        await run {
            let validated = try self.policy.validate(password)
            try await self.api.register(email: email, password: validated)
            self.state = .awaitingVerification(email: email)
        }
    }

    /// Confirms the address. The server issues no session here, so the user
    /// lands back on sign-in with a verified account.
    func verifyEmail(token: String) async {
        await run {
            // Read before changing state: pendingEmail is derived from it.
            let confirmed = self.pendingEmail
            try await self.api.verifyEmail(token: token)
            self.verifiedEmail = confirmed
            self.state = .anonymous
        }
    }

    func resendVerification() async {
        guard case let .awaitingVerification(email) = state else {
            failure = AccountFailure(message: "当前没有等待验证的邮箱。")
            return
        }
        await run {
            try await self.api.resendVerification(email: email)
        }
    }

    func login(email: String, password: String) async {
        await run {
            let validated = try self.policy.validate(password)
            let session = try await self.api.login(
                email: email,
                password: validated,
                device: self.device
            )
            try await self.adopt(session, email: email)
        }
    }

    func requestPasswordReset(email: String) async {
        await run {
            try await self.api.requestPasswordReset(email: email)
        }
    }

    func confirmPasswordReset(token: String, newPassword: String) async {
        await run {
            let validated = try self.policy.validate(newPassword)
            try await self.api.confirmPasswordReset(token: token, newPassword: validated)
        }
    }

    func signInWithApple() async {
        await run {
            let credential = try await self.apple.requestCredential()
            let session = try await self.api.signInWithApple(
                identityToken: credential.identityToken,
                nonce: credential.nonce,
                device: self.device
            )
            try await self.adopt(session, email: session.email)
        }
    }

    func linkApple() async {
        guard case .authenticated = state else {
            failure = AccountFailure(message: "请先登录，再绑定 Apple 账号。")
            return
        }
        await run {
            let credential = try await self.apple.requestCredential()
            try await self.authorizer.authorize { accessToken in
                try await self.api.linkApple(
                    identityToken: credential.identityToken,
                    nonce: credential.nonce,
                    accessToken: accessToken
                )
            }
        }
    }

    func reauthenticate(_ proof: ReauthenticationProof) async {
        await run {
            switch proof {
            case let .password(email, password):
                let validated = try self.policy.validate(password)
                let session = try await self.api.login(
                    email: email,
                    password: validated,
                    device: self.device
                )
                try await self.adopt(session, email: email)
            case .apple:
                let credential = try await self.apple.requestCredential()
                let session = try await self.api.signInWithApple(
                    identityToken: credential.identityToken,
                    nonce: credential.nonce,
                    device: self.device
                )
                try await self.adopt(session, email: session.email)
            }
            self.needsReauthentication = false
        }
    }

    /// Signs out. If the network is unavailable the refresh token is parked for
    /// later revocation, so the session still ends immediately on this device.
    ///
    /// Secure-storage failure is surfaced rather than swallowed. Reporting a
    /// completed sign-out while the credential is still readable would let the
    /// next launch silently restore the session — the exact situation a user
    /// handing over their phone believes they have prevented.
    func logOut() async {
        failure = nil
        let active: StoredSession?
        do {
            active = try await credentials.loadActive()
        } catch {
            report(error)
            return
        }

        guard let active else {
            needsReauthentication = false
            state = .anonymous
            return
        }

        do {
            try await api.logOut(refreshToken: active.refreshToken)
            try await credentials.clearActive()
        } catch let error as CredentialStoreError {
            report(error)
            return
        } catch {
            // The server is unreachable. Park the token so it can still be
            // revoked later, and fail loudly if even that cannot be written.
            do {
                try await credentials.moveRefreshToPendingRevocation()
            } catch {
                report(error)
                return
            }
        }

        needsReauthentication = false
        state = .anonymous
    }

    /// Revokes a token parked by an offline logout. Safe to call repeatedly.
    func processPendingRevocation() async {
        guard let pending = try? await credentials.loadPendingRevocation() else {
            return
        }
        do {
            try await api.logOut(refreshToken: pending.refreshToken)
            try await credentials.clearPendingRevocation()
        } catch APIError.unauthorized {
            // Already revoked or expired server-side; the slot can go.
            try? await credentials.clearPendingRevocation()
        } catch {
            // Still offline. Keep the token parked and retry later.
        }
    }

    private var pendingEmail: String? {
        if case let .awaitingVerification(email) = state {
            return email
        }
        return nil
    }

    private func adopt(_ session: StoredSession, email: String?) async throws {
        let resolved = StoredSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            accessExpiresAt: session.accessExpiresAt,
            refreshExpiresAt: session.refreshExpiresAt,
            userID: session.userID,
            sessionID: session.sessionID,
            recentAuthAt: session.recentAuthAt,
            email: session.email ?? email
        )
        try await credentials.saveActive(resolved)
        state = .authenticated(summary(for: resolved))
    }

    private func summary(for session: StoredSession) -> AccountSummary {
        AccountSummary(userID: session.userID, email: session.email)
    }

    private func lockProfile() {
        state = .locked
        failure = AccountFailure(
            message: "登录状态已失效，请重新登录。本机训练记录未受影响。"
        )
    }

    fileprivate func run(_ operation: @escaping () async throws -> Void) async {
        failure = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            report(error)
        }
    }

    fileprivate func report(_ error: Error) {
        if case APIError.reauthenticationRequired = error {
            needsReauthentication = true
        }
        failure = AccountFailure(message: Self.message(for: error))
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let error as APIError:
            error.recoverySuggestion
        case let error as CredentialStoreError:
            error.recoverySuggestion
        case let error as PasswordPolicy.Failure:
            error.recoverySuggestion
        case let error as AppleAuthorizationError:
            error.recoverySuggestion
        default:
            "操作未能完成，请稍后重试。"
        }
    }
}

enum ReauthenticationProof: Sendable, Equatable {
    case password(email: String, password: String)
    case apple
}

// MARK: - Device sessions and data rights

extension AccountSessionController {
    /// Lists the account's own device sessions.
    func loadDevices() async -> [DeviceSessionDTO] {
        guard case .authenticated = state else {
            return []
        }
        do {
            return try await authorizer.authorize { accessToken in
                try await self.api.devices(accessToken: accessToken)
            }
        } catch {
            report(error)
            return []
        }
    }

    /// Revokes another device. The server refuses a session the caller does
    /// not own, so nothing here needs to re-check ownership.
    func revokeDevice(sessionID: UUID) async {
        await run {
            try await self.authorizer.authorize { accessToken in
                try await self.api.revokeDevice(sessionID: sessionID, accessToken: accessToken)
            }
        }
    }

    /// Proves presence with Apple, refreshing the current session rather than
    /// starting a new one.
    func reauthenticateWithApple() async {
        await run {
            let credential = try await self.apple.requestCredential()
            _ = try await self.authorizer.authorize { accessToken in
                try await self.api.reauthenticate(
                    .apple(
                        identityToken: credential.identityToken,
                        nonce: credential.nonce
                    ),
                    accessToken: accessToken
                )
            }
            self.needsReauthentication = false
        }
    }

    /// Proves presence so a sensitive operation can proceed.
    func reauthenticate(_ proof: ReauthenticationRequest) async {
        await run {
            _ = try await self.authorizer.authorize { accessToken in
                try await self.api.reauthenticate(proof, accessToken: accessToken)
            }
            self.needsReauthentication = false
        }
    }

    /// Downloads the account document and writes the take-away bundle.
    func exportAccount(to destination: URL) async -> URL? {
        guard let profile = activeProfile else {
            failure = AccountFailure(message: "本机档案尚未就绪，请稍后重试。")
            return nil
        }

        var built: URL?
        await run {
            let remote = try await self.authorizer.authorize { accessToken in
                try await self.api.export(accessToken: accessToken)
            }
            built = try AccountExportBuilder().build(
                remote: remote,
                profile: profile,
                destination: destination
            )
        }
        return built
    }

    /// Deletes the remote account, then applies the user's choice for the
    /// copy cached on this device.
    ///
    /// The remote deletion happens first. If it fails there is nothing to
    /// reconcile locally, whereas clearing local data first would destroy the
    /// user's hands for a deletion that never happened.
    func deleteAccount(localChoice: LocalDeletionChoice) async {
        guard case let .authenticated(summary) = state else {
            failure = AccountFailure(message: "请先登录，再删除账号。")
            return
        }

        await run {
            try await self.authorizer.authorize { accessToken in
                try await self.api.deleteAccount(accessToken: accessToken)
            }
            try? await self.credentials.clearActive()
            try? await self.credentials.clearPendingRevocation()
            await self.onAccountDeleted?(summary.userID, localChoice)
            self.state = .anonymous
        }
    }
}
