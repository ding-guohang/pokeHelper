import Foundation

public protocol TrainingEventStore: Sendable {
    func append(_ event: TrainingEvent) async throws
    func allEvents() async throws -> [TrainingEvent]
    func events(after checkpoint: UUID?) async throws -> [TrainingEvent]
}

public enum TrainingEventStoreError: Error, Equatable {
    case corruptedLine(Int)
    case checkpointNotFound
}
