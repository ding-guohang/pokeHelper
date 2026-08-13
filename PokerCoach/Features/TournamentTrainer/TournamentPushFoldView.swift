import PokerCore
import SwiftUI
import TrainingDomain

/// The heads-up push/fold trainer surface (debug/dogfood only — the packs are
/// unverified and absent from the store build). Discloses the unverified status
/// on both the answering and feedback screens.
struct TournamentPushFoldView: View {
    @State private var viewModel: TournamentPushFoldViewModel

    init(viewModel: TournamentPushFoldViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let disclosure = viewModel.disclosure {
                    Label(disclosure, systemImage: "hammer.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("tourn.trainer.disclosure")
                }

                switch viewModel.state {
                case .unavailable:
                    ContentUnavailableView(
                        "训练内容不可用",
                        systemImage: "tray",
                        description: Text("此构建未打包锦标赛 push/fold 内容。")
                    )
                case .failed(let message):
                    ContentUnavailableView("暂不可用", systemImage: "exclamationmark.triangle", description: Text(message))
                case .answering:
                    answering
                case .feedback:
                    feedback
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("单挑 Push/Fold 训练")
        .task {
            if viewModel.state == .unavailable, !viewModel.availableDepths.isEmpty {
                viewModel.startRandomHand()
            }
        }
    }

    private var answering: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.promptText)
                .font(.headline)
                .accessibilityIdentifier("tourn.trainer.prompt")

            Text("你的选择")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(viewModel.candidateActions.enumerated()), id: \.offset) { _, action in
                ActionButton(
                    title: actionTitle(action),
                    isSelected: viewModel.selectedAction == action,
                    accessibilityIdentifier: "tourn.trainer.action.\(actionKey(action))",
                    action: { viewModel.select(action: action) }
                )
            }

            Text("信心")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                confidenceButton(.guessing, "猜的")
                confidenceButton(.unsure, "不确定")
                confidenceButton(.verySure, "很确定")
            }

            if let message = viewModel.validationMessage {
                Text(message).font(.callout).foregroundStyle(.red)
            }

            ActionButton(
                title: "提交",
                isSelected: true,
                accessibilityIdentifier: "tourn.trainer.submit",
                action: { Task { await viewModel.submit() } }
            )
            .disabled(viewModel.isSaving)
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("反馈")
                .font(.headline)
                .accessibilityIdentifier("tourn.trainer.feedback")
            ForEach(Array(viewModel.feedbackLines.enumerated()), id: \.offset) { index, line in
                Text(line).accessibilityIdentifier("tourn.trainer.feedback.\(index)")
            }
            ActionButton(
                title: "下一手",
                isSelected: true,
                accessibilityIdentifier: "tourn.trainer.next",
                action: { viewModel.startRandomHand() }
            )
        }
    }

    private func confidenceButton(_ confidence: DecisionConfidence, _ title: String) -> some View {
        ActionButton(
            title: title,
            isSelected: viewModel.selectedConfidence == confidence,
            accessibilityIdentifier: "tourn.trainer.confidence.\(confidence.rawValue)",
            action: { viewModel.setConfidence(confidence) }
        )
    }

    private func actionTitle(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "弃牌"
        case .allIn: "全下"
        case .call: "跟注全下"
        case .check: "过牌"
        case .bet: "下注"
        case .raise: "加注"
        }
    }

    private func actionKey(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "fold"
        case .allIn: "allIn"
        case .call: "call"
        case .check: "check"
        case .bet: "bet"
        case .raise: "raise"
        }
    }
}
