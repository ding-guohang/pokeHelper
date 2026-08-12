import Foundation
import Observation
import StrategyContent
import TrainingDomain

/// One row of the curriculum tree.
struct CurriculumNodePresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let prerequisiteTitles: [String]
    let practisableScenarioCount: Int
    let mastery: NodeMastery

    /// A node the installed content has no scenarios for. It is shown so the
    /// tree stays a map of the subject rather than of this month's content, but
    /// it cannot be trained and must not drag the progress denominator down.
    var isContentUnavailable: Bool { practisableScenarioCount == 0 }

    /// A node with too few scenarios to demonstrate transfer.
    ///
    /// Mastery over a single scenario is memorising one hand, not learning the
    /// spot, so such a node is reported as content-limited rather than being
    /// counted — either as masterable or as a permanent shortfall.
    var hasInsufficientContentForMastery: Bool {
        practisableScenarioCount < MasteryEvaluator.transferRequirement
    }

    var isMastered: Bool { mastery.isMastered }
}

/// One row of the mastery detail table.
struct MasterySignalRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let satisfied: Bool
}

struct CurriculumNodeDetail: Equatable {
    let nodeID: String
    let title: String
    let signalRows: [MasterySignalRow]
}

@MainActor
@Observable
final class LearnViewModel {
    private(set) var nodes: [CurriculumNodePresentation] = []
    let strategyContentAvailability: StrategyContentAvailability

    /// Nodes that count toward "how much of the tree is mastered". Nodes with
    /// no content are excluded: leaving them in would make the number fall
    /// whenever content ships without them, which reads as regression.
    var masteryProgressDenominator: Int {
        nodes.count { !$0.hasInsufficientContentForMastery }
    }

    var masteredCount: Int {
        nodes.count { !$0.hasInsufficientContentForMastery && $0.isMastered }
    }

    private let pack: StrategyPack
    private let events: [TrainingEvent]
    private let evaluator = MasteryEvaluator()

    init(
        pack: StrategyPack,
        events: [TrainingEvent],
        strategyContentAvailability: StrategyContentAvailability
    ) {
        self.pack = pack
        self.events = events
        self.strategyContentAvailability = strategyContentAvailability
    }

    func refresh() {
        let titlesByID = Dictionary(
            pack.curriculum.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let scenarioCounts = pack.scenarios.reduce(into: [String: Int]()) {
            $0[$1.curriculumNodeID, default: 0] += 1
        }

        nodes = pack.curriculum.map { node in
            CurriculumNodePresentation(
                id: node.id,
                title: node.title,
                prerequisiteTitles: node.prerequisiteNodeIDs.map {
                    titlesByID[$0] ?? $0
                },
                practisableScenarioCount: scenarioCounts[node.id] ?? 0,
                // Mastery is computed by the domain, never by this type:
                // layering.md forbids a ViewModel deriving domain truth.
                mastery: evaluator.evaluate(
                    nodeID: node.id,
                    events: events,
                    pack: pack
                )
            )
        }
    }

    func detail(forNode nodeID: String) -> CurriculumNodeDetail? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else {
            return nil
        }
        return CurriculumNodeDetail(
            nodeID: node.id,
            title: node.title,
            signalRows: node.mastery.signals.map(Self.row)
        )
    }

    private static func row(for signal: MasterySignal) -> MasterySignalRow {
        MasterySignalRow(
            id: signal.kind.rawValue,
            label: label(for: signal.kind),
            // Calibration's requirement is "every very-sure answer passed", so
            // a bare count reads better there than a ratio against zero.
            value: signal.kind == .confidenceCalibration && signal.required == 0
                ? "无高信心作答"
                : "\(signal.actual)/\(signal.required)",
            satisfied: signal.satisfied
        )
    }

    private static func label(for kind: MasterySignal.Kind) -> String {
        switch kind {
        case .sample: "样本"
        case .recentStability: "近期稳定性"
        case .confidenceCalibration: "信心校准"
        case .repetition: "复练"
        case .transfer: "迁移"
        }
    }
}
