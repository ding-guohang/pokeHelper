import Foundation
import StrategyContent
@testable import TrainingDomain

/// Builds a node history that satisfies every mastery signal, with one knob per
/// signal so a test can break exactly one of them.
///
/// The shape is fixed: an opening failure starts the repetition ladder, two
/// on-time passes complete it, and the remaining answers are on fresh scenario
/// IDs so the most recent three double as the transfer evidence.
enum MasteryFixture {
    static let nodeID = "turn-barrel"
    static let sampleRequirement = 20

    static func pack(scenarioCount: Int = 40) -> StrategyPack {
        CurriculumFixture.pack(
            scenarios: (0 ..< scenarioCount).map {
                (id: scenarioID($0), node: nodeID)
            },
            nodes: [(nodeID, [])]
        )
    }

    static func scenarioID(_ index: Int) -> String {
        String(format: "s-%03d", index)
    }

    static func allSignalsSatisfied(
        sampleCount: Int = sampleRequirement,
        recentFailureCount: Int = 0,
        highConfidenceErrorInRecentWindow: Bool = false,
        completedRepetitions: Int = 2,
        transferPassCount: Int = 3
    ) -> [TrainingEvent] {
        var events: [TrainingEvent] = []

        // Day 0: the failure that puts the node into the repetition rotation.
        events.append(
            CurriculumFixture.event(
                scenarioID: scenarioID(0),
                quality: .blunder,
                daysAfterEpoch: 0
            )
        )

        // On-time repetitions. The ladder is 1 → 3 → 7, so a pass on day 1 and
        // another on day 4 are both due when they happen.
        let repetitionDays = [1.0, 4.0]
        for index in 0 ..< min(completedRepetitions, repetitionDays.count) {
            events.append(
                CurriculumFixture.event(
                    scenarioID: scenarioID(index + 1),
                    quality: .acceptable,
                    daysAfterEpoch: repetitionDays[index]
                )
            )
        }

        // Ordinary practice on fresh scenarios, filling the sample out.
        //
        // Placed just after the last repetition and well before the next due
        // date. Practice that lands on or after a due date is itself a
        // repetition, so spacing these out by whole days would make the
        // repetition count depend on the sample size and the knob below would
        // control nothing.
        let practiceStart = repetitionDays.prefix(completedRepetitions).last ?? 0
        let remaining = max(0, sampleCount - events.count)
        for index in 0 ..< remaining {
            events.append(
                CurriculumFixture.event(
                    scenarioID: scenarioID(index + 3),
                    quality: .excellent,
                    daysAfterEpoch: practiceStart + 0.01 * Double(index + 1)
                )
            )
        }

        events = applyRecentFailures(recentFailureCount, to: events)
        events = applyTransferFailures(3 - transferPassCount, to: events)
        if highConfidenceErrorInRecentWindow {
            events = applyHighConfidenceError(to: events)
        }
        return events
    }

    /// Degrades the oldest entries of the recent-ten window, leaving the final
    /// three alone so the transfer signal stays independent of this knob.
    private static func applyRecentFailures(
        _ count: Int,
        to events: [TrainingEvent]
    ) -> [TrainingEvent] {
        guard count > 0, events.count >= 10 else { return events }
        var result = events
        let windowStart = events.count - 10
        for offset in 0 ..< min(count, 7) {
            result[windowStart + offset] = degrade(result[windowStart + offset])
        }
        return result
    }

    /// Degrades the most recent first-encounters, which is what transfer reads.
    private static func applyTransferFailures(
        _ count: Int,
        to events: [TrainingEvent]
    ) -> [TrainingEvent] {
        guard count > 0 else { return events }
        var result = events
        for offset in 0 ..< min(count, 3) {
            let index = result.count - 1 - offset
            guard index >= 0 else { break }
            result[index] = degrade(result[index])
        }
        return result
    }

    /// Marks one recent answer very-sure and wrong, which breaks calibration
    /// while leaving nine of the last ten passing.
    private static func applyHighConfidenceError(
        to events: [TrainingEvent]
    ) -> [TrainingEvent] {
        guard events.count >= 10 else { return events }
        var result = events
        let index = events.count - 4
        result[index] = CurriculumFixture.event(
            scenarioID: result[index].scenarioID,
            quality: .blunder,
            confidence: .verySure,
            daysAfterEpoch: result[index].occurredAt
                .timeIntervalSince(CurriculumFixture.epoch) / 86_400
        )
        return result
    }

    private static func degrade(_ event: TrainingEvent) -> TrainingEvent {
        CurriculumFixture.event(
            scenarioID: event.scenarioID,
            quality: .blunder,
            confidence: .unsure,
            daysAfterEpoch: event.occurredAt
                .timeIntervalSince(CurriculumFixture.epoch) / 86_400
        )
    }
}
