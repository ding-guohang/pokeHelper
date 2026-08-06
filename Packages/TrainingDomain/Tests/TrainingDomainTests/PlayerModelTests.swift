import Foundation
import Testing
@testable import TrainingDomain

@Test func reducerSeparatesHighConfidenceErrors() {
    let events = [
        TrainingEventFixture.score(40, confidence: .verySure, dimension: "bet-sizing"),
        TrainingEventFixture.score(90, confidence: .guessing, dimension: "preflop-range"),
    ]

    let profile = PlayerModelReducer().reduce(events: events)

    #expect(profile["bet-sizing"]?.highConfidenceErrorCount == 1)
    #expect(profile["bet-sizing"]?.meanScore == 40)
    #expect(profile["bet-sizing"]?.meanLossRateBasisPoints == 600)
    #expect(profile["preflop-range"]?.meanScore == 90)
    #expect(profile["preflop-range"]?.highConfidenceErrorCount == 0)
}

@Test func reducerUsesIntegerMeansAndLatestPracticeDate() {
    let older = TrainingEventFixture.at(seconds: 1_799_000_000, score: 31, dimension: "flop-play")
    let newer = TrainingEventFixture.at(seconds: 1_799_100_000, score: 32, dimension: "flop-play")

    let snapshot = PlayerModelReducer().reduce(events: [newer, older])["flop-play"]

    #expect(snapshot?.sampleCount == 2)
    #expect(snapshot?.meanScore == 31)
    #expect(snapshot?.meanLossRateBasisPoints == 685)
    #expect(snapshot?.lastPracticedAt == Date(timeIntervalSince1970: 1_799_100_000))
}
