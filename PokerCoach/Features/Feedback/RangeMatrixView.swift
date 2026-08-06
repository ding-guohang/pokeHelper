import SwiftUI

struct RangeMatrixView: View {
    let cells: [FeedbackRangeCell]

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("范围与组合权重", systemImage: "square.grid.3x3")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(cells) { cell in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cell.handClass)
                            .font(.headline)

                        ForEach(cell.actionWeights) { weight in
                            HStack {
                                Text(weight.actionTitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(weight.weightText)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                }
            }
        }
        .accessibilityIdentifier("feedback.rangeMatrix")
    }
}
