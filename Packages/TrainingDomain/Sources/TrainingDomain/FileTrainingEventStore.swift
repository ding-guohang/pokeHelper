import Foundation

public actor FileTrainingEventStore: TrainingEventStore {
    private let directoryURL: URL
    private let fileURL: URL
    private var events: [TrainingEvent]
    private var eventIDs: Set<UUID>

    public init(directory: URL) throws {
        let fileURL = directory.appending(path: "training-events.jsonl")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path()) {
            try Data().write(to: fileURL, options: .withoutOverwriting)
        }

        let decodedEvents = try Self.decodeEvents(from: fileURL)
        directoryURL = directory
        self.fileURL = fileURL
        events = decodedEvents
        eventIDs = Set(decodedEvents.map(\.id))
    }

    public func append(_ event: TrainingEvent) async throws {
        guard !eventIDs.contains(event.id) else {
            return
        }

        let updatedEvents = events + [event]
        try rewriteFile(with: updatedEvents)
        events = updatedEvents
        eventIDs.insert(event.id)
    }

    public func allEvents() async throws -> [TrainingEvent] {
        sortedEvents()
    }

    public func events(after checkpoint: UUID?) async throws -> [TrainingEvent] {
        let orderedEvents = sortedEvents()
        guard let checkpoint else {
            return orderedEvents
        }
        guard let checkpointIndex = orderedEvents.firstIndex(where: { $0.id == checkpoint }) else {
            throw TrainingEventStoreError.checkpointNotFound
        }

        return Array(orderedEvents.dropFirst(checkpointIndex + 1))
    }

    private func sortedEvents() -> [TrainingEvent] {
        events.sorted {
            if $0.occurredAt == $1.occurredAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.occurredAt < $1.occurredAt
        }
    }

    private static func decodeEvents(from fileURL: URL) throws -> [TrainingEvent] {
        let contents = try Data(contentsOf: fileURL)
        guard !contents.isEmpty else {
            return []
        }

        var lines = contents.split(
            separator: 0x0A,
            omittingEmptySubsequences: false
        )
        if contents.last == 0x0A {
            lines.removeLast()
        }

        let decoder = JSONDecoder()
        return try lines.enumerated().map { offset, line in
            do {
                return try decoder.decode(TrainingEvent.self, from: Data(line))
            } catch {
                throw TrainingEventStoreError.corruptedLine(offset + 1)
            }
        }
    }

    private func rewriteFile(with events: [TrainingEvent]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var contents = Data()
        for event in events {
            contents.append(try encoder.encode(event))
            contents.append(0x0A)
        }

        let temporaryURL = directoryURL.appending(
            path: ".training-events-\(UUID().uuidString).tmp"
        )
        do {
            try contents.write(to: temporaryURL, options: .withoutOverwriting)
            _ = try FileManager.default.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
}
