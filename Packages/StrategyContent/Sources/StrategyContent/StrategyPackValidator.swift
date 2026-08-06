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

        if pack.manifest.reviewStatus == .reviewed,
           pack.manifest.reviewedAt == nil {
            throw StrategyPackValidationError.missingReviewedAt
        }

        guard !pack.scenarios.isEmpty else {
            throw StrategyPackValidationError.emptyScenarios
        }

        var scenarioIDs: Set<String> = []
        for scenario in pack.scenarios {
            guard scenarioIDs.insert(scenario.id).inserted else {
                throw StrategyPackValidationError.duplicateScenarioID(scenario.id)
            }

            try validateCards(in: scenario)
            try validateOptions(in: scenario)
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
