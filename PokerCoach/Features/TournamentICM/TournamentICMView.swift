import SwiftUI

/// A content-free tournament ICM calculator: enter chip stacks and a payout
/// structure, see each seat's ICM equity and, optionally, the bubble factor
/// between two seats. It is an analysis tool, not training — no ranges, no
/// recommendations, no scoring.
///
/// Accessibility identifiers are namespaced `icm.*` on leaf elements, matching
/// the app's UI-test convention.
struct TournamentICMView: View {
    @State private var viewModel = TournamentICMViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("输入各家筹码与派彩结构，计算每家的 ICM 权益（按 Malmuth-Harville 模型）。这是分析工具，不含打法建议。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                field(title: "各家筹码（逗号分隔）", text: $viewModel.stacksInput, identifier: "icm.stacks")
                field(title: "派彩结构（逗号分隔，第 1 名起）", text: $viewModel.payoutsInput, identifier: "icm.payouts")

                Text("可选：填入英雄与对手座位编号，计算两者间泡沫系数。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    field(title: "英雄座位", text: $viewModel.heroSeatInput, identifier: "icm.hero")
                    field(title: "对手座位", text: $viewModel.opponentSeatInput, identifier: "icm.opponent")
                }

                ActionButton(
                    title: "计算",
                    isSelected: true,
                    accessibilityIdentifier: "icm.compute",
                    action: viewModel.compute
                )

                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("icm.error")
                }

                if !viewModel.equityLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ICM 权益")
                            .font(.headline)
                        ForEach(Array(viewModel.equityLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .accessibilityIdentifier("icm.equity.\(index)")
                        }
                    }
                }

                if let bubbleFactorText = viewModel.bubbleFactorText {
                    LabeledContent("泡沫系数", value: bubbleFactorText)
                        .accessibilityIdentifier("icm.bubbleFactor")
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("锦标赛 ICM 计算器")
    }

    private func field(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
        }
    }
}
