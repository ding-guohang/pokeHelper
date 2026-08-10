import Foundation

/// What to do with this installation's cached training data when the remote
/// account is deleted.
enum LocalDeletionChoice: String, Sendable, Equatable, CaseIterable, Identifiable {
    /// Keep the hands, drop the account association. The user keeps training
    /// with the history they built.
    case keepAnonymized
    /// Remove this profile's events, queue, sync state, and backups.
    case deleteEverything

    var id: Self { self }

    var title: String {
        switch self {
        case .keepAnonymized:
            "保留本机训练记录"
        case .deleteEverything:
            "同时删除本机训练记录"
        }
    }

    var explanation: String {
        switch self {
        case .keepAnonymized:
            "云端账号会被删除，本机训练记录会保留并转为未登录状态继续使用。"
        case .deleteEverything:
            "云端账号与本机训练记录都会删除，且无法恢复。"
        }
    }
}

/// Builds the file bundle a user takes away.
///
/// The remote document is written as received. Corrupted-history backups are
/// added from the local profile because they are the user's hands too, but they
/// are never uploaded: they exist precisely because they could not be parsed,
/// and shipping unparsed data to the server would be a way to smuggle
/// arbitrary content into an account.
struct AccountExportBuilder: Sendable {
    static let bundleSchemaVersion = 1

    struct Manifest: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let generatedAt: Date
        let files: [String]
    }

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    func build(
        remote: RemoteAccountExport,
        profile: ActiveProfile,
        destination: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        var files: [String] = []

        let accountFile = destination.appending(
            path: "account.json",
            directoryHint: .notDirectory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(RemoteExportEnvelope(remote)).write(to: accountFile, options: .atomic)
        files.append("account.json")

        files.append(contentsOf: try copyCorruptedBackups(from: profile, to: destination))

        let manifest = Manifest(
            schemaVersion: Self.bundleSchemaVersion,
            generatedAt: now(),
            files: files.sorted()
        )
        let manifestFile = destination.appending(
            path: "manifest.json",
            directoryHint: .notDirectory
        )
        try encoder.encode(manifest).write(to: manifestFile, options: .atomic)

        return destination
    }

    private func copyCorruptedBackups(
        from profile: ActiveProfile,
        to destination: URL
    ) throws -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: profile.directory.path(percentEncoded: false)
        )) ?? []

        let backups = names
            .filter { $0.hasPrefix("training-events.corrupted-") }
            .sorted()
        guard !backups.isEmpty else {
            return []
        }

        let folder = destination.appending(path: "backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var copied: [String] = []
        for name in backups {
            let source = profile.directory.appending(path: name, directoryHint: .notDirectory)
            let target = folder.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: target)
            }
            // Copied verbatim: these are raw bytes the parser rejected, and
            // rewriting them would destroy the evidence of what went wrong.
            try FileManager.default.copyItem(at: source, to: target)
            copied.append("backups/\(name)")
        }
        return copied
    }
}

/// Re-encodes the server document for the bundle. Only fields the server sent
/// are written; nothing local is mixed in.
private struct RemoteExportEnvelope: Encodable {
    let schemaVersion: Int
    let account: Account
    let devices: [Device]
    let events: [AnyCodableValue]

    struct Account: Encodable {
        let userID: String
        let createdAt: Date
    }

    struct Device: Encodable {
        let displayName: String
        let platform: String
        let appVersion: String
    }

    init(_ remote: RemoteAccountExport) {
        schemaVersion = remote.schemaVersion
        account = Account(
            userID: remote.account.userID.uuidString.lowercased(),
            createdAt: remote.account.createdAt
        )
        devices = remote.devices.map {
            Device(
                displayName: $0.displayName,
                platform: $0.platform,
                appVersion: $0.appVersion
            )
        }
        events = remote.events
    }
}
