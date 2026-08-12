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
    /// Builds the training session for a remediation scenario, injected so the
    /// view model stays unaware of how the session's grader, event store and
    /// identity are wired. It is the ordinary training factory, so a remediation
    /// drill is the ordinary training flow.
    private let makeRemediationSession: (String) -> DecisionSessionViewModel

    /// The mapped rows, nil until the first `load()` finishes so the view can
    /// tell "analyzing" from "analyzed, nothing to review".
    private(set) var presentation: HandImportKeyNodePresentation?

    init(
        coordinator: HandAnalysisCoordinator,
        identity: String,
        tableSize: Int,
        makeRemediationSession: @escaping (String) -> DecisionSessionViewModel
    ) {
        self.coordinator = coordinator
        self.identity = identity
        self.tableSize = tableSize
        self.makeRemediationSession = makeRemediationSession
    }

    /// The training session that drills the given remediation scenario. Building
    /// it starts nothing and writes nothing; a training event is only recorded
    /// when the user completes the drill through the ordinary session flow.
    func remediationSession(for scenarioID: String) -> DecisionSessionViewModel {
        makeRemediationSession(scenarioID)
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
    /// The remediation the user tapped into. A dedicated type, not a bare
    /// `String`: the enclosing Review stack already declares a
    /// `navigationDestination` for `String`, and two destinations of the same
    /// type in one stack collide — only the one nearest the root is used. Keying
    /// the push on its own type keeps this destination independent of that one.
    private struct RemediationRoute: Identifiable, Hashable {
        let scenarioID: String
        var id: String { scenarioID }
    }

    @State private var viewModel: HandAnalysisViewModel
    /// The remediation scenario the user tapped into, driving a push to the
    /// ordinary training session for that spot.
    @State private var remediationRoute: RemediationRoute?

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
        .navigationDestination(item: $remediationRoute) { route in
            DecisionSessionView(viewModel: viewModel.remediationSession(for: route.scenarioID))
        }
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

            if let scenarioID = row.remediationScenarioID {
                Button("练这个漏洞") {
                    remediationRoute = RemediationRoute(scenarioID: scenarioID)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("handlab.analysis.row.\(row.index).remediate")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
