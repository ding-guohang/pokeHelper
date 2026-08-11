import Foundation
import PokerCore
import TrainingDomain
import TrainingPersistence

enum TrainingEventFixture {
    static func correctHighConfidence() -> TrainingEvent {
        score(100, confidence: .verySure, dimension: "bet-sizing")
    }

    static func at(seconds: TimeInterval) -> TrainingEvent {
        at(seconds: seconds, id: eventID(for: seconds))
    }

    static func at(seconds: TimeInterval, id: UUID) -> TrainingEvent {
        makeEvent(
            id: id,
            occurredAt: Date(timeIntervalSince1970: seconds),
            score: 100,
            confidence: .verySure,
            dimension: "bet-sizing"
        )
    }

    static func at(seconds: TimeInterval, score: Int, dimension: String) -> TrainingEvent {
        makeEvent(
            id: eventID(for: seconds),
            occurredAt: Date(timeIntervalSince1970: seconds),
            score: score,
            confidence: .unsure,
            dimension: dimension
        )
    }

    static func score(
        _ score: Int,
        confidence: DecisionConfidence,
        dimension: String
    ) -> TrainingEvent {
        makeEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            occurredAt: Date(timeIntervalSince1970: 1),
            score: score,
            confidence: confidence,
            dimension: dimension
        )
    }

    private static func makeEvent(
        id: UUID,
        occurredAt: Date,
        score: Int,
        confidence: DecisionConfidence,
        dimension: String
    ) -> TrainingEvent {
        let evLossMilliBB = max(0, (100 - score) * 5)

        return TrainingEvent(
            id: id,
            localUserID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            deviceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            occurredAt: occurredAt,
            scenarioID: "scenario-1",
            strategyPackID: "cash-pack",
            strategyContentVersion: "2026.08.06",
            abilityDimension: dimension,
            submission: DecisionSubmission(action: .check, confidence: confidence),
            grade: DecisionGrade(
                selectedAction: .check,
                selectedFrequencyBasisPoints: 10_000,
                selectedEV: EVAmount(milliBB: 1_000 - evLossMilliBB),
                bestEV: EVAmount(milliBB: 1_000),
                evLoss: EVAmount(milliBB: evLossMilliBB),
                lossRateBasisPoints: evLossMilliBB * 2,
                score: score,
                quality: quality(for: score),
                isStrategicallyAvailable: true
            )
        )
    }

    private static func eventID(for seconds: TimeInterval) -> UUID {
        let suffix = String(format: "%012llX", Int64(seconds))
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private static func quality(for score: Int) -> DecisionQuality {
        switch score {
        case 95...:
            .excellent
        case 80...:
            .acceptable
        case 50...:
            .improvable
        default:
            .blunder
        }
    }
}

extension FileTrainingEventStore {
    static func temporary() throws -> FileTrainingEventStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return try FileTrainingEventStore(directory: directory)
    }
}
