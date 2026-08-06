import Foundation
import Testing
@testable import TrainingDomain

@Test func eventStoreAppendsAndDeduplicatesByID() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = try FileTrainingEventStore(directory: directory)
    let event = TrainingEventFixture.correctHighConfidence()

    try await store.append(event)
    try await store.append(event)

    let events = try await store.allEvents()
    #expect(events == [event])
}

@Test func eventsAfterCheckpointAreOrdered() async throws {
    let store = try FileTrainingEventStore.temporary()
    let first = TrainingEventFixture.at(seconds: 1)
    let second = TrainingEventFixture.at(seconds: 2)
    try await store.append(second)
    try await store.append(first)

    #expect(try await store.events(after: first.id) == [second])
}

@Test func initializationCreatesEmptyJSONLinesFile() throws {
    let directory = temporaryEventDirectory()
    _ = try FileTrainingEventStore(directory: directory)

    let fileURL = directory.appending(path: "training-events.jsonl")
    #expect(
        FileManager.default.fileExists(
            atPath: fileURL.path(percentEncoded: false)
        )
    )
    #expect(try Data(contentsOf: fileURL).isEmpty)
}

@Test func eventStorePersistsEventsAcrossInstances() async throws {
    let directory = temporaryEventDirectory()
    let event = TrainingEventFixture.correctHighConfidence()
    let firstStore = try FileTrainingEventStore(directory: directory)
    try await firstStore.append(event)

    let reopenedStore = try FileTrainingEventStore(directory: directory)
    #expect(try await reopenedStore.allEvents() == [event])
}

@Test func eventStorePersistsEventsWhenDirectoryContainsSpaces() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(
            path: "Poker Coach \(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    let event = TrainingEventFixture.correctHighConfidence()
    let firstStore = try FileTrainingEventStore(directory: directory)

    try await firstStore.append(event)

    let eventFile = directory.appending(path: "training-events.jsonl")
    #expect(
        FileManager.default.fileExists(
            atPath: eventFile.path(percentEncoded: false)
        )
    )
    let reopenedStore = try FileTrainingEventStore(directory: directory)
    #expect(try await reopenedStore.allEvents() == [event])
}

@Test func corruptedSecondLineReturnsTypedLineNumber() throws {
    let directory = temporaryEventDirectory()
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let firstLine = try JSONEncoder().encode(
        TrainingEventFixture.correctHighConfidence()
    )
    var contents = firstLine
    contents.append(Data("\nnot-json\n".utf8))
    try contents.write(
        to: directory.appending(path: "training-events.jsonl")
    )

    #expect(throws: TrainingEventStoreError.corruptedLine(2)) {
        _ = try FileTrainingEventStore(directory: directory)
    }
}

@Test func missingCheckpointReturnsTypedError() async throws {
    let store = try FileTrainingEventStore.temporary()
    try await store.append(TrainingEventFixture.correctHighConfidence())
    let missingID = UUID(
        uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
    )!

    await #expect(throws: TrainingEventStoreError.checkpointNotFound) {
        try await store.events(after: missingID)
    }
}

@Test func equalTimestampsAreOrderedByUUIDString() async throws {
    let store = try FileTrainingEventStore.temporary()
    let earlierID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!
    let laterID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000002"
    )!
    let earlier = TrainingEventFixture.at(seconds: 10, id: earlierID)
    let later = TrainingEventFixture.at(seconds: 10, id: laterID)

    try await store.append(later)
    try await store.append(earlier)

    #expect(try await store.allEvents() == [earlier, later])
}

@Test func duplicateIDRemainsDeduplicatedAfterReopening() async throws {
    let directory = temporaryEventDirectory()
    let event = TrainingEventFixture.correctHighConfidence()
    let firstStore = try FileTrainingEventStore(directory: directory)
    try await firstStore.append(event)

    let reopenedStore = try FileTrainingEventStore(directory: directory)
    try await reopenedStore.append(event)

    #expect(try await reopenedStore.allEvents() == [event])
}

@Test func concurrentAppendsDoNotLoseEvents() async throws {
    let store = try FileTrainingEventStore.temporary()
    let expected = (1...12).map {
        TrainingEventFixture.at(seconds: TimeInterval($0))
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for event in expected.reversed() {
            group.addTask {
                try await store.append(event)
            }
        }
        try await group.waitForAll()
    }

    #expect(try await store.allEvents() == expected)
}

@Test func liveStoresInterleaveAppendsWithoutLosingEvents() async throws {
    let directory = temporaryEventDirectory()
    let firstStore = try FileTrainingEventStore(directory: directory)
    let secondStore = try FileTrainingEventStore(directory: directory)
    let first = TrainingEventFixture.at(seconds: 1)
    let second = TrainingEventFixture.at(seconds: 2)
    let third = TrainingEventFixture.at(seconds: 3)
    let expected = [first, second, third]

    try await firstStore.append(first)
    try await secondStore.append(second)
    try await firstStore.append(third)

    #expect(try await firstStore.allEvents() == expected)
    #expect(try await secondStore.allEvents() == expected)
    let reopenedStore = try FileTrainingEventStore(directory: directory)
    #expect(try await reopenedStore.allEvents() == expected)
}

@Test func staleStoreDoesNotOverwriteCorruptedFile() async throws {
    let directory = temporaryEventDirectory()
    let firstStore = try FileTrainingEventStore(directory: directory)
    let staleStore = try FileTrainingEventStore(directory: directory)
    try await firstStore.append(TrainingEventFixture.at(seconds: 1))

    let fileURL = directory.appending(path: "training-events.jsonl")
    var corruptedContents = try Data(contentsOf: fileURL)
    corruptedContents.append(Data("not-json\n".utf8))
    try corruptedContents.write(to: fileURL)

    await #expect(throws: TrainingEventStoreError.corruptedLine(2)) {
        try await staleStore.append(TrainingEventFixture.at(seconds: 2))
    }
    #expect(try Data(contentsOf: fileURL) == corruptedContents)
}

private func temporaryEventDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
}
