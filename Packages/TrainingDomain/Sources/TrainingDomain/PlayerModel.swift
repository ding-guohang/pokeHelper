import Foundation

public struct AbilitySnapshot: Equatable, Codable, Sendable {
    public let dimension: String
    public let sampleCount: Int
    public let meanScore: Int
    public let meanLossRateBasisPoints: Int
    public let highConfidenceErrorCount: Int
    public let lastPracticedAt: Date?

    public init(
        dimension: String,
        sampleCount: Int,
        meanScore: Int,
        meanLossRateBasisPoints: Int,
        highConfidenceErrorCount: Int,
        lastPracticedAt: Date?
    ) {
        self.dimension = dimension
        self.sampleCount = sampleCount
        self.meanScore = meanScore
        self.meanLossRateBasisPoints = meanLossRateBasisPoints
        self.highConfidenceErrorCount = highConfidenceErrorCount
        self.lastPracticedAt = lastPracticedAt
    }
}

public struct PlayerProfile: Equatable, Codable, Sendable {
    public let abilities: [String: AbilitySnapshot]

    public init(abilities: [String: AbilitySnapshot]) {
        self.abilities = abilities
    }

    public subscript(dimension: String) -> AbilitySnapshot? {
        abilities[dimension]
    }
}

public struct PlayerModelReducer: Sendable {
    public init() {}

    public func reduce(events: [TrainingEvent]) -> PlayerProfile {
        var aggregates: [String: AbilityAggregate] = [:]

        for event in events {
            var aggregate = aggregates[event.abilityDimension] ?? .init()
            aggregate.add(event)
            aggregates[event.abilityDimension] = aggregate
        }

        let abilities = aggregates.mapValues { aggregate in
            AbilitySnapshot(
                dimension: aggregate.dimension,
                sampleCount: aggregate.sampleCount,
                meanScore: aggregate.scoreTotal / aggregate.sampleCount,
                meanLossRateBasisPoints: aggregate.lossRateTotal / aggregate.sampleCount,
                highConfidenceErrorCount: aggregate.highConfidenceErrorCount,
                lastPracticedAt: aggregate.lastPracticedAt
            )
        }

        return PlayerProfile(abilities: abilities)
    }
}

private struct AbilityAggregate {
    var dimension = ""
    var sampleCount = 0
    var scoreTotal = 0
    var lossRateTotal = 0
    var highConfidenceErrorCount = 0
    var lastPracticedAt: Date?

    mutating func add(_ event: TrainingEvent) {
        dimension = event.abilityDimension
        sampleCount += 1
        scoreTotal += event.grade.score
        lossRateTotal += event.grade.lossRateBasisPoints
        if event.submission.confidence == .verySure, isError(event.grade.quality) {
            highConfidenceErrorCount += 1
        }
        lastPracticedAt = maxDate(lastPracticedAt, event.occurredAt)
    }

    private func isError(_ quality: DecisionQuality) -> Bool {
        quality == .improvable || quality == .blunder
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else {
            return rhs
        }
        return max(lhs, rhs)
    }
}
