import HandHistory
import HandHistoryPersistence
import StrategyContent
import SwiftUI

/// The Hand Lab tab: paste a hand history, review the standardized preview, and
/// adopt it into the personal library.
///
/// Without a writable library directory there is nowhere to keep adopted hands,
/// so the tab says so rather than offering an import that cannot finish — the
/// same discipline the training tab uses when its session store is missing.
struct HandLabView: View {
    let dependencies: AppDependencies

    @State private var viewModel: HandImportViewModel?
    /// Held so analysis reuses the one store this session opened. Reopening it
    /// through `HandLabStorage.makeStore()` would re-honour `--reset-hand-library`
    /// and wipe the hand the user just adopted; the analysis path takes this
    /// instance instead.
    @State private var libraryStore: FileHandLibraryStore?

    var body: some View {
        Group {
            if let viewModel, let libraryStore {
                HandLabContentView(
                    viewModel: viewModel,
                    makeAnalysisViewModel: { identity, tableSize in
                        makeAnalysisViewModel(
                            store: libraryStore,
                            identity: identity,
                            tableSize: tableSize
                        )
                    }
                )
            } else {
                ContentUnavailableView(
                    "牌局实验室",
                    systemImage: "tray.and.arrow.down",
                    description: Text("本地牌库不可用，无法导入牌谱。")
                )
            }
        }
        .navigationTitle("牌局实验室")
        .task {
            if viewModel == nil {
                let store = try? HandLabStorage.makeStore()
                libraryStore = store
                viewModel = makeViewModel(store: store)
                await viewModel?.refreshLibrary()
            }
        }
    }

    private func makeViewModel(store: FileHandLibraryStore?) -> HandImportViewModel? {
        guard let store else { return nil }
        let coordinator = HandImportCoordinator(
            libraryStore: store,
            eventStore: dependencies.eventStore
        )
        return HandImportViewModel(coordinator: coordinator)
    }

    /// Builds the analysis view model for one stored hand.
    ///
    /// The matcher is built from the preferred installed pack — reviewed content
    /// ahead of any development fixture — so an imported line is judged against
    /// the same range tables a shipping build trains on, not the demo pack. The
    /// coordinator holds the event store and never writes it; analysis is a read.
    private func makeAnalysisViewModel(
        store: FileHandLibraryStore,
        identity: String,
        tableSize: Int
    ) -> HandAnalysisViewModel {
        let preferredPack = try? BundledContentLoader(bundle: .main).loadPreferredPack()
        let coordinator = HandAnalysisCoordinator(
            libraryStore: store,
            eventStore: dependencies.eventStore,
            matcher: ImportedHandContentMatcher(scenarios: preferredPack?.pack.scenarios ?? [])
        )
        return HandAnalysisViewModel(
            coordinator: coordinator,
            identity: identity,
            tableSize: tableSize,
            makeRemediationSession: { scenarioID in
                makeRemediationSession(scenarioID: scenarioID, pack: preferredPack?.pack)
            }
        )
    }

    /// The training session that drills a remediation scenario.
    ///
    /// Remediation is the ordinary training flow — the real scorer, event store
    /// and local identity — so the event it records is a plain training event,
    /// indistinguishable from one produced by starting the same scenario
    /// directly. It trains against the *preferred pack*, the very content the
    /// analysis matcher judged the imported line against, so the drill is the
    /// exact spot the deviation was measured at. In a shipping build that pack is
    /// also `dependencies.strategyProvider`'s, so this is
    /// `dependencies.makeDecisionSessionViewModel` by another name; a development
    /// build's training tab carries a different fixture pack, but the flagged
    /// spot lives in the reviewed content, and remediation follows it there
    /// rather than to a scenario the fixture happens not to contain.
    private func makeRemediationSession(
        scenarioID: String,
        pack: StrategyPack?
    ) -> DecisionSessionViewModel {
        let provider: any StrategyPackProviding = pack
            .map { InMemoryStrategyPackProvider(pack: $0) }
            ?? dependencies.strategyProvider
        return DecisionSessionViewModel(
            scenarioID: scenarioID,
            strategyProvider: provider,
            scorer: dependencies.scorer,
            eventStore: dependencies.eventStore,
            localUserID: dependencies.localUserID,
            deviceID: dependencies.deviceID
        )
    }
}

