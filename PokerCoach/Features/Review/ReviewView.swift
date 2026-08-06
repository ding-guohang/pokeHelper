import SwiftUI
import TrainingDomain

struct ReviewView: View {
    let dependencies: AppDependencies

    @State private var viewModel: ReviewViewModel
    @State private var selectedScenarioID: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ReviewViewModel(
            eventStore: dependencies.eventStore,
            reducer: dependencies.playerModelReducer,
            planner: dependencies.planner
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let failureMessage = viewModel.failureMessage {
                    ContentUnavailableView {
                        Label("复盘暂不可用", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failureMessage)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.refresh() }
                        }
                    }
                } else if viewModel.abilities.isEmpty {
                    ContentUnavailableView(
                        "还没有训练记录",
                        systemImage: "chart.bar",
                        description: Text("完成一次决策训练后，这里会显示真实的能力画像。")
                    )
                } else {
                    abilities
                    history
                    if viewModel.suggestedTraining != nil {
                        Button("生成弱项训练") {
                            selectedScenarioID = viewModel.startSuggestedTraining()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("复盘")
        .onAppear {
            Task { await viewModel.refresh() }
        }
        .navigationDestination(item: $selectedScenarioID) { scenarioID in
            DecisionSessionView(viewModel: makeSessionViewModel(scenarioID))
        }
    }

    private var abilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("能力画像")
                .font(.headline)
            ForEach(viewModel.abilities, id: \.dimension) { ability in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ability.dimension)
                        .font(.headline)
                    LabeledContent("样本数", value: "\(ability.sampleCount)")
                    LabeledContent("平均得分", value: "\(ability.meanScore)")
                    LabeledContent(
                        "平均 EV 损失率",
                        value: "\(ability.meanLossRateBasisPoints) bp"
                    )
                    LabeledContent(
                        "高信心失误",
                        value: "\(ability.highConfidenceErrorCount)"
                    )
                    LabeledContent("最近练习") {
                        Text(ability.lastPracticedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("训练历史")
                .font(.headline)
            ForEach(viewModel.history) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.abilityDimension)
                    Text("得分 \(event.grade.score) · EV 损失率 \(event.grade.lossRateBasisPoints) bp")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("内容 \(event.strategyPackID) / \(event.strategyContentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func makeSessionViewModel(
        _ scenarioID: String
    ) -> DecisionSessionViewModel {
        DecisionSessionViewModel(
            scenarioID: scenarioID,
            strategyProvider: dependencies.strategyProvider,
            scorer: dependencies.scorer,
            eventStore: dependencies.eventStore,
            localUserID: UUID(),
            deviceID: UUID()
        )
    }
}
