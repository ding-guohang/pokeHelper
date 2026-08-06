import Foundation

public struct TrainingEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let localUserID: UUID
    public let deviceID: UUID
    public let occurredAt: Date
    public let scenarioID: String
    public let strategyPackID: String
    public let strategyContentVersion: String
    public let abilityDimension: String
    public let submission: DecisionSubmission
    public let grade: DecisionGrade
}

extension TrainingEvent: Equatable {
    public static func == (lhs: TrainingEvent, rhs: TrainingEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.localUserID == rhs.localUserID
            && lhs.deviceID == rhs.deviceID
            && lhs.occurredAt == rhs.occurredAt
            && lhs.scenarioID == rhs.scenarioID
            && lhs.strategyPackID == rhs.strategyPackID
            && lhs.strategyContentVersion == rhs.strategyContentVersion
            && lhs.abilityDimension == rhs.abilityDimension
            && lhs.submission == rhs.submission
            && lhs.grade.selectedAction == rhs.grade.selectedAction
            && lhs.grade.selectedFrequencyBasisPoints == rhs.grade.selectedFrequencyBasisPoints
            && lhs.grade.selectedEV == rhs.grade.selectedEV
            && lhs.grade.bestEV == rhs.grade.bestEV
            && lhs.grade.evLoss == rhs.grade.evLoss
            && lhs.grade.lossRateBasisPoints == rhs.grade.lossRateBasisPoints
            && lhs.grade.score == rhs.grade.score
            && lhs.grade.quality == rhs.grade.quality
            && lhs.grade.isStrategicallyAvailable == rhs.grade.isStrategicallyAvailable
    }
}
