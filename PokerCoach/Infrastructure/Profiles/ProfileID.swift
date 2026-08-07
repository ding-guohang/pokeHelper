import Foundation

/// Identifies one isolated slice of on-device data.
///
/// Anonymous training and each signed-in account get their own profile, so two
/// accounts sharing an installation never see each other's hands.
struct ProfileID: Hashable, Sendable, Codable {
    let rawValue: String

    static let anonymous = ProfileID(rawValue: "anonymous")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(remoteUserID: UUID) {
        rawValue = "user-\(remoteUserID.uuidString.lowercased())"
    }
}

/// Everything a dependency needs to read and write one profile's data.
struct ActiveProfile: Sendable, Equatable {
    let id: ProfileID
    /// Profile-scoped. Two profiles never share one, so synced events stay
    /// attributable.
    let localUserID: UUID
    /// Installation-scoped. Every profile on this device reports the same one.
    let deviceID: UUID
    let directory: URL
}

/// Maps profiles onto directories under a single root.
struct ProfileDirectoryProvider: Sendable {
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func directory(for profile: ProfileID) -> URL {
        root
            .appending(path: "Profiles", directoryHint: .isDirectory)
            .appending(path: profile.rawValue, directoryHint: .isDirectory)
    }

    func createDirectory(for profile: ProfileID) throws -> URL {
        let url = directory(for: profile)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Renames a profile directory. Used to claim anonymous history, where
    /// moving the directory preserves every byte of the append-only log.
    func move(from source: ProfileID, to destination: ProfileID) throws {
        let sourceURL = directory(for: source)
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            return
        }
        let destinationURL = directory(for: destination)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}
