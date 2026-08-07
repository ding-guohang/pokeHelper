import Foundation

/// Owns which profile the app is currently reading and writing.
actor ActiveProfileController {
    private let associations: ProfileAssociationStore
    private let directories: ProfileDirectoryProvider
    private var activeID: ProfileID = .anonymous

    init(associations: ProfileAssociationStore, directories: ProfileDirectoryProvider) {
        self.associations = associations
        self.directories = directories
    }

    func current() async throws -> ActiveProfile {
        try await profile(for: activeID)
    }

    /// Adopts the anonymous history into a signed-in account.
    ///
    /// The directory is renamed rather than copied, so the append-only event
    /// log keeps its exact bytes, event IDs, and local user ID. Rewriting the
    /// log would break event identity and any idempotent upload that already
    /// referenced it.
    func claimCurrent(remoteUserID: UUID) async throws -> ActiveProfile {
        let target = ProfileID(remoteUserID: remoteUserID)
        guard activeID == .anonymous else {
            return try await activate(remoteUserID: remoteUserID)
        }

        if try await associations.claimAnonymous(by: remoteUserID) {
            try directories.move(from: .anonymous, to: target)
        }
        return try await switchTo(target)
    }

    func activate(remoteUserID: UUID) async throws -> ActiveProfile {
        try await switchTo(ProfileID(remoteUserID: remoteUserID))
    }

    /// Returns to anonymous training. The account's cached data stays on disk
    /// so signing back in restores it.
    func lockCurrent() async throws {
        _ = try await switchTo(.anonymous)
    }

    private func switchTo(_ id: ProfileID) async throws -> ActiveProfile {
        activeID = id
        // Recorded so the next launch reopens on this profile instead of
        // briefly showing anonymous data to a signed-in user.
        try await associations.setLastActiveProfile(id)
        return try await profile(for: id)
    }

    private func profile(for id: ProfileID) async throws -> ActiveProfile {
        ActiveProfile(
            id: id,
            localUserID: try await associations.localUserID(for: id),
            deviceID: try await associations.deviceID(),
            directory: try directories.createDirectory(for: id)
        )
    }
}
