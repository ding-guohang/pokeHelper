import Foundation
import Observation
import PokerCore
import SessionPersistence
import SessionSimulation
import StrategyContent

/// One line of the frequency report, as text.
struct SessionFrequencyRowPresentation: Identifiable, Equatable {
    let id: String
    let positionLabel: String
    let facingLabel: String
    let opportunitiesText: String
    let entriesText: String
    let frequencyText: String

    /// Absent when installed content says nothing about this spot. Absent, not
    /// "0.0%": the shipped pack has no big-blind scenario, and a zero baseline
    /// there reads as "never continue from the big blind".
    let baselineText: String?

    /// Absent on a thin sample as well as on a missing baseline. The report
    /// counts either way; it only concludes when there is something to
    /// conclude from.
    let deltaText: String?

    /// What the row says instead of a verdict, when it is not entitled to one.
    let withheldText: String?

    let leakText: String?

    var isLeak: Bool { leakText != nil }
}

/// The hero's realized preflop frequencies across every recorded session,
/// beside the installed content's ranges.
///
/// Reads the hands off disk on every refresh. The counting itself is
/// `SessionFrequencyReport`, in the infrastructure layer, because it needs both
/// the session records and the strategy pack; this type only turns its integers
/// into strings and holds the loading state.
@MainActor
@Observable
final class SessionFrequencyReportViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private(set) var rows: [SessionFrequencyRowPresentation] = []
    private(set) var leakRows: [SessionFrequencyRowPresentation] = []

    /// Stated on the screen so the threshold is a rule the user can see rather
    /// than a reason some rows are quiet.
    let sampleRuleText =
        "少于 \(SessionFrequencyReport.minimumOpportunities) 次机会的位置只报计数，不与基准比较。"

    private let sessionStore: FileSessionRecordStore
    private let strategyProvider: any StrategyPackProviding

    init(
        sessionStore: FileSessionRecordStore,
        strategyProvider: any StrategyPackProviding
    ) {
        self.sessionStore = sessionStore
        self.strategyProvider = strategyProvider
    }

    func refresh() async {
        state = .loading
        do {
            // A pack that will not load is "no content installed", which the
            // report has a defined answer for — counts, no baselines — and not
            // a failure. Only an unreadable session store is a failure.
            let pack = try? await strategyProvider.pack()
            let report = try await SessionFrequencyReport.make(
                store: sessionStore,
                installedContent: pack
            )
            rows = report.rows.map(Self.present)
            leakRows = report.leaks.map(Self.present)
            state = .loaded
        } catch {
            rows = []
            leakRows = []
            state = .failed(message: "频率报告暂时无法读取，请重试")
        }
    }

    private static func present(
        _ row: SessionFrequencyRow
    ) -> SessionFrequencyRowPresentation {
        let position = row.position?.label ?? "位置 \(row.key.heroSeatOffsetFromButton)"
        let facing = switch row.key.facing {
        case .unopened: "无人加注"
        case .singleRaise: "面对加注"
        case .reraise: "面对再加注"
        }

        let leakText: String? = switch row.leak {
        case .loose: "偏松"
        case .tight: "偏紧"
        case nil: nil
        }

        return SessionFrequencyRowPresentation(
            id: "\(row.key.heroSeatOffsetFromButton)-\(row.key.facing.rawValue)",
            positionLabel: position,
            facingLabel: facing,
            opportunitiesText: "\(row.opportunities) 次机会",
            entriesText: "入池 \(row.entries) 次",
            frequencyText: StrategyNumberText.frequency(
                basisPoints: row.frequencyBasisPoints
            ),
            baselineText: row.baselineBasisPoints
                .map { StrategyNumberText.frequency(basisPoints: $0) },
            deltaText: row.deltaBasisPoints.map(deltaText),
            withheldText: row.hasEnoughOpportunities ? nil : "样本不足，暂不比较",
            leakText: leakText
        )
    }

    /// Signed percentage points, always carrying its sign — a delta printed
    /// without one reads as a second frequency.
    private static func deltaText(_ basisPoints: Int) -> String {
        let sign = basisPoints < 0 ? "−" : "+"
        let tenths = (abs(basisPoints) + 5) / 10
        return "\(sign)\(tenths / 10).\(tenths % 10) 个百分点"
    }
}
