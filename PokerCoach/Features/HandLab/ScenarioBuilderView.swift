import HandHistory
import HandHistoryPersistence
import Observation
import PokerCore
import SwiftUI

/// The verbs the builder offers, and whether each carries a "to" amount.
///
/// A range table names the decision, not the sizing — a bet, raise and all-in
/// are all "raise" to it — so the size a sized verb carries only reaches the
/// constructed spot, never the coverage lookup.
enum ScenarioBuilderAction: String, CaseIterable, Identifiable {
    case fold
    case check
    case call
    case bet
    case raise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fold: "弃牌"
        case .check: "过牌"
        case .call: "跟注"
        case .bet: "下注"
        case .raise: "加注"
        }
    }

    /// Whether this verb needs a "to" amount to be a legal `DecisionAction`.
    var isSized: Bool {
        switch self {
        case .fold, .check: false
        case .call, .bet, .raise: true
        }
    }
}

/// Assembles a preflop spot by hand, asks whether installed content covers it,
/// and — when it does — offers the same remediation drill an imported deviation
/// would.
///
/// It builds a `ConstructedSpot` from the user's inputs (surfacing the exact
/// validation error a bad input earns), derives its signature, and classifies it
/// through the shared matcher core. Saving goes through `FileConstructedSpotStore`
/// and reaches no event store; a training event is recorded only when the user
/// completes a remediation drill through the ordinary session flow, exactly as
/// analysis-side remediation does.
@MainActor
@Observable
final class ScenarioBuilderViewModel {
    // MARK: Inputs

    /// The hero's 0-based offset from the button; 0 is the button at a
    /// six-handed table.
    var heroSeatOffsetFromButton: Int = 0
    var firstCardCode: String = "As"
    var secondCardCode: String = "Ad"
    var facing: FacingAction = .unopened
    /// The effective stack in whole big blinds; converted to centi-BB when the
    /// spot is built.
    var effectiveStackBB: Int = 100
    var actionVerb: ScenarioBuilderAction = .raise
    /// The "to" amount, in big blinds, for a sized verb.
    var actionToBB: Double = 2.5

    // MARK: Outputs

    /// Whether installed content covers the last built spot, nil until the first
    /// build.
    private(set) var coverage: NodeCoverage?
    /// The precondition the last build broke, if it was rejected.
    private(set) var validationError: ConstructedSpotError?
    /// The identity a successful save wrote under, so the view can confirm it.
    private(set) var savedIdentity: String?
    /// The last spot that built cleanly.
    private(set) var spot: ConstructedSpot?

    private let matcher: ImportedHandContentMatcher
    private let store: FileConstructedSpotStore
    /// Builds the training session for a covered spot's scenario, injected so the
    /// view model stays unaware of how the grader, event store and identity are
    /// wired — the ordinary training factory, so a remediation drill is the
    /// ordinary training flow.
    private let makeRemediationSession: (String) -> DecisionSessionViewModel

    init(
        matcher: ImportedHandContentMatcher,
        store: FileConstructedSpotStore,
        makeRemediationSession: @escaping (String) -> DecisionSessionViewModel
    ) {
        self.matcher = matcher
        self.store = store
        self.makeRemediationSession = makeRemediationSession
    }

    /// The scenario a covered spot can be drilled against, or nil when the spot
    /// is uncovered (or nothing has been built).
    var remediationScenarioID: String? {
        if case let .covered(scenarioID, _) = coverage {
            return scenarioID
        }
        return nil
    }

    /// The range-table weight the covering scenario gives the line taken, out of
    /// 10,000, or nil when the spot is uncovered.
    var coveredWeightBasisPoints: Int? {
        if case let .covered(_, weight) = coverage {
            return weight
        }
        return nil
    }

    /// Builds a spot from the current inputs and classifies it.
    ///
    /// A rejected build surfaces its `ConstructedSpotError` and clears any prior
    /// coverage, so the screen never shows a comparison for a spot that does not
    /// exist. Building starts nothing and writes nothing.
    func build() {
        do {
            let built = try ConstructedSpot(
                heroSeatOffsetFromButton: heroSeatOffsetFromButton,
                holeCardCodes: [firstCardCode, secondCardCode],
                facing: facing,
                effectiveStackCentiBB: effectiveStackBB * 100,
                action: decisionAction()
            )
            spot = built
            validationError = nil
            savedIdentity = nil
            coverage = matcher.classify(signature: built.signature(), action: built.action)
        } catch let error as ConstructedSpotError {
            spot = nil
            coverage = nil
            savedIdentity = nil
            validationError = error
        } catch {
            spot = nil
            coverage = nil
            savedIdentity = nil
            validationError = nil
        }
    }

