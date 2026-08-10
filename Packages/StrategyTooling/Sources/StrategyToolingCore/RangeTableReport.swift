import Foundation
import PokerCore

/// Renders the range tables of an export as text for human review.
///
/// This is what the owner reads before signing a pack off as `reviewed`. The
/// unit of review is the range table, not the individual question: a chart can
/// be checked at a glance, two hundred scenarios cannot.
public struct RangeTableReport: Sendable {
    public init() {}

    public func render(_ export: SolverExport) -> String {
        var lines: [String] = [
            "策略包：\(export.packID)",
            "来源：\(export.generatedSource)",
            "牌桌：\(export.gameType) · \(export.tableSize) 人 · "
                + "有效筹码 \(export.effectiveStack.centiBB / 100)BB",
            "抽水：\(export.rakeDescription)",
            "允许尺度：\(export.allowedBetSizeDescription)",
            "",
        ]

        for node in export.nodes {
            let heroHand = ContentAudit.handClass(for: node.heroCards) ?? "?"

            // For a node answering a raise, the meaningful denominator is the
            // range that actually reached it, not all 1,326 starting hands.
            // Reporting the latter understates defence by a factor of four and
            // hides whether the minimum defence frequency is met.
            let opening = node.facingRaiseTo == nil ? nil : export.nodes.first {
                $0.curriculumNodeID == "preflop-rfi"
                    && $0.heroSeatOffsetFromButton == node.heroSeatOffsetFromButton
            }
            let rangeWide = opening.map {
                ContentAudit.continuationBasisPoints(
                    facing: node.rangeCells,
                    openedWith: $0.rangeCells
                )
            } ?? ContentAudit.combinationWeightedBasisPoints(node.rangeCells)
            let rangeWideLabel = opening == nil
                ? "整段范围加权开池率"
                : "开池范围中的继续率"

            lines.append("── \(node.id) · \(node.title)")
            lines.append("   能力节点：\(node.curriculumNodeID)")
            lines.append("   位置：按钮位后第 \(node.heroSeatOffsetFromButton) 座")
            lines.append(
                "   英雄手牌：\(node.heroCards.joined(separator: " "))（\(heroHand)）"
            )
            lines.append(
                "   \(rangeWideLabel)："
                    + String(format: "%.2f%%", Double(rangeWide) / 100)
            )
            if let facingRaiseTo = node.facingRaiseTo {
                let risked = facingRaiseTo.centiBB
                let attacked = node.pot.centiBB - risked
                let minimum = attacked * 10_000 / (risked + attacked)
                lines.append(
                    "   面对加注至 \(Self.bb(risked))，最小防守频率 "
                        + String(format: "%.2f%%", Double(minimum) / 100)
                )
            }
            // Labelled as the hero's hand, not the range. The previous wording
            // read "行动频率" beside a 100% raise, which looks like a claim
            // about the whole opening range rather than about AKo.
            lines.append("   \(heroHand) 这手牌的行动频率：")
            for action in node.actions {
                let percent = Double(action.frequencyBasisPoints) / 100
                var label = Self.describe(action.action)
                if case .call = action.action, let facing = node.facingRaiseTo {
                    label += "（总投入至 \(Self.bb(facing.centiBB))）"
                }
                lines.append(
                    "     \(label)  "
                        + String(format: "%.2f%%", percent)
                        + "  EV \(Self.describeEV(action.ev.milliBB))"
                )
            }
            lines.append("   范围表：")
            // Sorted so two runs of the report read identically; the reviewer
            // compares revisions by eye.
            for cell in node.rangeCells.sorted(by: { $0.handClass < $1.handClass }) {
                let weights = cell.actionWeightsBasisPoints
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) \(String(format: "%.2f%%", Double($0.value) / 100))" }
                    .joined(separator: "  ")
                // Pad without truncating: padding(toLength:) shortens anything
                // longer than the target, which silently rewrote "AKo-AQo" as
                // "AKo-AQ" — a different range.
                let label = cell.handClass.count >= 8
                    ? cell.handClass
                    : cell.handClass + String(repeating: " ", count: 8 - cell.handClass.count)
                lines.append("     \(label) \(weights)")
            }
            lines.append("")
        }

        lines.append("审核提示：确认每张范围表的行动与频率符合你的策略判断。")
        lines.append("确认后用 --review-status reviewed --reviewed-by <你的名字> 重新导入。")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "弃牌"
        case .check: "过牌"
        // The associated value of a call is what is owed, not a target total:
        // legalActions() builds it as .call(to: amountToCall).
        case let .call(to): "补跟 \(bb(to.centiBB))"
        case let .bet(to): "下注至 \(bb(to.centiBB))"
        case let .raise(to): "加注至 \(bb(to.centiBB))"
        case let .allIn(to): "全下至 \(bb(to.centiBB))"
        }
    }

    private static func bb(_ centiBB: Int) -> String {
        "\(centiBB / 100).\(String(format: "%02d", centiBB % 100))BB"
    }

    private static func describeEV(_ milliBB: Int) -> String {
        let sign = milliBB < 0 ? "−" : ""
        let magnitude = abs(milliBB)
        return "\(sign)\(magnitude / 1_000).\(String(format: "%03d", magnitude % 1_000))BB"
    }
}
