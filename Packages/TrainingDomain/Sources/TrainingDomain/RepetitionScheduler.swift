import Foundation
import StrategyContent

/// When a curriculum node next falls due for repetition.
public struct RepetitionSchedule: Sendable, Equatable {
    public let nodeID: String
    public let intervalDays: Int
    public let nextDueAt: Date
}

/// A repetition the plan should surface today.
///
/// `scenarioID` is nil when the node has no unanswered scenario left. Serving
/// the question the user already failed would train recall of that answer
/// rather than the skill, so the repetition is suspended instead and says so.
public struct RepetitionPlanItem: Sendable, Equatable {
    public let nodeID: String
    public let scenarioID: String?
    public let schedule: RepetitionSchedule

    public var isContentLimited: Bool { scenarioID == nil }
}

/// Derives repetition state by folding a node's event history.
///
/// Nothing is persisted. Storing `nextDueAt` would introduce mutable state that
/// has to answer how it synchronizes, how it isolates across profiles, and who
/// wins when two devices disagree — M1B established that the profile is a
/// deterministic reduction of the complete history, and a stored schedule would
/// be an exception sitting beside that guarantee.
public struct RepetitionScheduler: Sendable {
    /// Days between repetitions, in order. A correct repetition moves one rung
    /// up, an incorrect one moves one rung down, and the bottom rung is one day
    /// so an interval can never reach zero and re-serve a node in the same
    /// session.
    public static let ladderDays = [1, 3, 7, 14, 30]

    public init() {}

    public func schedule(
        forNode nodeID: String,
        events: [TrainingEvent]
    ) -> RepetitionSchedule? {
        let ordered = Self.chronological(events)

        guard let firstFailure = ordered.first(where: { Self.isError($0.grade.quality) })
        else {
            return nil
        }

        var rung = 0
        var dueAt = Self.advance(from: firstFailure.occurredAt, rung: rung)

        for event in ordered where event.occurredAt >= dueAt {
            rung = Self.isError(event.grade.quality)
                ? max(0, rung - 1)
                : min(Self.ladderDays.count - 1, rung + 1)
            dueAt = Self.advance(from: event.occurredAt, rung: rung)
        }

        return RepetitionSchedule(
            nodeID: nodeID,
            intervalDays: Self.ladderDays[rung],
            nextDueAt: dueAt
        )
    }

    /// How many due repetitions the user answered correctly.
    ///
    /// Shares the fold with `schedule(forNode:events:)` so "what counts as a
    /// repetition" has exactly one definition. Practice that happens before the
    /// node falls due is not a repetition and is not counted.
    public func completedRepetitionCount(events: [TrainingEvent]) -> Int {
        let ordered = Self.chronological(events)
        guard let firstFailure = ordered.first(where: { Self.isError($0.grade.quality) })
        else {
            return 0
        }

        var rung = 0
        var dueAt = Self.advance(from: firstFailure.occurredAt, rung: rung)
        var completed = 0

        for event in ordered where event.occurredAt >= dueAt {
            if Self.isError(event.grade.quality) {
                rung = max(0, rung - 1)
            } else {
                rung = min(Self.ladderDays.count - 1, rung + 1)
                completed += 1
            }
            dueAt = Self.advance(from: event.occurredAt, rung: rung)
        }
        return completed
    }

    /// Repetitions that have fallen due, longest-waiting first.
    public func dueRepetitions(
        events: [TrainingEvent],
        pack: StrategyPack,
        now: Date
    ) -> [RepetitionPlanItem] {
        let resolver = CurriculumResolver(pack: pack)
        let eventsByNode = resolver.eventsByNode(events)
        let scenarioIDsByNode = Dictionary(
            grouping: pack.scenarios,
            by: \.curriculumNodeID
        ).mapValues { $0.map(\.id).sorted() }

        return eventsByNode
            .compactMap { nodeID, nodeEvents -> RepetitionPlanItem? in
                guard let schedule = schedule(forNode: nodeID, events: nodeEvents),
                      schedule.nextDueAt <= now
                else {
                    return nil
                }

                let answered = Set(nodeEvents.map(\.scenarioID))
                let unanswered = (scenarioIDsByNode[nodeID] ?? [])
                    .first { !answered.contains($0) }

                return RepetitionPlanItem(
                    nodeID: nodeID,
                    scenarioID: unanswered,
                    schedule: schedule
                )
            }
            .sorted { lhs, rhs in
                if lhs.schedule.nextDueAt != rhs.schedule.nextDueAt {
                    return lhs.schedule.nextDueAt < rhs.schedule.nextDueAt
                }
                return lhs.nodeID < rhs.nodeID
            }
    }

    /// Ties are broken by ID so two devices holding the same events in a
    /// different local order fold to the same result.
    static func chronological(_ events: [TrainingEvent]) -> [TrainingEvent] {
        events.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func isPass(_ quality: DecisionQuality) -> Bool {
        !isError(quality)
    }

    private static func advance(from date: Date, rung: Int) -> Date {
        date.addingTimeInterval(TimeInterval(ladderDays[rung]) * 86_400)
    }

    static func isError(_ quality: DecisionQuality) -> Bool {
        quality == .improvable || quality == .blunder
    }
}