/// The working surface, shown once the library is available.
///
/// ## Identifiers sit on leaves
///
/// Every `accessibilityIdentifier` here is on a `Text` or `Button`, never on a
/// stack, so it names one element rather than renaming everything inside a
/// container.
private struct HandLabContentView: View {
    @Bindable var viewModel: HandImportViewModel
    /// Builds the analysis view model for a stored hand, injected so the content
    /// view stays unaware of how the coordinator and content matcher are wired.
    let makeAnalysisViewModel: (_ identity: String, _ tableSize: Int) -> HandAnalysisViewModel

    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importEntry
                if let message = viewModel.unsupportedMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("handlab.unsupported")
                }
                if !viewModel.unresolvedConflicts.isEmpty {
                    conflicts
                }
                if let preview = viewModel.preview {
                    previewSection(preview)
                }
                library
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var importEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入牌谱")
                .font(.headline)
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.4))
                )
                .accessibilityIdentifier("handlab.text")
            HStack {
                Button("解析") {
                    viewModel.load(text: text)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("handlab.parse")

#if DEVELOPMENT_STRATEGY_FIXTURES
                Button("载入示例") {
                    text = HandImportSampleText.appendixA
                    viewModel.load(text: text)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("handlab.loadSample")

                Button("载入偏离示例") {
                    text = HandImportSampleText.appendixG
                    viewModel.load(text: text)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("handlab.loadDeviationSample")
#endif
            }
        }
    }

    private var conflicts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要确认的字段")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("handlab.conflicts.title")
            ForEach(viewModel.unresolvedConflicts, id: \.self) { conflict in
                Text("第 \(conflict.sourceLine) 行 · \(conflict.field)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("handlab.conflict.\(conflict.sourceLine)")
            }
            Text("含未解决字段的牌谱无法采纳。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewSection(_ preview: HandImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("标准化预览")
                .font(.headline)

            Text("英雄位置 \(preview.heroPosition)")
                .font(.subheadline)
                .accessibilityIdentifier("handlab.preview.heroPosition")

            ForEach(preview.seats) { seat in
                Text("\(seat.position) · \(seat.startingStack) · \(seat.holeCards)")
                    .font(.footnote.monospacedDigit())
                    .accessibilityIdentifier("handlab.preview.seat.\(seat.seat)")
            }

            ForEach(preview.streets) { street in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(street.name) \(street.board)")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("handlab.preview.\(street.street.rawValue).board")
                    ForEach(Array(street.actions.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.footnote)
                            .accessibilityIdentifier(
                                "handlab.preview.\(street.street.rawValue).action.\(index)"
                            )
                    }
                }
            }

            Text("抽水 \(preview.rake)")
                .font(.footnote)
                .accessibilityIdentifier("handlab.preview.rake")

            Button("采纳到牌库") {
                Task { try? await viewModel.accept() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAccept)
            .accessibilityIdentifier("handlab.accept")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("牌库")
                .font(.headline)
            Text("共 \(viewModel.libraryHands.count) 手")
                .font(.subheadline)
                .accessibilityIdentifier("handlab.library.count")
            ForEach(Array(viewModel.libraryHands.enumerated()), id: \.offset) { index, hand in
                HStack {
                    Text("\(hand.preview.heroPosition) · 抽水 \(hand.preview.rake)")
                        .font(.footnote.monospacedDigit())
                        .accessibilityIdentifier("handlab.library.row.\(index)")
                    Spacer()
                    NavigationLink {
                        HandAnalysisView(
                            viewModel: makeAnalysisViewModel(hand.identity, hand.tableSize)
                        )
                    } label: {
                        Text("分析")
                    }
                    .accessibilityIdentifier("handlab.analyze.\(index)")
                }
            }
        }
    }
}
