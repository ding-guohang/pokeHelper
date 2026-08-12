import SessionPersistence
import SessionSimulation
import SwiftUI

/// The cash-session surface: pick a length, see who is at the table, play, and
/// review what happened.
///
/// ## Identifiers sit on leaves
///
/// Every `accessibilityIdentifier` in this file is on a `Text` or a `Button`
/// and never on a stack. An accessibility modifier applied to a container
/// applies to everything inside it, so an identifier on a `VStack` renames all
/// of its children — this project has already lost an afternoon to a button
/// that answered to its parent's name.
struct SessionView: View {
    let dependencies: AppDependencies
    let sessionStore: FileSessionRecordStore

    @State private var viewModel: SessionViewModel
    @State private var selectedHandIndex: Int?
    @State private var isShowingFrequencyReport = false

    init(dependencies: AppDependencies, sessionStore: FileSessionRecordStore) {
        self.dependencies = dependencies
        self.sessionStore = sessionStore
        _viewModel = State(
            initialValue: SessionViewModel(
                sessionStore: sessionStore,
                eventStore: dependencies.eventStore,
                strategyProvider: dependencies.strategyProvider,
                makeSeed: dependencies.makeSessionSeed
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                opponents
                lengthPicker
                startRow
                results
                reportEntry
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("现金局")
        .navigationDestination(item: $selectedHandIndex) { handIndex in
            if let review = viewModel.reviews.first(where: { $0.handIndex == handIndex }) {
                KeyHandReviewView(review: review, dependencies: dependencies)
            } else {
                ContentUnavailableView(
                    "这手牌不在本局复盘里",
                    systemImage: "questionmark.circle"
                )
            }
        }
        .navigationDestination(isPresented: $isShowingFrequencyReport) {
            SessionFrequencyReportView(
                viewModel: SessionFrequencyReportViewModel(
                    sessionStore: sessionStore,
                    strategyProvider: dependencies.strategyProvider
                )
            )
        }
    }

    /// Who is at the table, stated before a card is dealt.
    ///
    /// The four profiles and their three published numbers, plus the disclosure
    /// that they are fixed heuristics. Both halves are required: a table of
    /// tendencies with no provenance invites the user to read them as how real
    /// players behave, and a disclosure with no tendencies leaves them
    /// practising against something they cannot describe.
    private var opponents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("对手")
                .font(.headline)
            Text(viewModel.opponentDisclosure)
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("session.disclosure")

            ForEach(viewModel.profileRows) { profile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("session.profile.\(profile.id).name")
                    Text(profile.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("session.profile.\(profile.id).summary")
                    HStack(spacing: 16) {
                        tendency(
                            "入池率",
                            profile.entryRateText,
                            id: "session.profile.\(profile.id).entry"
                        )
                        tendency(
                            "激进度",
                            profile.aggressionText,
                            id: "session.profile.\(profile.id).aggression"
                        )
                        tendency(
                            "跟注倾向",
                            profile.callingTendencyText,
                            id: "session.profile.\(profile.id).calling"
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Text("对手行为表版本 \(viewModel.opponentTableVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tendency(_ name: String, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier(id)
        }
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手数")
                .font(.headline)
            HStack {
                ForEach(SessionViewModel.handCountChoices, id: \.self) { count in
                    ActionButton(
                        title: "\(count) 手",
                        isSelected: viewModel.selectedHandCount == count,
                        accessibilityIdentifier: "session.handCount.\(count)"
                    ) {
                        viewModel.select(handCount: count)
                    }
                    .disabled(viewModel.state == .playing)
                }
            }
        }
    }

    @ViewBuilder
    private var startRow: some View {
        Button("开始对局") {
            Task { await viewModel.start() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.state == .playing)
        .accessibilityIdentifier("session.start")

        switch viewModel.state {
        case .playing:
            ProgressView("正在发牌…")
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier("session.error")
        case .setup, .finished:
            EmptyView()
        }
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.state == .finished {
            VStack(alignment: .leading, spacing: 12) {
                Text("已打完 \(viewModel.handsPlayed) 手")
                    .font(.headline)
                    .accessibilityIdentifier("session.summary.hands")
                Text("关键手")
                    .font(.subheadline.weight(.semibold))
                ForEach(viewModel.reviews) { review in
                    Button {
                        selectedHandIndex = review.handIndex
                    } label: {
                        HStack {
                            Text("第 \(review.handIndex + 1) 手")
                            Spacer()
                            Text(review.reasonText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("session.keyhand.\(review.handIndex)")
                }
            }
        }
    }

    private var reportEntry: some View {
        Button("按位置频率报告") {
            isShowingFrequencyReport = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("session.frequency.open")
    }
}
