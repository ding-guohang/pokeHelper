import SwiftUI

enum ProfessionalFeedbackLayout: Equatable {
    case singleColumn
    case splitColumns

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular
            ? .splitColumns
            : .singleColumn
    }
}

struct ProfessionalFeedbackView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let presentation: FeedbackPresentation

    private var layout: ProfessionalFeedbackLayout {
        ProfessionalFeedbackLayout(
            horizontalSizeClass: horizontalSizeClass
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            outcome
            conclusion
            ActionFrequencyView(rows: presentation.frequencyRows)

            if layout == .splitColumns {
                HStack(alignment: .top, spacing: 24) {
                    if !presentation.rangeCells.isEmpty {
                        RangeMatrixView(cells: presentation.rangeCells)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    reasoning
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                if !presentation.rangeCells.isEmpty {
                    RangeMatrixView(cells: presentation.rangeCells)
                }
                reasoning
            }

            strategyBaseline
            provenance
        }
        .accessibilityIdentifier("feedback.professional")
    }

    private var outcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.qualityText)
                    .font(.title2.bold())
                Spacer()
                Text(presentation.scoreText)
                    .font(.headline)
                    .monospacedDigit()
            }

            Label(
                presentation.provenanceBadge,
                systemImage: "checkmark.seal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(presentation.confidenceText)
                .font(.subheadline.weight(.semibold))
            Text(presentation.confidenceCalibrationText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("EV 损失")
                Spacer()
                Text(presentation.evLossText)
                    .monospacedDigit()
            }
            LabeledContent("决策") {
                Text(presentation.selectedActionText)
            }
            LabeledContent("所选行动 EV") {
                Text(presentation.selectedEVText)
                    .monospacedDigit()
            }
            LabeledContent("最佳 EV") {
                Text(presentation.bestEVText)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("feedback.outcome")
    }

    private var conclusion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("结论", systemImage: "text.bubble")
                .font(.headline)
            Text(presentation.conclusion)
                .font(.body)
        }
    }

    private var reasoning: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("四问推理", systemImage: "list.number")
                .font(.headline)

            ForEach(presentation.reasoningSections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.question)
                        .font(.subheadline.weight(.semibold))
                    Text(section.answer)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("feedback.reasoning")
    }

    private var strategyBaseline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("GTO 基线", systemImage: "scope")
                .font(.headline)
            Text(presentation.gtoBaseline)

            if let exploitAdjustment = presentation.exploitAdjustment {
                Divider()
                Label("有条件剥削调整", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text(exploitAdjustment)
            }
        }
        .accessibilityIdentifier("feedback.strategyBaseline")
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("求解假设与来源", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            LabeledContent("场景") {
                Text(presentation.assumptions)
            }
            LabeledContent("有效筹码") {
                Text(presentation.stackText)
            }
            LabeledContent("抽水") {
                Text(presentation.rakeText)
            }
            LabeledContent("下注树") {
                Text(presentation.betSizeTreeText)
            }
            LabeledContent("生成来源") {
                Text(presentation.generatedSource)
            }
            LabeledContent("内容版本") {
                Text(presentation.contentVersion)
            }
            LabeledContent("审核/开发状态") {
                Text(presentation.reviewStatusText)
            }
        }
        .font(.callout)
        .accessibilityIdentifier("feedback.provenance")
    }
}
