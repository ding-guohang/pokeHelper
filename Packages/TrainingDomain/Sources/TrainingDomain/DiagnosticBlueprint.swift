import Foundation
import StrategyContent

/// Which street a scenario is decided on, derived from the board rather than
/// stored: the content model already fixes the board, and a second field could
/// disagree with it.
public enum TrainingStreet: String, Sendable, Codable, CaseIterable {
    case preflop
    case flop
    case turn
    case river

    public init?(boardCardCount: Int) {
        switch boardCardCount {
        case 0: self = .preflop
        case 3: self = .flop
        case 4: self = .turn
        case 5: self = .river
        default: return nil
        }
    }
}

/// One question in the initial diagnostic, with the axes the blueprint samples
/// on exposed so coverage is checkable.
public struct DiagnosticQuestion: Sendable, Equatable, Identifiable {
    public let scenarioID: String
    public let abilityDimension: String
    public let curriculumNodeID: String
    public let heroSeatOffsetFromButton: Int
    public let street: TrainingStreet
    public let effectiveStackCentiBB: Int

    public var id: String { scenarioID }
}

/// The sampling plan for the initial diagnostic.
///
/// It declares the ability dimensions it covers and how many questions to ask,
/// so "the profile covers every dimension the diagnostic sampled" is a claim
/// about a stated set rather than about whatever the implementation happened to
/// pick.
public struct DiagnosticBlueprint: Sendable {
    public let dimensions: Set<String>
    public let questionCount: Int

    public init(dimensions: Set<String>, questionCount: Int) {
        self.dimensions = dimensions
        self.questionCount = questionCount
    }

    public static let cash6MaxDefault = DiagnosticBlueprint(
        dimensions: ["preflop-range", "flop-cbet", "turn-barrel", "river-bluff-catch"],
        questionCount: 12
    )

    /// Chooses questions that spread across dimensions first and across
    /// position, street and stack depth second.
    ///
    /// Deterministic: two devices holding the same pack must offer the same
    /// diagnostic, or resuming an interrupted session would not line up with
    /// the session it resumes.
    public func draw(from pack: StrategyPack) -> [DiagnosticQuestion] {
        var remaining = pack.scenarios
            .compactMap(Self.question)
            .filter { dimensions.contains($0.abilityDimension) }
            .sorted { $0.scenarioID < $1.scenarioID }

        var selected: [DiagnosticQuestion] = []
        var picksPerDimension: [String: Int] = [:]
        var seats: Set<Int> = []
        var streets: Set<TrainingStreet> = []
        var stacks: Set<Int> = []

        while selected.count < questionCount, !remaining.isEmpty {
            // Dimension balance comes first so no declared dimension can be
            // crowded out by another that happens to add more new axes.
            let index = Self.bestCandidateIndex(
                in: remaining,
                picksPerDimension: picksPerDimension,
                seats: seats,
                streets: streets,
                stacks: stacks
            )
            let question = remaining.remove(at: index)

            selected.append(question)
            picksPerDimension[question.abilityDimension, default: 0] += 1
            seats.insert(question.heroSeatOffsetFromButton)
            streets.insert(question.street)
            stacks.insert(question.effectiveStackCentiBB)
        }
        return selected
    }

    private static func bestCandidateIndex(
        in candidates: [DiagnosticQuestion],
        picksPerDimension: [String: Int],
        seats: Set<Int>,
        streets: Set<TrainingStreet>,
        stacks: Set<Int>
    ) -> Int {
        var bestIndex = 0
        var bestKey = key(
            for: candidates[0],
            picksPerDimension: picksPerDimension,
            seats: seats,
            streets: streets,
            stacks: stacks
        )

        for index in candidates.indices.dropFirst() {
            let candidateKey = key(
                for: candidates[index],
                picksPerDimension: picksPerDimension,
                seats: seats,
                streets: streets,
                stacks: stacks
            )
            if candidateKey < bestKey {
                bestIndex = index
                bestKey = candidateKey
            }
        }
        return bestIndex
    }

    /// Lower sorts better: fewest picks in its dimension, then most new axes,
    /// then scenario ID. The candidate list is already ID-sorted, so the final
    /// component only ever settles exact ties.
    private static func key(
        for question: DiagnosticQuestion,
        picksPerDimension: [String: Int],
        seats: Set<Int>,
        streets: Set<TrainingStreet>,
        stacks: Set<Int>
    ) -> (Int, Int, String) {
        let newAxes = (seats.contains(question.heroSeatOffsetFromButton) ? 0 : 1)
            + (streets.contains(question.street) ? 0 : 1)
            + (stacks.contains(question.effectiveStackCentiBB) ? 0 : 1)

        return (
            picksPerDimension[question.abilityDimension] ?? 0,
            -newAxes,
            question.scenarioID
        )
    }

    private static func question(from scenario: DecisionScenario) -> DiagnosticQuestion? {
        guard let street = TrainingStreet(boardCardCount: scenario.board.count) else {
            return nil
        }
        return DiagnosticQuestion(
            scenarioID: scenario.id,
            abilityDimension: scenario.abilityDimension,
            curriculumNodeID: scenario.curriculumNodeID,
            heroSeatOffsetFromButton: scenario.heroSeatOffsetFromButton,
            street: street,
            effectiveStackCentiBB: scenario.assumptions.effectiveStack.centiBB
        )
    }
}

/// A diagnostic run and how far through it the user is.
///
/// Progress is derived from which scenario IDs the event history already
/// contains, so an interrupted diagnostic resumes without persisting anything
/// of its own.
public struct DiagnosticSession: Sendable, Equatable {
    public let questions: [DiagnosticQuestion]
    public let remaining: [DiagnosticQuestion]

    public var totalCount: Int { questions.count }
    public var completedCount: Int { questions.count - remaining.count }
    public var isComplete: Bool { remaining.isEmpty }

    public init(blueprint: DiagnosticBlueprint, pack: StrategyPack) {
        let drawn = blueprint.draw(from: pack)
        questions = drawn
        remaining = drawn
    }

    private init(questions: [DiagnosticQuestion], remaining: [DiagnosticQuestion]) {
        self.questions = questions
        self.remaining = remaining
    }

    public func resuming(answeredScenarioIDs: Set<String>) -> DiagnosticSession {
        DiagnosticSession(
            questions: questions,
            remaining: questions.filter { !answeredScenarioIDs.contains($0.scenarioID) }
        )
    }
}
