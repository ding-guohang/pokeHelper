import Foundation
import Synchronization

public actor FileTrainingEventStore: TrainingEventStore {
    private let coordinator: TrainingEventFileCoordinator

    public init(directory: URL) throws {
        coordinator = try TrainingEventFileCoordinatorRegistry.coordinator(
            for: directory
        )
    }

    public func append(_ event: TrainingEvent) async throws {
        try await coordinator.append(event)
    }

    public func allEvents() async throws -> [TrainingEvent] {
        try await coordinator.allEvents()
    }

    public func events(after checkpoint: UUID?) async throws -> [TrainingEvent] {
        try await coordinator.events(after: checkpoint)
    }
}

private enum TrainingEventFileCoordinatorRegistry {
    private static let coordinators = Mutex<
        [String: WeakTrainingEventFileCoordinator]
    >([:])

    static func coordinator(
        for directory: URL
    ) throws -> TrainingEventFileCoordinator {
        let standardizedDirectory = directory.standardizedFileURL
        try FileManager.default.createDirectory(
            at: standardizedDirectory,
            withIntermediateDirectories: true
        )
        let canonicalDirectory = standardizedDirectory
            .resolvingSymlinksInPath()
        let fileURL = canonicalDirectory.appending(
            path: "training-events.jsonl"
        )

        return try coordinators.withLock { coordinators in
            let fileSystemPath = fileURL.path(percentEncoded: false)
            if !FileManager.default.fileExists(atPath: fileSystemPath) {
                try Data().write(
                    to: fileURL,
                    options: .withoutOverwriting
                )
            }

            let decodedEvents = try TrainingEventFileCoordinator.decodeEvents(
                from: fileURL
            )
            let key = fileSystemPath
            if let coordinator = coordinators[key]?.coordinator {
                return coordinator
            }

            let coordinator = TrainingEventFileCoordinator(
                directoryURL: canonicalDirectory,
                fileURL: fileURL,
                events: decodedEvents
            )
            coordinators[key] = WeakTrainingEventFileCoordinator(coordinator)
            coordinators = coordinators.filter {
                $0.value.coordinator != nil
            }
            return coordinator
        }
    }
}

private final class WeakTrainingEventFileCoordinator {
    weak var coordinator: TrainingEventFileCoordinator?

    init(_ coordinator: TrainingEventFileCoordinator) {
        self.coordinator = coordinator
    }
}

private actor TrainingEventFileCoordinator {
    private let directoryURL: URL
    private let fileURL: URL
    private var events: [TrainingEvent]
    private var eventIDs: Set<UUID>

    init(
        directoryURL: URL,
        fileURL: URL,
        events: [TrainingEvent]
    ) {
        self.directoryURL = directoryURL
        self.fileURL = fileURL
        self.events = events
        eventIDs = Set(events.map(\.id))
    }

    func append(_ event: TrainingEvent) throws {
        try refreshFromDisk()
        guard !eventIDs.contains(event.id) else {
            return
        }

        let updatedEvents = events + [event]
        try rewriteFile(with: updatedEvents)
        events = updatedEvents
        eventIDs.insert(event.id)
    }

    func allEvents() throws -> [TrainingEvent] {
        try refreshFromDisk()
        return sortedEvents()
    }

    func events(after checkpoint: UUID?) throws -> [TrainingEvent] {
        try refreshFromDisk()
        let orderedEvents = sortedEvents()
        guard let checkpoint else {
            return orderedEvents
        }
        guard let checkpointIndex = orderedEvents.firstIndex(where: {
            $0.id == checkpoint
        }) else {
            throw TrainingEventStoreError.checkpointNotFound
        }

        return Array(orderedEvents.dropFirst(checkpointIndex + 1))
    }

    static func decodeEvents(from fileURL: URL) throws -> [TrainingEvent] {
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

    private func refreshFromDisk() throws {
        let latestEvents = try Self.decodeEvents(from: fileURL)
        events = latestEvents
        eventIDs = Set(latestEvents.map(\.id))
    }

    private func sortedEvents() -> [TrainingEvent] {
        events.sorted {
            if $0.occurredAt == $1.occurredAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.occurredAt < $1.occurredAt
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
