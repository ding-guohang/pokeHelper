import Foundation
import PokerCore
import Testing
import TrainingDomain
import TrainingPersistence

@Test func publicConsumerCanConstructAndAppendTrainingEvent() async throws {
    let gradeJSON = Data(
        """
        {
          "bestEV": {"milliBB": 1000},
          "evLoss": {"milliBB": 0},
          "isStrategicallyAvailable": true,
          "lossRateBasisPoints": 0,
          "quality": "excellent",
          "score": 100,
          "selectedAction": {"kind": "check"},
          "selectedEV": {"milliBB": 1000},
          "selectedFrequencyBasisPoints": 10000
        }
        """.utf8
    )
    let grade = try JSONDecoder().decode(DecisionGrade.self, from: gradeJSON)
    let event = TrainingEvent(
        id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
        localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        occurredAt: Date(timeIntervalSince1970: 1),
        scenarioID: "public-scenario",
        strategyPackID: "public-pack",
        strategyContentVersion: "2026.08.06",
        abilityDimension: "bet-sizing",
        submission: DecisionSubmission(action: .check, confidence: .verySure),
        grade: grade
    )
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = try FileTrainingEventStore(directory: directory)

    try await store.append(event)

    #expect(try await store.allEvents() == [event])
}
