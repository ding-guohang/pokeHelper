import Foundation

/// Revokes a refresh token that was parked by an offline logout.
///
/// The pending token can only be used to revoke itself. It never restores a
/// session, so a device that logged out stays logged out even though its token
/// is still on disk waiting for the network.
actor PendingRevocationProcessor {
    /// Why the processor ran. Kept so a triggering path can be traced without
    /// changing behaviour.
    enum Trigger: String, Sendable, Equatable {
        case launch
        case foreground
        case networkRestored
    }

    private let credentials: any CredentialStore
    private let api: any AccountAPI
    private var isRunning = false

    init(credentials: any CredentialStore, api: any AccountAPI) {
        self.credentials = credentials
        self.api = api
    }

    /// Attempts one revocation. Safe to call from every trigger and safe to
    /// call repeatedly; overlapping runs are collapsed.
    func process(trigger: Trigger = .launch) async {
        guard !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }

        guard
            let pending = try? await credentials.loadPendingRevocation(),
            !pending.refreshToken.isEmpty
        else {
            return
        }

        do {
            try await api.logOut(refreshToken: pending.refreshToken)
            try await credentials.clearPendingRevocation()
        } catch APIError.unauthorized {
            // Already revoked or expired server-side: the slot has done its job.
            try? await credentials.clearPendingRevocation()
        } catch {
            // Still unreachable. Keep the token parked and try again on the
            // next trigger rather than dropping a revocation on the floor.
        }
    }
}
