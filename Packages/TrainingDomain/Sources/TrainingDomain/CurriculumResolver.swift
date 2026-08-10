import Foundation
import StrategyContent

/// Where a training event belongs in the curriculum.
///
/// An event records the pack and content version it was answered under. When
/// that content is not the one installed, its scenario may not exist locally at
/// all, so node membership cannot be established. Dropping the event would
/// shrink the user's history every time content upgrades, so it keeps
/// contributing to its ability dimension and is excluded only from node-level
/// mastery — where attributing it to the wrong node would be worse than not
/// counting it.
public enum CurriculumResolution: Sendable, Equatable {
    case node(String)
    case dimensionOnly(String)

    public var countsTowardMastery: Bool {
        if case .node = self { return true }
        return false
    }

    /// The node when one could be established, otherwise the dimension the
    /// event itself recorded.
    public var abilityDimension: String {
        switch self {
        case let .node(nodeID): nodeID
        case let .dimensionOnly(dimension): dimension
        }
    }
}

/// Maps training events onto curriculum nodes through the content they were
/// answered against.
///
/// The node lives on the scenario, not on the event, so `TrainingEvent` and the
/// cross-language upload contract in `Contracts/` stay untouched.
public struct CurriculumResolver: Sendable {
    private let packID: String
    private let contentVersion: String
    private let nodeByScenarioID: [String: String]

    public init(pack: StrategyPack) {
        packID = pack.manifest.id
        contentVersion = pack.manifest.contentVersion
        nodeByScenarioID = Dictionary(
            pack.scenarios.map { ($0.id, $0.curriculumNodeID) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func resolve(_ event: TrainingEvent) -> CurriculumResolution {
        guard event.strategyPackID == packID,
              event.strategyContentVersion == contentVersion,
              let nodeID = nodeByScenarioID[event.scenarioID]
        else {
            return .dimensionOnly(event.abilityDimension)
        }
        return .node(nodeID)
    }

    /// Events grouped by node, in their original order, excluding any whose
    /// node could not be established.
    public func eventsByNode(_ events: [TrainingEvent]) -> [String: [TrainingEvent]] {
        var grouped: [String: [TrainingEvent]] = [:]
        for event in events {
            guard case let .node(nodeID) = resolve(event) else {
                continue
            }
            grouped[nodeID, default: []].append(event)
        }
        return grouped
    }
}
