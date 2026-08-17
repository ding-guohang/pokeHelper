import PokerCore
import SwiftUI
import TrainingDomain

/// The river trainer surface. The packs are `reviewed`, so no unverified banner
/// shows and the trainer ships in every channel including store.
struct RiverTrainerView: View {
    @State private var viewModel: RiverTrainerViewModel

    init(viewModel: RiverTrainerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let disclosure = viewModel.disclosure {
                    Label(disclosure, systemImage: "hammer.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("river.trainer.disclosure")
                }

                switch viewModel.state {
                case .unavailable:
                    ContentUnavailableView(
                        "训练内容不可用",
                        systemImage: "tray",
                        description: Text("此构建未打包河牌内容。")
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
        .navigationTitle("河牌决策训练")
        .task {
            if viewModel.state == .unavailable, !viewModel.availableBoards.isEmpty {
                viewModel.startRandomHand()
            }
        }
    }

    private var answering: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.promptText)
                .font(.headline)
                .accessibilityIdentifier("river.trainer.prompt")

            HStack(spacing: 6) {
                Text("公共牌").font(.subheadline).foregroundStyle(.secondary)
                Text(viewModel.board.map(\.code).joined(separator: " "))
                    .font(.body.monospaced())
                    .accessibilityIdentifier("river.trainer.board")
            }

            Text("你的选择")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(viewModel.candidateActions.enumerated()), id: \.offset) { _, action in
                ActionButton(
                    title: actionTitle(action),
                    isSelected: viewModel.selectedAction == action,
                    accessibilityIdentifier: "river.trainer.action.\(actionKey(action))",
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
                accessibilityIdentifier: "river.trainer.submit",
                action: { Task { await viewModel.submit() } }
            )
            .disabled(viewModel.isSaving)
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("反馈")
                .font(.headline)
                .accessibilityIdentifier("river.trainer.feedback")
            ForEach(Array(viewModel.feedbackLines.enumerated()), id: \.offset) { index, line in
                Text(line).accessibilityIdentifier("river.trainer.feedback.\(index)")
            }
            ActionButton(
                title: "下一手",
                isSelected: true,
                accessibilityIdentifier: "river.trainer.next",
                action: { viewModel.startRandomHand() }
            )
        }
    }

    private func confidenceButton(_ confidence: DecisionConfidence, _ title: String) -> some View {
        ActionButton(
            title: title,
            isSelected: viewModel.selectedConfidence == confidence,
            accessibilityIdentifier: "river.trainer.confidence.\(confidence.rawValue)",
            action: { viewModel.setConfidence(confidence) }
        )
    }

    private func actionTitle(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "弃牌"
        case .check: "过牌"
        case .call: "跟注"
        case .allIn: "全下"
        case let .bet(to): "下注至 \(bbText(to))"
        case let .raise(to): "加注至 \(bbText(to))"
        }
    }

    /// Bet keys include the size so multiple bet sizes get distinct identifiers.
    private func actionKey(_ action: DecisionAction) -> String {
        switch action {
        case .fold: "fold"
        case .check: "check"
        case .call: "call"
        case .allIn: "allIn"
        case let .bet(to): "bet\(to.centiBB)"
        case let .raise(to): "raise\(to.centiBB)"
        }
    }

    private func bbText(_ amount: BBAmount) -> String {
        let whole = amount.centiBB / 100
        let frac = (amount.centiBB % 100) / 10
        return "\(whole).\(frac)BB"
    }
}
