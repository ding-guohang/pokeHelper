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

    fileprivate func lockAndReturnAnonymous() async throws -> ActiveProfile {
        try await switchTo(.anonymous)
    }

    fileprivate func adoptAsAnonymous(_ profile: ProfileID) throws {
        try directories.move(from: profile, to: .anonymous)
    }

    fileprivate func removeProfileDirectory(_ profile: ProfileID) throws {
        let directory = directories.directory(for: profile)
        guard FileManager.default.fileExists(
            atPath: directory.path(percentEncoded: false)
        ) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
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

extension ActiveProfileController {
    /// Applies the user's local choice after the remote account is deleted.
    ///
    /// Keeping the data detaches it from the account: the directory is renamed
    /// back to anonymous so training continues with the same hands. Deleting
    /// removes the profile's events, upload queue, sync state, and corrupted
    /// backups together, because leaving any one of them behind would keep a
    /// deleted account's data readable on this device.
    func applyLocalDeletion(
        _ choice: LocalDeletionChoice,
        remoteUserID: UUID
    ) async throws -> ActiveProfile {
        let profile = ProfileID(remoteUserID: remoteUserID)
        switch choice {
        case .keepAnonymized:
            try adoptAsAnonymous(profile)
        case .deleteEverything:
            try removeProfileDirectory(profile)
        }
        return try await lockAndReturnAnonymous()
    }
}
