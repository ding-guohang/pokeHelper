import PokerCore
import StrategyContent
import SwiftUI
import TrainingDomain

struct DecisionSessionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: DecisionSessionViewModel

    init(viewModel: DecisionSessionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("正在加载训练场景…")
            case .answering:
                tableScreen
            case .feedback:
                feedbackScreen
            case .completed:
                ContentUnavailableView(
                    "训练完成",
                    systemImage: "checkmark.circle",
                    description: Text("本次决策已记录。")
                )
            case let .failed(message):
                failureView(message: message)
            }
        }
        .navigationTitle("决策训练")
        .task {
            guard viewModel.state == .loading else {
                return
            }
            await viewModel.load()
        }
    }

    private var tableScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                scenarioFacts
                cards
                actions
                confidence

                if let validationMessage = viewModel.validationMessage {
                    Text(validationMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await viewModel.submit()
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("提交")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("decision.submit")
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var feedbackScreen: some View {
        if
            let scenario = viewModel.scenario,
            let submission = viewModel.submission,
            let grade = viewModel.grade
        {
            let presentation = FeedbackPresentation(
                scenario: scenario,
                submission: submission,
                grade: grade,
                manifest: viewModel.strategyManifest
            )
            ScrollView {
                Group {
                    if ProfessionalFeedbackLayout(
                        horizontalSizeClass: horizontalSizeClass
                    ) == .splitColumns {
                        HStack(alignment: .top, spacing: 32) {
                            tableContext
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .topLeading
                                )
                                .accessibilityIdentifier(
                                    "feedback.table-column"
                                )
                            feedbackAnalysis(presentation)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .topLeading
                                )
                                .accessibilityIdentifier(
                                    "feedback.analysis-column"
                                )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            tableContext
                            feedbackAnalysis(presentation)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView(
                "反馈暂不可用",
                systemImage: "exclamationmark.triangle",
                description: Text("已保存的决策数据不完整。")
            )
        }
    }

    private var tableContext: some View {
        VStack(alignment: .leading, spacing: 20) {
            scenarioFacts
            cards
        }
    }

    private func feedbackAnalysis(
        _ presentation: FeedbackPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("回答已保存", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            ProfessionalFeedbackView(presentation: presentation)
            Button("继续") {
                viewModel.continueSession()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var scenarioFacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.strategyManifest?.reviewStatus == .testFixture {
                Label(
                    "开发演示数据",
                    systemImage: "hammer.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
            LabeledContent("位置") {
                Text(viewModel.positionLabel ?? "—")
                    .accessibilityIdentifier("decision.position")
            }
            LabeledContent("有效筹码") {
                Text(
                    viewModel.scenario?.decision.effectiveStack.displayText
                        ?? "—"
                )
            }
            LabeledContent("底池") {
                Text(viewModel.scenario?.decision.pot.displayText ?? "—")
                    .accessibilityIdentifier("decision.pot")
            }
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手牌")
                .font(.headline)
            HStack {
                ForEach(
                    Array((viewModel.scenario?.heroCards ?? []).enumerated()),
                    id: \.offset
                ) { _, card in
                    PokerCardView(card: card)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("decision.heroCards")

            Text("公共牌")
                .font(.headline)
            Group {
                if let board = viewModel.scenario?.board, !board.isEmpty {
                    HStack {
                        ForEach(Array(board.enumerated()), id: \.offset) {
                            _, card in
                            PokerCardView(card: card)
                        }
                    }
                } else {
                    Text("翻前")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("decision.board")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择行动")
                .font(.headline)
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 120), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(viewModel.legalActions, id: \.stableID) { action in
                    ActionButton(
                        title: action.displayTitle,
                        isSelected: viewModel.selectedAction == action,
                        accessibilityIdentifier:
                            "decision.action.\(action.stableID)"
                    ) {
                        viewModel.select(action: action)
                    }
                    .disabled(viewModel.state != .answering)
                }
            }
        }
    }

    private var confidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("信心程度")
                .font(.headline)
            HStack {
                ForEach(
                    DecisionConfidence.displayCases,
                    id: \.rawValue
                ) { confidence in
                    ActionButton(
                        title: confidence.displayTitle,
                        isSelected: viewModel.selectedConfidence?.rawValue
                            == confidence.rawValue,
                        accessibilityIdentifier:
                            "decision.confidence.\(confidence.rawValue)"
                    ) {
                        viewModel.setConfidence(confidence)
                    }
                    .disabled(viewModel.state != .answering)
                }
            }
        }
    }

    private func failureView(message: String) -> some View {
        ContentUnavailableView {
            Label(
                "训练暂时不可用",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task {
                    if viewModel.scenario == nil {
                        await viewModel.load()
                    } else {
                        await viewModel.submit()
                    }
                }
            }
            .disabled(!viewModel.canRetry)
        }
    }
}
