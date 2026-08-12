import HandHistory
import Observation
import SwiftUI

/// Drives the analysis surface for one adopted hand: ask the coordinator for the
/// review-worthy nodes, then map them to display rows.
///
/// It holds no event store and writes nothing: analysis is a read. The
/// coordinator it calls is the type that *could* file an event and does not, and
/// this view model does not add a second path — it turns key nodes into a pure
/// presentation and stops there.
@MainActor
@Observable
final class HandAnalysisViewModel {
    private let coordinator: HandAnalysisCoordinator
    private let identity: String
    private let tableSize: Int

    /// The mapped rows, nil until the first `load()` finishes so the view can
    /// tell "analyzing" from "analyzed, nothing to review".
    private(set) var presentation: HandImportKeyNodePresentation?

    init(coordinator: HandAnalysisCoordinator, identity: String, tableSize: Int) {
        self.coordinator = coordinator
        self.identity = identity
        self.tableSize = tableSize
    }

    /// Runs the analysis and maps its key nodes. A failed read leaves an empty
    /// presentation rather than a spinner that never resolves.
    func load() async {
        let nodes = (try? await coordinator.analyze(identity: identity)) ?? []
        presentation = HandImportKeyNodePresentation(keyNodes: nodes, tableSize: tableSize)
    }
}

/// The analysis of one adopted hand: its key nodes and, for each, how the line
/// the hero took compares to installed content.
///
/// Reached from a hand in the Hand Lab library, never from a primary tab — the
/// four core destinations are fixed, and analysis is a review-time tool the same
/// way Hand Lab itself is.
struct HandAnalysisView: View {
    @State private var viewModel: HandAnalysisViewModel

    init(viewModel: HandAnalysisViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("关键节点")
                    .font(.headline)

                if let presentation = viewModel.presentation {
                    if presentation.rows.isEmpty {
                        Text("这手对已安装内容没有需要复盘的关键节点。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("handlab.analysis.empty")
                    } else {
                        Text("共 \(presentation.rows.count) 个关键节点")
                            .font(.subheadline)
                            .accessibilityIdentifier("handlab.analysis.count")
                        ForEach(presentation.rows) { row in
                            rowView(row)
                        }
                    }
                } else {
                    ProgressView("正在分析…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("分析")
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func rowView(_ row: HandImportKeyNodePresentation.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(row.street) · \(row.position)")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("handlab.analysis.row.\(row.index).spot")

            Text("你打的：\(row.heroAction)")
                .font(.footnote.monospacedDigit())
                .accessibilityIdentifier("handlab.analysis.row.\(row.index).action")

            Text(row.reasonLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.isDeviation ? .orange : .blue)
                .accessibilityIdentifier("handlab.analysis.row.\(row.index).reason")

            switch row.comparison {
            case let .covered(contentFrequency, deviation):
                Text("内容频率 \(contentFrequency) · 偏离 \(deviation)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("handlab.analysis.row.\(row.index).comparison")
            case .uncovered:
                Text("无内容可对照")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("handlab.analysis.row.\(row.index).comparison")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
