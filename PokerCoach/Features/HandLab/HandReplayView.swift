import HandHistory
import HandHistoryPersistence
import Observation
import PokerCore
import SwiftUI

/// Drives the replay surface for one adopted hand: load the hand, map it to the
/// streets it actually reached and, per hero decision, how the line compares to
/// installed content.
///
/// It holds no event store and writes nothing: a replay is a read. The one thing
/// it can start is a remediation drill, and only when the user taps into a
/// covered node — that path is the ordinary training flow, injected so this view
/// model stays unaware of how the grader, event store and identity are wired.
@MainActor
@Observable
final class HandReplayViewModel {
    private let libraryStore: FileHandLibraryStore
    private let identity: String
    /// The table size, so the view can label positions from seat offsets.
    let tableSize: Int
    private let matcher: ImportedHandContentMatcher
    private let makeRemediationSession: (String) -> DecisionSessionViewModel

    /// The streets to replay, nil until the first `load()` finishes so the view
    /// can tell "loading" from "loaded, nothing to show".
    private(set) var streets: [ReplayStreet]?
    /// One entry per hero decision, with its content counterfactual.
    private(set) var counterfactuals: [HeroNodeCounterfactual] = []
    /// The hand's seats, so a street action can be labelled with the acting
    /// seat's position rather than a bare seat number.
    private(set) var seats: [ObservedSeat] = []

    init(
        libraryStore: FileHandLibraryStore,
        identity: String,
        tableSize: Int,
        matcher: ImportedHandContentMatcher,
        makeRemediationSession: @escaping (String) -> DecisionSessionViewModel
    ) {
        self.libraryStore = libraryStore
        self.identity = identity
        self.tableSize = tableSize
        self.matcher = matcher
        self.makeRemediationSession = makeRemediationSession
    }

    /// The training session that drills the given remediation scenario. Building
    /// it starts nothing and writes nothing; a training event is only recorded
    /// when the user completes the drill through the ordinary session flow.
    func remediationSession(for scenarioID: String) -> DecisionSessionViewModel {
        makeRemediationSession(scenarioID)
    }

    /// Loads the hand and maps it. A failed read leaves an empty replay rather
    /// than a spinner that never resolves.
    func load() async {
        guard let hand = try? await libraryStore.hand(identity: identity) else {
            streets = []
            counterfactuals = []
            seats = []
            return
        }
        seats = hand.seats
        streets = replayStreets(of: hand)
        counterfactuals = heroNodeCounterfactuals(of: hand, matcher: matcher)
    }
}

/// Replays one adopted hand street by street and, for each hero decision, shows
/// how the line compares to installed content — a covered node offering a drill,
/// an uncovered node saying there is nothing to compare against.
///
/// Reached from a hand in the Hand Lab library alongside "分析", never from a
/// primary tab: the four core destinations are fixed, and a replay is a
/// review-time tool the same way Hand Lab itself is.
struct HandReplayView: View {
    /// The remediation the user tapped into. A dedicated type, not a bare
    /// `String`: the enclosing Review stack already declares a
    /// `navigationDestination` for `String`, and two destinations of the same
    /// type in one stack collide. Keying the push on its own type keeps this
    /// destination independent of that one.
    private struct RemediationRoute: Identifiable, Hashable {
        let scenarioID: String
        var id: String { scenarioID }
    }

    @State private var viewModel: HandReplayViewModel
    @State private var remediationRoute: RemediationRoute?

    init(viewModel: HandReplayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let streets = viewModel.streets {
                    streetsSection(streets)
                    counterfactualsSection
                } else {
                    ProgressView("正在载入回放…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("回放")
        .task { await viewModel.load() }
        .navigationDestination(item: $remediationRoute) { route in
            DecisionSessionView(viewModel: viewModel.remediationSession(for: route.scenarioID))
        }
    }

    @ViewBuilder
    private func streetsSection(_ streets: [ReplayStreet]) -> some View {
        Text("逐街回放")
            .font(.headline)
        ForEach(streets, id: \.street) { street in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(HandImportPreview.streetName(street.street)) \(HandImportPreview.board(street.board))")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("handlab.replay.\(street.street.rawValue).board")
                ForEach(Array(street.actions.enumerated()), id: \.offset) { index, action in
                    Text(HandImportPreview.action(
                        action,
                        tableSize: viewModel.tableSize,
                        seats: viewModel.seats
                    ))
                        .font(.footnote)
                        .accessibilityIdentifier(
                            "handlab.replay.\(street.street.rawValue).action.\(index)"
                        )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var counterfactualsSection: some View {
        Text("你的行动 vs 内容频率")
            .font(.headline)
        if viewModel.counterfactuals.isEmpty {
            Text("这手没有英雄决策可对照。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("handlab.replay.nodes.empty")
        } else {
            ForEach(Array(viewModel.counterfactuals.enumerated()), id: \.offset) { index, node in
                nodeView(index: index, node: node)
            }
        }
    }

    @ViewBuilder
    private func nodeView(index: Int, node: HeroNodeCounterfactual) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(HandImportPreview.streetName(node.signature.signature.street)) · \(HandImportPreview.position(tableSize: viewModel.tableSize, offset: node.signature.signature.heroSeatOffsetFromButton)) · 你打的：\(Self.heroAction(node.signature.action))")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("handlab.replay.node.\(index).spot")

            switch node.coverage {
            case let .covered(_, weight):
                Text("内容频率 \(HandImportKeyNodePresentation.percent(basisPoints: weight))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("handlab.replay.node.\(index).counterfactual")
            case .uncovered:
                Text("无内容可对照")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("handlab.replay.node.\(index).counterfactual")
            }

            if let scenarioID = node.remediationScenarioID {
                Button("练这个漏洞") {
                    remediationRoute = RemediationRoute(scenarioID: scenarioID)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("handlab.replay.node.\(index).remediate")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The hero's own action as "<verb> [<amount>]", the amount rendered as big
    /// blinds by the same formatter the preview and analysis rows use.
    private static func heroAction(_ action: ObservedAction) -> String {
        let verb: String
        switch action.kind {
        case .fold: verb = "弃牌"
        case .check: verb = "过牌"
        case .call: verb = "跟注"
        case .bet: verb = "下注"
        case .raiseTo: verb = "加注至"
        }
        if let amount = action.amountCentiBB {
            return "\(verb) \(HandImportPreview.bb(amount))"
        }
        return verb
    }
}
