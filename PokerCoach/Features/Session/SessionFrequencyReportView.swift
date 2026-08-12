import SwiftUI

/// The hero's preflop frequencies by position, across every recorded session.
///
/// Every row shows its counts. Only the rows entitled to a verdict show one:
/// below the sample threshold the screen says so instead of printing a
/// difference, and a position installed content has no scenario for shows no
/// baseline rather than a zero.
struct SessionFrequencyReportView: View {
    @State private var viewModel: SessionFrequencyReportViewModel

    init(viewModel: SessionFrequencyReportViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.state {
                case .loading:
                    ProgressView("正在统计…")
                case let .failed(message):
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("session.frequency.error")
                case .loaded:
                    loaded
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("频率报告")
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var loaded: some View {
        Text(viewModel.sampleRuleText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("session.frequency.rule")

        if viewModel.rows.isEmpty {
            Text("还没有已记录的手牌。")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("session.frequency.empty")
        }

        ForEach(viewModel.rows) { row in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.positionLabel) · \(row.facingLabel)")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("session.frequency.\(row.id).spot")
                Text("\(row.opportunitiesText)　\(row.entriesText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.frequency.\(row.id).counts")
                LabeledContent("实际") {
                    Text(row.frequencyText)
                        .monospacedDigit()
                        .accessibilityIdentifier(
                            "session.frequency.\(row.id).actual"
                        )
                }
                if let baselineText = row.baselineText {
                    LabeledContent("基准") {
                        Text(baselineText)
                            .monospacedDigit()
                            .accessibilityIdentifier(
                                "session.frequency.\(row.id).baseline"
                            )
                    }
                }
                if let deltaText = row.deltaText {
                    LabeledContent("差值") {
                        Text(deltaText)
                            .monospacedDigit()
                            .accessibilityIdentifier(
                                "session.frequency.\(row.id).delta"
                            )
                    }
                }
                if let withheldText = row.withheldText {
                    Text(withheldText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "session.frequency.\(row.id).withheld"
                        )
                }
            }
            .padding(.vertical, 4)
        }

        if !viewModel.leakRows.isEmpty {
            Text("漏洞")
                .font(.headline)
            ForEach(viewModel.leakRows) { row in
                Text("\(row.positionLabel) · \(row.facingLabel) \(row.leakText ?? "")")
                    .font(.callout)
                    .accessibilityIdentifier("session.frequency.leak.\(row.id)")
            }
        }
    }
}
