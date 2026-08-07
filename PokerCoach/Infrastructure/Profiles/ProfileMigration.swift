import Foundation

/// Moves an M1A installation into the profile layout.
///
/// M1A kept one event log directly under `Library/PokerCoach` and its identity
/// in UserDefaults. Without this migration an existing user would launch M1B
/// onto an empty anonymous profile and appear to have lost every hand they had
/// trained.
enum ProfileMigration {
    static func migrateLegacyInstallIfNeeded(
        root: URL,
        records: ProfileRecordFile,
        directories: ProfileDirectoryProvider,
        legacyIdentity: LocalIdentity?
    ) throws {
        let legacyLog = root.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        guard FileManager.default.fileExists(
            atPath: legacyLog.path(percentEncoded: false)
        ) else {
            return
        }

        let anonymousDirectory = try directories.createDirectory(for: .anonymous)
        let destination = anonymousDirectory.appending(
            path: "training-events.jsonl",
            directoryHint: .notDirectory
        )
        guard !FileManager.default.fileExists(
            atPath: destination.path(percentEncoded: false)
        ) else {
            // The anonymous profile already has a log; leaving both untouched
            // is safer than guessing which one is authoritative.
            return
        }

        // Moving preserves the exact bytes, so event IDs and ordering survive.
        try FileManager.default.moveItem(at: legacyLog, to: destination)

        // Carry the M1A identity forward so migrated events keep matching the
        // identifiers new events will be written with.
        if let legacyIdentity {
            try records.adoptLegacyIdentity(legacyIdentity)
        }

        try moveLegacyBackups(from: root, to: anonymousDirectory)
    }

    private static func moveLegacyBackups(from root: URL, to destination: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: root.path(percentEncoded: false)
        )
        for name in names where name.hasPrefix("training-events.corrupted-") {
            let source = root.appending(path: name, directoryHint: .notDirectory)
            let target = destination.appending(path: name, directoryHint: .notDirectory)
            guard !FileManager.default.fileExists(
                atPath: target.path(percentEncoded: false)
            ) else {
                continue
            }
            try FileManager.default.moveItem(at: source, to: target)
        }
    }
}
