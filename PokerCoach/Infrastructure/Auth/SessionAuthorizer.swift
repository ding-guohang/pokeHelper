import Foundation

/// Lets a `SessionAuthorizer` notify the account controller that the profile
/// has been locked. The handler is installed synchronously during controller
/// initialization, so a lock that happens on the very first request is never
/// missed.
final class SessionLockSignal: @unchecked Sendable {
    private let mutex = NSLock()
    private var handler: (@Sendable () async -> Void)?

    func onLock(_ handler: @escaping @Sendable () async -> Void) {
        mutex.withLock { self.handler = handler }
    }

    fileprivate func fire() async {
        // The handler is read under a scoped lock and invoked outside it, so no
        // lock is ever held across a suspension point.
        let handler = mutex.withLock { self.handler }
        await handler?()
    }
}

/// Attaches a live access token to authenticated requests and owns the token
/// rotation policy.
actor SessionAuthorizer {
    private let store: any CredentialStore
    private let api: any AccountAPI
    private let lockSignal: SessionLockSignal

    init(
        store: any CredentialStore,
        api: any AccountAPI,
        lockSignal: SessionLockSignal = SessionLockSignal()
    ) {
        self.store = store
        self.api = api
        self.lockSignal = lockSignal
    }

    func validAccessToken() async throws -> String {
        guard let active = try await store.loadActive() else {
            throw APIError.unauthorized
        }
        return active.accessToken
    }

    /// Runs `operation` with a bearer token, rotating once if the server
    /// rejects the token.
    ///
    /// Exactly one rotation and one replay are allowed. Retrying further would
    /// turn a revoked session into a stream of refresh attempts, and a refresh
    /// token replay is precisely what the server treats as a breach.
    func authorize<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T {
        let token = try await validAccessToken()
        do {
            return try await operation(token)
        } catch APIError.unauthorized {
            let rotated = try await rotate()
            do {
                return try await operation(rotated)
            } catch APIError.unauthorized {
                await lockProfile()
                throw APIError.unauthorized
            }
        }
    }

    private func rotate() async throws -> String {
        guard let active = try await store.loadActive() else {
            await lockProfile()
            throw APIError.unauthorized
        }

        let refreshed: StoredSession
        do {
            refreshed = try await api.refresh(refreshToken: active.refreshToken)
        } catch APIError.unauthorized {
            // The refresh token was replayed or revoked; the session is gone.
            await lockProfile()
            throw APIError.unauthorized
        }

        let carried = StoredSession(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            accessExpiresAt: refreshed.accessExpiresAt,
            refreshExpiresAt: refreshed.refreshExpiresAt,
            userID: refreshed.userID,
            sessionID: refreshed.sessionID,
            recentAuthAt: refreshed.recentAuthAt,
            email: refreshed.email ?? active.email
        )

        do {
            try await store.replaceActive(
                expectedRefreshToken: active.refreshToken,
                with: carried
            )
        } catch CredentialStoreError.staleRefreshToken {
            // Another rotation won the race; use whatever it installed.
            guard let current = try await store.loadActive() else {
                await lockProfile()
                throw APIError.unauthorized
            }
            return current.accessToken
        }
        return carried.accessToken
    }

    private func lockProfile() async {
        // Training history is never touched here: locking removes credentials
        // only, so the user keeps every local event.
        try? await store.clearActive()
        await lockSignal.fire()
    }
}
