import Foundation
import SessionSimulation

public enum SessionRecordStoreError: Error, Equatable {
    case recordNotFound(UUID)
    /// A hand line that will not decode, with its 1-based line number. The
    /// number is the point: "the session file is corrupt" sends someone reading
    /// a thousand lines of JSON.
    case corruptedHandLine(sessionID: UUID, line: Int)
    /// A hand arriving out of order. Appending hand 9 to a file holding seven
    /// hands would leave a gap that `SessionProgress` reads as "resume at 8",
    /// so the gap has to be refused at the moment it is created rather than
    /// discovered later as a session that replays wrong.
    case handOutOfOrder(expected: Int, found: Int)
}

/// A session on disk: one directory per session, holding the setup and an
/// append-only log of the hands played so far.
///
/// Hands are appended, never rewritten. That is what makes an interrupted
/// session resumable: whatever was on disk when the process died is exactly the
/// hands that were finished, and a hand that was half-played when the power
/// went out simply is not there. A store that rewrote the whole file on every
/// hand would also be correct on a graceful exit and would lose the file to a
/// kill in the middle of the write.
public actor FileSessionRecordStore {
    private let root: URL

    public init(directory: URL) throws {
        root = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    /// Writes the setup for a session that has not been played yet.
    ///
    /// Idempotent on the same record so that a resume path can call it without
    /// having to ask first; a *different* record under the same ID is a
    /// programmer error and traps rather than silently reseating a table.
    public func create(_ record: SessionRecord) throws {
        let url = recordURL(record.id)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let existing = try self.record(id: record.id)
            precondition(
                existing == record,
                "Session \(record.id) already exists with a different setup"
            )
            return
        }

        try FileManager.default.createDirectory(
            at: sessionDirectory(record.id),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)

        let handsURL = self.handsURL(record.id)
        if !FileManager.default.fileExists(atPath: handsURL.path(percentEncoded: false)) {
            try Data().write(to: handsURL, options: .withoutOverwriting)
        }
    }

    public func record(id: UUID) throws -> SessionRecord {
        let url = recordURL(id)
        guard let data = try? Data(contentsOf: url) else {
            throw SessionRecordStoreError.recordNotFound(id)
        }
        return try JSONDecoder().decode(SessionRecord.self, from: data)
    }

    public func hands(for id: UUID) throws -> [SessionHandRecord] {
        let url = handsURL(id)
        guard let contents = try? Data(contentsOf: url) else {
            throw SessionRecordStoreError.recordNotFound(id)
        }
        guard !contents.isEmpty else {
            return []
        }

        var lines = contents.split(separator: 0x0A, omittingEmptySubsequences: false)
        if contents.last == 0x0A {
            lines.removeLast()
        }

        let decoder = JSONDecoder()
        return try lines.enumerated().map { offset, line in
            do {
                return try decoder.decode(SessionHandRecord.self, from: Data(line))
            } catch {
                throw SessionRecordStoreError.corruptedHandLine(
                    sessionID: id,
                    line: offset + 1
                )
            }
        }
    }

    public func progress(for id: UUID) throws -> SessionProgress {
        SessionProgress(record: try record(id: id), playedHands: try hands(for: id))
    }

    /// Appends one finished hand.
    ///
    /// One `write` at the end of the file, with no read-modify-write of what is
    /// already there, so the hands already stored cannot be damaged by a hand
    /// being stored now.
    public func appendHand(_ hand: SessionHandRecord, to id: UUID) throws {
        let stored = try hands(for: id)
        guard hand.handIndex == stored.count else {
            throw SessionRecordStoreError.handOutOfOrder(
                expected: stored.count,
                found: hand.handIndex
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(hand)
        line.append(0x0A)

        let handle = try FileHandle(forWritingTo: handsURL(id))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Every session on disk, in ID order.
    public func sessionIDs() throws -> [UUID] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        return entries
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    private func sessionDirectory(_ id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func recordURL(_ id: UUID) -> URL {
        sessionDirectory(id).appending(path: "record.json", directoryHint: .notDirectory)
    }

    private func handsURL(_ id: UUID) -> URL {
        sessionDirectory(id).appending(path: "hands.jsonl", directoryHint: .notDirectory)
    }
}
