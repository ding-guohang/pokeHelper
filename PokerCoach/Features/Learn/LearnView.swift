import SwiftUI

struct LearnView: View {
    let dependencies: AppDependencies

    @State private var viewModel: LearnViewModel?
    @State private var expandedNodeID: String?

    var body: some View {
        List {
            if let viewModel {
                Section {
                    ForEach(viewModel.nodes) { node in
                        nodeRow(node, viewModel: viewModel)
                    }
                } header: {
                    Text("现金局能力树")
                } footer: {
                    Text("已掌握 \(viewModel.masteredCount)/\(viewModel.masteryProgressDenominator) 个节点")
                }

                Section("内容") {
                    LabeledContent("当前内容") {
                        Text(viewModel.strategyContentAvailability.disclosureText)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("暂无策略内容", systemImage: "tray")
                } description: {
                    Text(StrategyContentMetadata.reviewedContentUnavailableDisclosure)
                }
            }
        }
        .navigationTitle("学习")
        .accessibilityIdentifier("learn.tree")
        .onAppear { Task { await load() } }
    }

    @ViewBuilder
    private func nodeRow(
        _ node: CurriculumNodePresentation,
        viewModel: LearnViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    node.title,
                    systemImage: node.isMastered ? "checkmark.seal.fill" : "circle"
                )
                Spacer()
                Text(node.isContentUnavailable ? "暂无内容" : "\(node.practisableScenarioCount) 题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !node.prerequisiteTitles.isEmpty {
                Text("前置：\(node.prerequisiteTitles.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if expandedNodeID == node.id,
               let detail = viewModel.detail(forNode: node.id) {
                ForEach(detail.signalRows) { row in
                    HStack {
                        Image(systemName: row.satisfied ? "checkmark.circle.fill" : "circle.dotted")
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("learn.signal.\(row.id)")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expandedNodeID = expandedNodeID == node.id ? nil : node.id
        }
        // Applied to the label rather than the row: an identifier on a
        // container propagates to its children and overwrites theirs, which is
        // how the mastery signal rows lost their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learn.node.\(node.id)")
    }

    /// Rebuilt on every appearance rather than once.
    ///
    /// Mastery is derived from the event history, so a tree cached at first
    /// appearance shows the same numbers for the life of the process no matter
    /// how much the user trains.
    private func load() async {
        guard let pack = try? await dependencies.strategyProvider.pack() else {
            return
        }
        let events = (try? await dependencies.eventStore.allEvents()) ?? []
        let model = LearnViewModel(
            pack: pack,
            events: events,
            strategyContentAvailability: dependencies.strategyContentAvailability
        )
        model.refresh()
        viewModel = model
    }
}
