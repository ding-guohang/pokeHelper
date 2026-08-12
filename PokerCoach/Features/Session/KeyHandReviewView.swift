import PokerCore
import SwiftUI

/// One key hand: the streets it was played over, and — when installed content
/// covers the spot — what that content does with it.
///
/// The two halves are deliberately unequal. The replay is always there, because
/// it is a record of what happened. The comparison appears only where a
/// scenario covers the preflop spot, and with it the way into training. A hand
/// content says nothing about gets the replay and nothing else: no ranges
/// borrowed from a neighbouring situation, and no "重打" leading to a scenario
/// that is not this spot.
struct KeyHandReviewView: View {
    let review: KeyHandReview
    let dependencies: AppDependencies

    @State private var replayScenarioID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ForEach(review.streets) { street in
                    streetSection(street)
                }
                if let comparison = review.comparison {
                    comparisonSection(comparison)
                }
                // Gated on the model's own answer rather than on `comparison`
                // being non-nil. The two conditions are the same today and a
                // test says so; reading it off the comparison here would make
                // the screen agree with itself no matter what the model said.
                if let scenarioID = review.replayScenarioID {
                    replayButton(scenarioID)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("第 \(review.handIndex + 1) 手")
        .navigationDestination(item: $replayScenarioID) { scenarioID in
            DecisionSessionView(
                viewModel: dependencies.makeDecisionSessionViewModel(
                    scenarioID: scenarioID
                )
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.reasonText)
                .font(.headline)
                .accessibilityIdentifier("session.keyhand.reason")
            HStack {
                ForEach(Array(review.heroCards.enumerated()), id: \.offset) { _, card in
                    PokerCardView(card: card)
                }
            }
        }
    }

    /// One street. Its own board, its own pot, its own actions.
    private func streetSection(_ street: KeyHandStreet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(street.title)
                .font(.subheadline.weight(.semibold))

            LabeledContent("公共牌") {
                Text("\(street.board.count)")
                    .monospacedDigit()
                    .accessibilityIdentifier(
                        "session.replay.\(street.id).boardCount"
                    )
            }
            if !street.board.isEmpty {
                HStack {
                    ForEach(Array(street.board.enumerated()), id: \.offset) { _, card in
                        PokerCardView(card: card)
                    }
                }
            }

            LabeledContent("本街结束底池") {
                Text(street.potAtEnd.displayText)
                    .monospacedDigit()
                    .accessibilityIdentifier("session.replay.\(street.id).pot")
            }
            LabeledContent("本街行动数") {
                Text("\(street.actions.count)")
                    .monospacedDigit()
                    .accessibilityIdentifier(
                        "session.replay.\(street.id).actionCount"
                    )
            }

            ForEach(street.actions) { action in
                Text("\(action.actorLabel) \(action.actionTitle)　底池 \(action.potAfterText)")
                    .font(.callout)
                    .foregroundStyle(action.isHero ? Color.primary : Color.secondary)
                    .accessibilityIdentifier("session.replay.\(action.id)")
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonSection(_ comparison: KeyHandComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("与已安装内容对照")
                .font(.headline)
            Text(KeyHandComparison.notice)
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("session.comparison.notice")
            Text(comparison.scenarioTitle)
                .font(.subheadline)
                .accessibilityIdentifier("session.comparison.scenario")
            Text(comparison.spotSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("session.comparison.spot")

            LabeledContent("你的行动") {
                Text(comparison.heroActionTitle)
                    .accessibilityIdentifier("session.comparison.heroAction")
            }
            if let weight = comparison.heroActionWeightText {
                LabeledContent("范围表给这个行动的权重") {
                    Text(weight)
                        .monospacedDigit()
                        .accessibilityIdentifier("session.comparison.heroWeight")
                }
            }

            Text("内容在这个场景里的频率与 EV")
                .font(.subheadline.weight(.semibold))
            ForEach(comparison.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.isHeroAction ? "▸ \(row.actionTitle)" : row.actionTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(
                            "session.comparison.row.\(row.id).action"
                        )
                    Text(row.frequencyText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "session.comparison.row.\(row.id).frequency"
                        )
                    Text(row.evText)
                        .monospacedDigit()
                        .frame(minWidth: 84, alignment: .trailing)
                        .accessibilityIdentifier(
                            "session.comparison.row.\(row.id).ev"
                        )
                }
                .font(.callout)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func replayButton(_ scenarioID: String) -> some View {
        Button(KeyHandComparison.replayTitle) {
            replayScenarioID = scenarioID
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("session.replayAsTraining")
    }
}
