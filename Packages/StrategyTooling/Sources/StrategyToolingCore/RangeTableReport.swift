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
            lines.append("── \(node.id) · \(node.title)")
            lines.append("   能力节点：\(node.curriculumNodeID)")
            lines.append("   位置：按钮位后第 \(node.heroSeatOffsetFromButton) 座")
            lines.append("   行动频率：")
            for action in node.actions {
                let percent = Double(action.frequencyBasisPoints) / 100
                lines.append(
                    "     \(Self.describe(action.action))  "
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
        case let .call(to): "跟注至 \(bb(to.centiBB))"
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
