import StrategyContent
import SwiftUI
import TrainingDomain

struct TodayView: View {
    let dependencies: AppDependencies

    @State private var viewModel: TodayViewModel
    @State private var selectedScenarioID: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: TodayViewModel(
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
                        Label("今日计划暂不可用", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failureMessage)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.refresh() }
                        }
                    }
                } else if let primaryItem = viewModel.primaryItem {
                    primaryTraining(primaryItem)
                    supportingTraining
                } else {
                    ContentUnavailableView(
                        "暂无可用训练",
                        systemImage: "checkmark.circle",
                        description: Text("当前内容暂未提供训练场景。")
                    )
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("今日")
        .onAppear {
            Task { await viewModel.refresh() }
        }
        .navigationDestination(item: $selectedScenarioID) { scenarioID in
            DecisionSessionView(viewModel: makeSessionViewModel(scenarioID))
        }
    }

    private func primaryTraining(_ item: DailyPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今日重点", systemImage: "target")
                .font(.headline)
            Text(abilityTitle(item.abilityDimension))
                .font(.title2.bold())
            Text(viewModel.durationText)
                .foregroundStyle(.secondary)
            Text(reasonText(item.reason))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("开始重点训练") {
                selectedScenarioID = viewModel.startPrimaryItem()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var supportingTraining: some View {
        if !viewModel.supportingItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("补充练习")
                    .font(.headline)
                ForEach(viewModel.supportingItems) { item in
                    LabeledContent(abilityTitle(item.abilityDimension)) {
                        Text("约 \(item.catalogItem.estimatedMinutes) 分钟")
                            .foregroundStyle(.secondary)
                    }
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

    private func abilityTitle(_ dimension: String) -> String {
        switch dimension {
        case "bet-sizing": "下注尺度"
        case "preflop-range": "翻前范围"
        case "flop-cbet": "翻牌持续下注"
        default: dimension
        }
    }

    private func reasonText(_ reason: String) -> String {
        "选择原因：\(reason)"
    }
}