    /// Persists the last built spot as a new version. Reaches only the
    /// constructed-spot store, never a training event: saving a spot is not a
    /// training answer.
    func save() async {
        guard let spot else { return }
        try? await store.save(spot)
        savedIdentity = spot.identity
    }

    /// The training session that drills a covered spot's scenario, or nil when
    /// the spot is uncovered. Building it starts nothing and writes nothing.
    func remediationSession() -> DecisionSessionViewModel? {
        guard let scenarioID = remediationScenarioID else { return nil }
        return makeRemediationSession(scenarioID)
    }

    private func decisionAction() -> DecisionAction {
        let to = BBAmount(centiBB: Int((actionToBB * 100).rounded()))
        switch actionVerb {
        case .fold: return .fold
        case .check: return .check
        case .call: return .call(to: to)
        case .bet: return .bet(to: to)
        case .raise: return .raise(to: to)
        }
    }
}

/// Reads a rejection into the field it names, so the user is pointed at the
/// input to fix.
private func message(for error: ConstructedSpotError) -> String {
    switch error {
    case let .unparseableCard(code):
        "无法识别的牌：\(code)"
    case .duplicateCards:
        "两张手牌必须是不同的牌"
    case .nonPositiveStack:
        "有效筹码必须为正"
    case .seatOutOfRange:
        "座位超出六人桌范围"
    }
}

/// The manual scenario builder screen, reached from Hand Lab.
///
/// A hand-built spot is a review-time tool the same way an imported hand is, so
/// it lives under 复盘 → 牌局实验室 rather than a primary tab.
struct ScenarioBuilderView: View {
    /// The remediation the user tapped into. A dedicated type, not a bare
    /// `String`, so this destination stays independent of any `String`
    /// destination higher in the stack — the same care `HandAnalysisView` takes.
    private struct RemediationRoute: Identifiable, Hashable {
        let scenarioID: String
        var id: String { scenarioID }
    }

    @State private var viewModel: ScenarioBuilderViewModel
    @State private var remediationRoute: RemediationRoute?

    init(viewModel: ScenarioBuilderViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inputs
                Button("构造") {
                    viewModel.build()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("scenarioBuilder.build")

                if let error = viewModel.validationError {
                    Text(message(for: error))
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("scenarioBuilder.error")
                }

                if let coverage = viewModel.coverage {
                    result(coverage)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("构造场景")
        .navigationDestination(item: $remediationRoute) { route in
            if let session = viewModel.remediationSession() {
                DecisionSessionView(viewModel: session)
            } else {
                Text("无法开始训练")
            }
        }
    }

    @ViewBuilder
    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(
                "位置偏移 \(viewModel.heroSeatOffsetFromButton)（0=BTN）",
                value: $viewModel.heroSeatOffsetFromButton,
                in: 0 ... 5
            )
            .accessibilityIdentifier("scenarioBuilder.seat")

            HStack {
                TextField("第一张牌", text: $viewModel.firstCardCode)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scenarioBuilder.card1")
                TextField("第二张牌", text: $viewModel.secondCardCode)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scenarioBuilder.card2")
            }

            Picker("面对", selection: $viewModel.facing) {
                Text("未开池").tag(FacingAction.unopened)
                Text("面对加注").tag(FacingAction.singleRaise)
                Text("面对再加注").tag(FacingAction.reraise)
            }
            .accessibilityIdentifier("scenarioBuilder.facing")

            Stepper(
                "有效筹码 \(viewModel.effectiveStackBB) BB",
                value: $viewModel.effectiveStackBB,
                in: 1 ... 500
            )
            .accessibilityIdentifier("scenarioBuilder.stack")

            Picker("行动", selection: $viewModel.actionVerb) {
                ForEach(ScenarioBuilderAction.allCases) { verb in
                    Text(verb.label).tag(verb)
                }
            }
            .accessibilityIdentifier("scenarioBuilder.action")
        }
    }

    @ViewBuilder
    private func result(_ coverage: NodeCoverage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch coverage {
            case let .covered(scenarioID, weightBasisPoints):
                Text("内容对照 \(scenarioID)")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("scenarioBuilder.coveredScenario")
                Text("内容频率 \(weightBasisPoints / 100)%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scenarioBuilder.comparison")
                Button("练这个漏洞") {
                    if let scenarioID = viewModel.remediationScenarioID {
                        remediationRoute = RemediationRoute(scenarioID: scenarioID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("scenarioBuilder.remediate")
            case .uncovered:
                Text("无内容可对照")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scenarioBuilder.comparison")
            }

            Button("保存场景") {
                Task { await viewModel.save() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("scenarioBuilder.save")

            if viewModel.savedIdentity != nil {
                Text("已保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scenarioBuilder.saved")
            }
        }
    }
}
