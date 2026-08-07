import Foundation

/// Turns account state changes into profile switches.
///
/// Keeping this separate from `AccountSessionController` means the account
/// layer never needs to know how local data is laid out, and the profile layer
/// never needs to know how authentication works.
@MainActor
final class ProfileLifecycleController {
    private let profiles: ActiveProfileController
    private let onProfileChanged: @MainActor (ActiveProfile) -> Void

    private(set) var active: ActiveProfile?

    init(
        profiles: ActiveProfileController,
        onProfileChanged: @escaping @MainActor (ActiveProfile) -> Void = { _ in }
    ) {
        self.profiles = profiles
        self.onProfileChanged = onProfileChanged
    }

    func start() async {
        await apply { try await profiles.current() }
    }

    /// Called when a user signs in.
    ///
    /// The first account to sign in on a fresh installation adopts the
    /// anonymous history; later accounts get their own empty profile.
    func signedIn(remoteUserID: UUID) async {
        await apply { try await profiles.claimCurrent(remoteUserID: remoteUserID) }
    }

    func signedOut() async {
        await apply {
            try await profiles.lockCurrent()
            return try await profiles.current()
        }
    }

    private func apply(_ operation: () async throws -> ActiveProfile) async {
        guard let profile = try? await operation() else {
            return
        }
        active = profile
        onProfileChanged(profile)
    }
}
