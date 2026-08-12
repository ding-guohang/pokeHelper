import Foundation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent
import XCTest
@testable import PokerCoach

/// The frequency report as a screen reads it.
///
/// `SessionFrequencyReportTests` owns the arithmetic — the counts, the
/// baselines and the threshold. What is left, and what this covers, is the part
/// a user actually sees: which rows are allowed to state a conclusion, which
/// ones say why they are not, and that a position the content is silent about
/// stays silent rather than being given a zero.
final class SessionFrequencyReportPresentationTests: XCTestCase {
    /// Enough hands that some spot clears the thirty-opportunity threshold and
    /// some spot does not. Both halves are asserted below, so a change that
    /// made every row thin or every row thick fails here rather than quietly
    /// removing a branch from the test.
    private let sessionCount = 8
    private let handsPerSession = 60

    @MainActor
    func testThinRowsSayWhyTheyAreQuietAndThickRowsGiveTheGap() async throws {
        let pack = try SessionReviewFixture.corePack()
        let viewModel = SessionFrequencyReportViewModel(
            sessionStore: try await playedStore(),
            strategyProvider: InMemoryStrategyPackProvider(pack: pack)
        )
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.rows.isEmpty, "报告一行都没有，下面全是空转")

        let thin = viewModel.rows.filter { $0.withheldText != nil }
        let thick = viewModel.rows.filter { $0.withheldText == nil }
        XCTAssertFalse(thin.isEmpty, "没有样本不足的行")
        XCTAssertFalse(thick.isEmpty, "没有样本足够的行")

        for row in thin {
            XCTAssertEqual(row.withheldText, "样本不足，暂不比较")
            XCTAssertNil(row.deltaText, "\(row.id) 样本不足却给了差值")
            XCTAssertNil(row.leakText, "\(row.id) 样本不足却被列为漏洞")
            // It still counts. Withholding the verdict is not withholding the
            // row: "you have played this spot eight times" is the finding.
            XCTAssertTrue(row.opportunitiesText.hasSuffix("次机会"))
            XCTAssertFalse(row.frequencyText.isEmpty)
        }

        for row in thick where row.baselineText != nil {
            let deltaText = try XCTUnwrap(row.deltaText, "\(row.id) 样本足够、有基准，却没有差值")
            XCTAssertTrue(
                deltaText.hasPrefix("+") || deltaText.hasPrefix("−"),
                "差值没有带符号：\(deltaText)"
            )
            XCTAssertTrue(deltaText.hasSuffix("个百分点"), deltaText)
        }

        // Every leak is a row that was entitled to a verdict.
        for leak in viewModel.leakRows {
            XCTAssertNotNil(leak.baselineText)
            XCTAssertNotNil(leak.deltaText)
            XCTAssertTrue(["偏松", "偏紧"].contains(leak.leakText ?? ""))
        }
    }

    /// The shipped pack has no big-blind scenario. That row shows what the user
    /// did and no baseline — not a 0.0% baseline, which would read as "never
    /// continue from the big blind".
    @MainActor
    func testAPositionTheContentIsSilentAboutGetsNoBaseline() async throws {
        let pack = try SessionReviewFixture.corePack()
        XCTAssertFalse(
            pack.entryBaselines.keys.contains {
                $0.heroSeatOffsetFromButton == 2 && $0.facing == .unopened
            },
            "内容里已经有大盲未面对下注的场景，这条断言换了对象"
        )

        let viewModel = SessionFrequencyReportViewModel(
            sessionStore: try await playedStore(),
            strategyProvider: InMemoryStrategyPackProvider(pack: pack)
        )
        await viewModel.refresh()

        let bigBlind = try XCTUnwrap(
            viewModel.rows.first { $0.id == "2-unopened" },
            "报告里没有大盲未面对下注这一行"
        )
        XCTAssertNil(bigBlind.baselineText)
        XCTAssertNil(bigBlind.deltaText)
        XCTAssertNil(bigBlind.leakText)
        XCTAssertGreaterThan(bigBlind.opportunitiesText.count, 0)
        XCTAssertFalse(bigBlind.frequencyText.isEmpty)

        // And some other row does have one, so "no baseline" is a property of
        // this row rather than of the whole report.
        XCTAssertTrue(viewModel.rows.contains { $0.baselineText != nil })
    }

    @MainActor
    func testWithNoContentInstalledEveryRowStillCountsAndNoneHasABaseline() async throws {
        let viewModel = SessionFrequencyReportViewModel(
            sessionStore: try await playedStore(),
            strategyProvider: UnavailableStrategyPackProvider()
        )
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded, "没有内容不是错误状态")
        XCTAssertFalse(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.rows.allSatisfy { $0.baselineText == nil })
        XCTAssertTrue(viewModel.rows.allSatisfy { $0.deltaText == nil })
        XCTAssertTrue(viewModel.leakRows.isEmpty)
        XCTAssertTrue(viewModel.rows.contains { $0.opportunitiesText != "0 次机会" })
    }

    /// Sessions on disk, played the way the app plays them.
    @MainActor
    private func playedStore() async throws -> FileSessionRecordStore {
        let store = try FileSessionRecordStore(
            directory: SessionReviewFixture.temporaryDirectory()
        )
        for seed in UInt64(1) ... UInt64(sessionCount) {
            let id = UUID()
            try await store.create(
                SessionRecord(id: id, seed: seed, handCount: handsPerSession)
            )
            try await SessionPlaythrough.play(sessionID: id, store: store)
        }
        return store
    }
}

/// Stands in for a build with nothing installed.
private struct UnavailableStrategyPackProvider: StrategyPackProviding {
    struct Missing: Error {}

    func pack() async throws -> StrategyPack { throw Missing() }
    func scenario(id: String) async throws -> DecisionScenario { throw Missing() }
}
