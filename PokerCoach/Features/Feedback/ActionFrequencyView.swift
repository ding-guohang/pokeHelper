import SwiftUI

struct ActionFrequencyView: View {
    let rows: [FeedbackFrequencyRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("行动频率", systemImage: "chart.bar.xaxis")
                .font(.headline)

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(
                        systemName: row.isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        row.isSelected ? Color.accentColor : Color.secondary
                    )
                    .accessibilityLabel(row.isSelected ? "已选择" : "未选择")

                    Text(row.actionTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.frequencyText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text(row.evText)
                        .monospacedDigit()
                        .frame(minWidth: 84, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("feedback.actionFrequencies")
    }
}
