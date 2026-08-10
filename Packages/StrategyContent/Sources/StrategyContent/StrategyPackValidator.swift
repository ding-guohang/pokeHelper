import Foundation
import PokerCore

public struct StrategyPackValidator: Sendable {
    public init() {}

    public func validate(_ pack: StrategyPack) throws {
        guard pack.manifest.schemaVersion == 1 else {
            throw StrategyPackValidationError.unsupportedSchemaVersion(
                pack.manifest.schemaVersion
            )
        }

        guard !pack.manifest.generatedSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else {
            throw StrategyPackValidationError.emptyGeneratedSource
        }

        if pack.manifest.reviewStatus == .reviewed {
            guard pack.manifest.reviewedAt != nil else {
                throw StrategyPackValidationError.missingReviewedAt
            }
            // A blank reviewer makes the same claim as a missing one, and is
            // what an automated step would leave behind if it filled the field
            // only to get past this check.
            guard let reviewedBy = pack.manifest.reviewedBy,
                  !reviewedBy
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                      .isEmpty
            else {
                throw StrategyPackValidationError.missingReviewedBy
            }
        }

        guard !pack.scenarios.isEmpty else {
            throw StrategyPackValidationError.emptyScenarios
        }

        try validateCurriculum(pack)

        var scenarioIDs: Set<String> = []
        for scenario in pack.scenarios {
            guard scenarioIDs.insert(scenario.id).inserted else {
                throw StrategyPackValidationError.duplicateScenarioID(scenario.id)
            }

            try validatePosition(in: scenario)
            try validateCards(in: scenario)
            try validateOptions(in: scenario)
        }
    }

    private func validateCurriculum(_ pack: StrategyPack) throws {
        var nodesByID: [String: CurriculumNode] = [:]
        for node in pack.curriculum {
            guard nodesByID.updateValue(node, forKey: node.id) == nil else {
                throw StrategyPackValidationError.duplicateCurriculumNodeID(node.id)
            }
        }

        for scenario in pack.scenarios
            where nodesByID[scenario.curriculumNodeID] == nil
        {
            throw StrategyPackValidationError.unknownCurriculumNode(
                scenarioID: scenario.id,
                nodeID: scenario.curriculumNodeID
            )
        }

        for node in pack.curriculum {
            for prerequisiteID in node.prerequisiteNodeIDs
                where nodesByID[prerequisiteID] == nil
            {
                throw StrategyPackValidationError.unknownPrerequisite(
                    nodeID: node.id,
                    prerequisiteID: prerequisiteID
                )
            }
        }

        if let cycle = Self.firstCycle(in: nodesByID) {
            throw StrategyPackValidationError.cyclicCurriculum(nodeIDs: cycle)
        }
    }

    /// Returns the sorted IDs of one prerequisite cycle, or nil when the tree
    /// is acyclic.
    ///
    /// The search is iterative rather than recursive so a deep tree cannot
    /// overflow the stack, and it tracks the current path separately from the
    /// finished set: a node reachable by two different paths (a diamond) is
    /// revisited legitimately and must not be reported as a cycle.
    private static func firstCycle(
        in nodesByID: [String: CurriculumNode]
    ) -> [String]? {
        var finished: Set<String> = []

        for start in nodesByID.keys.sorted() where !finished.contains(start) {
            var onPath: Set<String> = [start]
            var stack: [(id: String, remaining: ArraySlice<String>)] = [
                (start, ArraySlice(nodesByID[start]?.prerequisiteNodeIDs ?? [])),
            ]

            while var frame = stack.popLast() {
                guard let next = frame.remaining.popFirst() else {
                    onPath.remove(frame.id)
                    finished.insert(frame.id)
                    continue
                }
                stack.append(frame)

                if onPath.contains(next) {
                    return onPath.sorted()
                }
                if finished.contains(next) {
                    continue
                }
                onPath.insert(next)
                stack.append(
                    (next, ArraySlice(nodesByID[next]?.prerequisiteNodeIDs ?? []))
                )
            }
        }
        return nil
    }

    private func validatePosition(in scenario: DecisionScenario) throws {
        do {
            _ = try TablePosition(
                tableSize: scenario.assumptions.tableSize,
                heroSeatOffsetFromButton:
                    scenario.heroSeatOffsetFromButton
            )
        } catch let error {
            switch error {
            case let .invalidTableSize(tableSize):
                throw StrategyPackValidationError.invalidTableSize(
                    scenarioID: scenario.id,
                    tableSize: tableSize
                )
            case let .invalidHeroSeatOffset(
                tableSize,
                heroSeatOffsetFromButton
            ):
                throw StrategyPackValidationError.invalidHeroSeatOffset(
                    scenarioID: scenario.id,
                    tableSize: tableSize,
                    heroSeatOffsetFromButton: heroSeatOffsetFromButton
                )
            }
        }
    }

    private func validateCards(in scenario: DecisionScenario) throws {
        var cardCodes: Set<String> = []

        for card in scenario.heroCards + scenario.board {
            guard cardCodes.insert(card.code).inserted else {
                throw StrategyPackValidationError.duplicateCard(card.code)
            }
        }
    }

    private func validateOptions(in scenario: DecisionScenario) throws {
        var frequencyTotal = 0
        for option in scenario.options {
            let frequency = option.frequencyBasisPoints
            guard (0...10_000).contains(frequency) else {
                throw StrategyPackValidationError.invalidFrequencyTotal(
                    scenarioID: scenario.id,
                    actual: frequency
                )
            }

            let (updatedTotal, overflowed) = frequencyTotal.addingReportingOverflow(
                frequency
            )
            guard !overflowed else {
                throw StrategyPackValidationError.invalidFrequencyTotal(
                    scenarioID: scenario.id,
                    actual: Int.max
                )
            }
            frequencyTotal = updatedTotal
        }

        guard frequencyTotal == 10_000 else {
            throw StrategyPackValidationError.invalidFrequencyTotal(
                scenarioID: scenario.id,
                actual: frequencyTotal
            )
        }

        let legalActions = scenario.decision.legalActions()
        var actions: Set<DecisionAction> = []

        for option in scenario.options {
            guard legalActions.contains(option.action) else {
                throw StrategyPackValidationError.illegalAction(
                    scenarioID: scenario.id
                )
            }

            guard actions.insert(option.action).inserted else {
                throw StrategyPackValidationError.duplicateAction(
                    scenarioID: scenario.id
                )
            }
        }
    }
}
