import Foundation
import PokerCore
import StrategyContent
import TrainingDomain

/// One (scenario, submission) pair whose grade must stay stable across a
/// content upgrade.
public struct GoldenCase: Codable, Sendable, Equatable {
    public let scenarioID: String
    public let submission: DecisionSubmission

    public init(scenarioID: String, submission: DecisionSubmission) {
        self.scenarioID = scenarioID
        self.submission = submission
    }
}

public struct GoldenChange: Sendable, Equatable {
    public let scenarioID: String
    public let oldLossRateBasisPoints: Int
    public let newLossRateBasisPoints: Int
    public let oldQuality: DecisionQuality
    public let newQuality: DecisionQuality

    public var deltaBasisPoints: Int {
        newLossRateBasisPoints - oldLossRateBasisPoints
    }

    public var crossesQualityBoundary: Bool {
        oldQuality != newQuality
    }
}

public struct GoldenReport: Sendable {
    public let changes: [GoldenChange]
    public let missingScenarioIDs: [String]
    public let toleranceBasisPoints: Int

    public var exitCode: Int32 {
        guard missingScenarioIDs.isEmpty else { return 1 }
        let breached = changes.contains {
            $0.crossesQualityBoundary
                || abs($0.deltaBasisPoints) > toleranceBasisPoints
        }
        return breached ? 1 : 0
    }
}

public enum GoldenRegressionError: Error, Equatable {
    case scenarioMissingFromBaseline(String)
    case ungradableCase(scenarioID: String)
}

/// Compares how a fixed set of submissions grades before and after a content
/// upgrade, as `docs/standards/strategy-content.md` requires of every upgrade.
public struct GoldenRegression: Sendable {
    public init() {}

    public func compare(
        old: StrategyPack,
        new: StrategyPack,
        cases: [GoldenCase],
        toleranceBasisPoints: Int
    ) throws -> GoldenReport {
        let oldScenarios = Dictionary(
            uniqueKeysWithValues: old.scenarios.map { ($0.id, $0) }
        )
        let newScenarios = Dictionary(
            uniqueKeysWithValues: new.scenarios.map { ($0.id, $0) }
        )
        let scorer = DecisionScorer()

        var changes: [GoldenChange] = []
        var missing: [String] = []

        for goldenCase in cases {
            guard let oldScenario = oldScenarios[goldenCase.scenarioID] else {
                throw GoldenRegressionError.scenarioMissingFromBaseline(
                    goldenCase.scenarioID
                )
            }
            // Losing a scenario is reported, not thrown: the run should still
            // grade everything else so one removal does not hide the rest.
            guard let newScenario = newScenarios[goldenCase.scenarioID] else {
                missing.append(goldenCase.scenarioID)
                continue
            }

            let oldGrade = try grade(scorer, goldenCase, oldScenario)
            let newGrade = try grade(scorer, goldenCase, newScenario)

            changes.append(
                GoldenChange(
                    scenarioID: goldenCase.scenarioID,
                    oldLossRateBasisPoints: oldGrade.lossRateBasisPoints,
                    newLossRateBasisPoints: newGrade.lossRateBasisPoints,
                    oldQuality: oldGrade.quality,
                    newQuality: newGrade.quality
                )
            )
        }

        return GoldenReport(
            changes: changes,
            missingScenarioIDs: missing,
            toleranceBasisPoints: toleranceBasisPoints
        )
    }

    /// Renders every case, not only the breaching ones.
    ///
    /// A report that prints only failures cannot distinguish "nothing moved"
    /// from "moved but stayed inside tolerance", which turns an upgrade into a
    /// black box for the person signing it off.
    public func render(_ report: GoldenReport) -> String {
        var lines = ["黄金回归：\(report.changes.count) 个用例，容差 \(report.toleranceBasisPoints) bp"]

        for change in report.changes {
            let marker = change.crossesQualityBoundary
                ? "跨越等级"
                : (abs(change.deltaBasisPoints) > report.toleranceBasisPoints
                    ? "超出容差"
                    : "在容差内")
            lines.append(
                "  \(change.scenarioID)  "
                    + "\(change.oldLossRateBasisPoints) → \(change.newLossRateBasisPoints) bp "
                    + "(Δ\(change.deltaBasisPoints))  "
                    + "\(change.oldQuality.rawValue) → \(change.newQuality.rawValue)  "
                    + marker
            )
        }
        for scenarioID in report.missingScenarioIDs {
            lines.append("  \(scenarioID)  新包中不存在")
        }
        lines.append(report.exitCode == 0 ? "结果：通过" : "结果：失败")
        return lines.joined(separator: "\n")
    }

    private func grade(
        _ scorer: DecisionScorer,
        _ goldenCase: GoldenCase,
        _ scenario: DecisionScenario
    ) throws -> DecisionGrade {
        do {
            return try scorer.grade(
                submission: goldenCase.submission,
                scenario: scenario
            )
        } catch {
            throw GoldenRegressionError.ungradableCase(
                scenarioID: goldenCase.scenarioID
            )
        }
    }
}
