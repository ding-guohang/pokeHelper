import Foundation
import PokerCore
import StrategyContent
import TrainingDomain

struct FeedbackFrequencyRow: Identifiable, Equatable {
    let id: String
    let actionTitle: String
    let frequencyText: String
    let evText: String
    let isSelected: Bool
}

struct FeedbackActionWeight: Identifiable, Equatable {
    let id: String
    let actionTitle: String
    let weightText: String
}

struct FeedbackRangeCell: Identifiable, Equatable {
    var id: String { handClass }

    let handClass: String
    let actionWeights: [FeedbackActionWeight]
}

struct FeedbackReasoningSection: Identifiable, Equatable {
    let id: String
    let question: String
    let answer: String
}

struct FeedbackPresentation {
    let frequencyRows: [FeedbackFrequencyRow]
    let evLossText: String
    let qualityText: String
    let scoreText: String
    let confidenceText: String
    let confidenceCalibrationText: String
    let selectedActionText: String
    let selectedEVText: String
    let bestEVText: String
    let conclusion: String
    let rangeCells: [FeedbackRangeCell]
    let reasoningSections: [FeedbackReasoningSection]
    let gtoBaseline: String
    let exploitAdjustment: String?
    let assumptions: String
    let stackText: String
    let rakeText: String
    let betSizeTreeText: String
    let generatedSource: String
    let contentVersion: String
    let reviewStatusText: String
    let provenanceBadge: String

    init(
        scenario: DecisionScenario,
        submission: DecisionSubmission,
        grade: DecisionGrade
    ) {
        self.init(
            scenario: scenario,
            submission: submission,
            grade: grade,
            manifest: nil
        )
    }

    init(
        scenario: DecisionScenario,
        submission: DecisionSubmission,
        grade: DecisionGrade,
        manifest: StrategyPackManifest?
    ) {
        let rows = scenario.options.map { option in
            FeedbackFrequencyRow(
                id: option.action.stableID,
                actionTitle: option.action.displayTitle,
                frequencyText: Self.frequencyText(
                    basisPoints: option.frequencyBasisPoints
                ),
                evText: Self.evText(option.ev),
                isSelected: option.action == submission.action
            )
        }
        frequencyRows = rows
        evLossText = Self.lossText(grade.evLoss)
        qualityText = switch grade.quality {
        case .excellent:
            "优秀"
        case .acceptable:
            "可接受"
        case .improvable:
            "可改进"
        case .blunder:
            "严重失误"
        }
        scoreText = "\(grade.score) / 100"
        confidenceText = "信心：\(Self.confidenceTitle(submission.confidence))"
        confidenceCalibrationText = Self.confidenceCalibrationText(
            confidence: submission.confidence,
            quality: grade.quality
        )
        selectedActionText = "所选：\(submission.action.displayTitle)"
        selectedEVText = Self.evText(grade.selectedEV)
        bestEVText = Self.evText(grade.bestEV)
        conclusion = scenario.explanation.conclusion
        rangeCells = scenario.rangeCells.map { cell in
            FeedbackRangeCell(
                handClass: cell.handClass,
                actionWeights: cell.actionWeightsBasisPoints.keys.sorted()
                    .map { actionID in
                        FeedbackActionWeight(
                            id: actionID,
                            actionTitle: rows.first(where: {
                                $0.id == actionID
                            })?.actionTitle ?? actionID,
                            weightText: Self.frequencyText(
                                basisPoints:
                                    cell.actionWeightsBasisPoints[actionID] ?? 0
                            )
                        )
                    }
            )
        }
        reasoningSections = [
            FeedbackReasoningSection(
                id: "range",
                question: "我的范围是什么？",
                answer: scenario.explanation.rangeReasoning
            ),
            FeedbackReasoningSection(
                id: "board",
                question: "牌面如何影响策略？",
                answer: scenario.explanation.boardReasoning
            ),
            FeedbackReasoningSection(
                id: "opponent",
                question: "对手范围是什么？",
                answer: scenario.explanation.opponentReasoning
            ),
            FeedbackReasoningSection(
                id: "future",
                question: "未来计划是什么？",
                answer: scenario.explanation.futurePlan
            )
        ]
        gtoBaseline = scenario.explanation.gtoBaseline
        exploitAdjustment = scenario.explanation.exploitCondition.flatMap {
            let condition = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return condition.isEmpty ? nil : condition
        }
        assumptions = [
            scenario.assumptions.gameType,
            "\(scenario.assumptions.tableSize)人桌",
            Self.compactBBText(scenario.assumptions.effectiveStack)
        ].joined(separator: " · ")
        stackText = scenario.assumptions.effectiveStack.displayText
        rakeText = scenario.assumptions.rakeDescription
        betSizeTreeText = scenario.assumptions.allowedBetSizeDescription
        generatedSource = manifest?.generatedSource ?? "来源未提供"
        contentVersion = manifest?.contentVersion ?? "未知版本"
        reviewStatusText = switch manifest?.reviewStatus {
        case .testFixture:
            "开发/未审核"
        case .reviewed:
            "已审核"
        case .retired:
            "已停用"
        case nil:
            "审核状态未知"
        }
        provenanceBadge = switch manifest?.reviewStatus {
        case .testFixture:
            "开发演示数据"
        case .reviewed:
            "已审核 · \(manifest?.contentVersion ?? "")"
        case .retired:
            "已停用 · \(manifest?.contentVersion ?? "")"
        case nil:
            "来源未提供"
        }
    }

    private static func evText(_ amount: EVAmount) -> String {
        let sign: String
        if amount.milliBB < 0 {
            sign = "−"
        } else {
            sign = ""
        }
        let magnitude = amount.milliBB.magnitude
        let whole = magnitude / 1_000
        let fractional = magnitude % 1_000
        return "\(sign)\(whole).\(String(format: "%03llu", fractional)) BB"
    }

    private static func lossText(_ amount: EVAmount) -> String {
        guard amount.milliBB != 0 else {
            return evText(amount)
        }
        return "−\(evText(amount))"
    }

    private static func frequencyText(basisPoints: Int) -> String {
        let tenthsOfPercent = (basisPoints + 5) / 10
        return "\(tenthsOfPercent / 10).\(tenthsOfPercent % 10)%"
    }

    private static func compactBBText(_ amount: BBAmount) -> String {
        let whole = amount.centiBB / 100
        let remainder = amount.centiBB % 100
        if remainder == 0 {
            return "\(whole)BB"
        }
        if remainder % 10 == 0 {
            return "\(whole).\(remainder / 10)BB"
        }
        return "\(whole).\(String(format: "%02d", remainder))BB"
    }

    private static func confidenceTitle(
        _ confidence: DecisionConfidence
    ) -> String {
        switch confidence {
        case .guessing:
            "猜测"
        case .unsure:
            "不确定"
        case .verySure:
            "很确定"
        }
    }

    private static func confidenceCalibrationText(
        confidence: DecisionConfidence,
        quality: DecisionQuality
    ) -> String {
        switch (confidence, quality) {
        case (.verySure, .improvable), (.verySure, .blunder):
            "高信心失误，需要重点复盘"
        case (.guessing, .excellent), (.guessing, .acceptable):
            "结果可接受，但信心不足"
        case (.unsure, _):
            "当前不确定性已保留，请结合证据校准"
        default:
            "信心与本次决策质量基本一致"
        }
    }
}
