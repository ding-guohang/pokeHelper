import CryptoKit
import Foundation

enum SHA256Digest {
    static func hexString(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Checkpoint and acknowledgement state for one profile.
protocol SyncStateStore: Sendable {
    func checkpoint() async throws -> UInt64
    func setCheckpoint(_ value: UInt64) async throws
    func acknowledgedEventIDs() async throws -> Set<UUID>
    func markAcknowledged(_ eventIDs: Set<UUID>) async throws
}

/// JSON-backed sync state written by atomic replacement, so a crash mid-write
/// leaves the previous state intact rather than a truncated file.
actor FileSyncStateStore: SyncStateStore {
    private struct State: Codable, Sendable {
        var checkpoint: UInt64
        var acknowledged: Set<UUID>
    }

    private let file: URL

    init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        file = directory.appending(path: "sync-state.json", directoryHint: .notDirectory)
    }

    func checkpoint() throws -> UInt64 {
        try state().checkpoint
    }

    func setCheckpoint(_ value: UInt64) throws {
        var current = try state()
        // Checkpoints only move forward; an out-of-order response must never
        // rewind the pull cursor and re-deliver events.
        guard value > current.checkpoint else {
            return
        }
        current.checkpoint = value
        try save(current)
    }

    func acknowledgedEventIDs() throws -> Set<UUID> {
        try state().acknowledged
    }

    func markAcknowledged(_ eventIDs: Set<UUID>) throws {
        var current = try state()
        current.acknowledged.formUnion(eventIDs)
        try save(current)
    }

    private func state() throws -> State {
        guard
            let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode(State.self, from: data)
        else {
            return State(checkpoint: 0, acknowledged: [])
        }
        return decoded
    }

    private func save(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}
