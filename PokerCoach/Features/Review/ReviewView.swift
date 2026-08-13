import SwiftUI
import StrategyContent
import TrainingDomain

struct ReviewView: View {
    let dependencies: AppDependencies
    let onStartTraining: () -> Void

    @State private var viewModel: ReviewViewModel
    @State private var selectedScenarioID: String?

    init(
        dependencies: AppDependencies,
        onStartTraining: @escaping () -> Void = {}
    ) {
        self.dependencies = dependencies
        self.onStartTraining = onStartTraining
        _viewModel = State(initialValue: ReviewViewModel(
            eventStore: dependencies.eventStore,
            reducer: dependencies.playerModelReducer,
            planner: dependencies.planner,
            catalog: dependencies.localTrainingCatalog,
            strategyContentAvailability:
                dependencies.strategyContentAvailability,
            strategyProvider: dependencies.strategyProvider,
            installedContent: dependencies.installedContent
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                handLabEntry
                switch viewModel.state {
                case .loading:
                    ProgressView("正在加载复盘记录…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                case let .failed(message):
                    ContentUnavailableView {
                        Label("复盘暂不可用", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.refresh() }
                        }
                    }
                case .empty:
                    ContentUnavailableView {
                        Label("还没有训练记录", systemImage: "chart.bar")
                    } description: {
                        Text("完成一次决策训练后，这里会显示真实的能力画像。")
                    } actions: {
                        Button("前往训练") {
                            onStartTraining()
                        }
                    }
                case .loaded:
                    abilities
                    history
                    if viewModel.suggestedTraining != nil {
                        Button("生成弱项训练") {
                            selectedScenarioID = viewModel.startSuggestedTraining()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canStartTraining)
                        if let explanation =
                            viewModel.trainingUnavailableExplanation
                        {
                            Text(explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
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

    /// Hand Lab is a review-time tool, not a fifth primary destination, so it is
    /// reached from within 复盘 rather than the tab bar. The tournament ICM
    /// calculator is another such review-time tool.
    private var handLabEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                HandLabView(dependencies: dependencies)
            } label: {
                Label("牌局实验室", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
            }
            .accessibilityIdentifier("review.handLab")

            // A content-free analysis calculator (pure ICM math, no strategy
            // content, no training events), reached from within 复盘 like Hand Lab.
            NavigationLink {
                TournamentICMView()
            } label: {
                Label("锦标赛 ICM 计算器", systemImage: "function")
                    .font(.headline)
            }
            .accessibilityIdentifier("review.tournamentICM")

            // A read-only trend over the user's own training history — pure
            // aggregation, no strategy content.
            NavigationLink {
                ProgressTrendView(eventStore: dependencies.eventStore)
            } label: {
                Label("训练进度", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
            }
            .accessibilityIdentifier("review.progressTrend")

            // Push/fold trainer over the bundled unverified tournament packs.
            // Only present when those packs are bundled (debug/dogfood); the
            // store build excludes them, so this entry disappears there.
            if !dependencies.tournamentPushFoldLoader.availableDepths().isEmpty {
                NavigationLink {
                    TournamentPushFoldView(viewModel: dependencies.makeTournamentPushFoldViewModel())
                } label: {
                    Label("单挑 Push/Fold 训练", systemImage: "suit.spade.fill")
                        .font(.headline)
                }
                .accessibilityIdentifier("review.tournamentPushFold")
            }
        }
    }

    private var abilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("能力画像")
                .font(.headline)
            ForEach(viewModel.abilities, id: \.dimension) { ability in
                VStack(alignment: .leading, spacing: 6) {
                    Text(AbilityDimensionPresentation.displayName(
                        for: ability.dimension
                    ))
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
                    if let disclosure = viewModel.contentDisclosure(
                        for: event
                    ) {
                        Label(disclosure, systemImage: "hammer.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(AbilityDimensionPresentation.displayName(
                        for: event.abilityDimension
                    ))
                    Text(
                        "得分 \(event.grade.score) · EV 损失 \(event.grade.evLoss.milliBB) milliBB · EV 损失率 \(event.grade.lossRateBasisPoints) bp"
                    )
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
        dependencies.makeDecisionSessionViewModel(
            scenarioID: scenarioID
        )
    }
}
