import Foundation
import PokerCore
import StrategyContent
import Testing
@testable import StrategyToolingCore

/// Checks that content means what it says it means.
///
/// Every defect below passed `StrategyPackValidator` and the release gate and
/// reached a human reviewer, who caught all of them by hand. The validator
/// only enforces narrow internal consistency — frequencies total 10,000,
/// actions are legal — and none of these violate that. A reviewer's time
/// should go on strategy judgement, not on arithmetic a machine can do.
@Suite("内容自洽性审计")
struct ContentAuditTests {
    // The hero holds one specific hand. `options` describes the strategy for
    // that hand, and the range cell covering it must say the same thing.
    //
    // The shipped content had range-wide RFI percentages in `options`: UTG with
    // AKo listed raise 17.6% / fold 82.4% while its range cell said AKo raises
    // 100%. The app grades from `options`, so it would have taught that folding
    // AKo under the gun is the 82% play while simultaneously grading it a
    // blunder on EV.
    @Test("固定手牌的 options 频率必须等于该手牌的范围表格子")
    func optionFrequenciesMatchTheHeroHandsRangeCell() throws {
        for (pack, node) in try allNodes() {
            guard let cell = ContentAudit.rangeCell(
                forHeroHand: node.heroCards,
                in: node.rangeCells
            ) else {
                Issue.record(
                    Comment(rawValue: "\(pack)/\(node.id)：范围表里没有覆盖英雄手牌的格子")
                )
                continue
            }

            for action in node.actions {
                let key = ContentAudit.rangeKey(for: action.action)
                let weight = cell.actionWeightsBasisPoints[key] ?? 0
                #expect(
                    weight == action.frequencyBasisPoints,
                    Comment(rawValue: "\(pack)/\(node.id)：\(key) 在 options 里是 "
                        + "\(action.frequencyBasisPoints)，在 \(cell.handClass) "
                        + "的范围表里是 \(weight)")
                )
            }
        }
    }

    // A scenario's prose states a range-wide frequency. Option frequencies are
    // per-hand, so this is the only surviving claim about the whole range, and
    // the range table has to actually weigh that much.
    @Test("解释里声明的整段频率必须等于范围表的组合加权")
    func proseFrequencyMatchesTheRangeTable() throws {
        for (pack, node) in try allNodes() {
            // A node answering a raise states its continuation elsewhere; an
            // opening node without a percentage in its conclusion is a node
            // whose claim nobody can check, which is worse than a wrong one.
            guard node.facingRaiseTo == nil else { continue }
            guard let stated = ContentAudit.statedFrequencyBasisPoints(
                in: node.explanation.conclusion
            ) else {
                Issue.record(
                    Comment(rawValue: "\(pack)/\(node.id)：结论里没有百分比，整段频率无从校验")
                )
                continue
            }

            let actual = ContentAudit.combinationWeightedBasisPoints(node.rangeCells)
            let drift = abs(actual - stated)

            // 25 basis points, against observed drift of 1 to 6. The previous
            // 100 left enough slack to add an entire offsuit hand class -- 12
            // combinations at full weight is 90 basis points -- without the
            // rule noticing.
            #expect(
                drift <= 25,
                Comment(rawValue: "\(pack)/\(node.id)：解释声明 \(Double(stated) / 100)%，"
                    + "范围表实际 \(Double(actual) / 100)%")
            )
        }
    }

    // The label a reader sees comes from TablePosition, not from the title the
    // author typed. Four of six nodes disagreed: a node titled "CO" sat at
    // offset 1, which a six-handed table renders as SB.
    @Test("场景标题里的位置必须与 heroSeatOffsetFromButton 解析结果一致")
    func titlesAgreeWithTheResolvedPosition() throws {
        for (pack, export, node) in try allNodesWithExport() {
            let resolved = try TablePosition(
                tableSize: export.tableSize,
                heroSeatOffsetFromButton: node.heroSeatOffsetFromButton
            )
            guard let claimed = ContentAudit.positionMentioned(in: node.title) else {
                Issue.record(
                    Comment(rawValue: "\(pack)/\(node.id)：标题没有写明位置，无法校验")
                )
                continue
            }
            #expect(
                claimed == resolved.label,
                Comment(rawValue: "\(pack)/\(node.id)：标题写 \(claimed)，offset "
                    + "\(node.heroSeatOffsetFromButton) 在 \(export.tableSize) "
                    + "人桌解析为 \(resolved.label)")
            )
        }
    }

    // The pack declares its bet tree in prose. Every sizing a scenario actually
    // uses has to appear in it, or the declaration describes a different game.
    @Test("场景使用的尺度必须出现在声明的下注树里")
    func everySizingAppearsInTheDeclaredBetTree() throws {
        for (pack, export, node) in try allNodesWithExport() {
            let declared = ContentAudit.declaredSizesBB(
                export.allowedBetSizeDescription
            )
            // facingRaiseTo is checked alongside the action sizes: it feeds the
            // minimum-defence calculation, so a value outside the declared tree
            // silently changes what that gate demands.
            var used = node.actions.compactMap {
                ContentAudit.targetCentiBB($0.action)
            }
            if let facing = node.facingRaiseTo {
                used.append(facing.centiBB)
            }

            for toCentiBB in used {
                let sizeBB = Double(toCentiBB) / 100
                #expect(
                    declared.contains(where: { abs($0 - sizeBB) < 0.01 }),
                    Comment(rawValue: "\(pack)/\(node.id)：使用了 \(sizeBB)BB，"
                        + "但声明的下注树是 \(export.allowedBetSizeDescription)")
                )
            }
        }
    }

    // A hand can only face a 3bet if the opening range contained it. The CO
    // opening range stopped at A9s while the facing-a-3bet node had A5s
    // four-betting half the time — a branch no player can reach.
    @Test("后续节点引用的手牌必须在前序开池范围内")
    func laterNodesOnlyReferenceHandsTheOpeningRangeContains() throws {
        let export = try coreExport()
        guard let opening = export.nodes.first(where: { $0.id == "rfi-co" }),
              let facing = export.nodes.first(where: { $0.id == "vs3bet-co-vs-btn" })
        else {
            Issue.record("找不到 CO 开池或 CO 面对 3bet 节点")
            return
        }

        let opened = ContentAudit.handsWithNonZeroAggression(opening.rangeCells)
        for cell in facing.rangeCells {
            for hand in ContentAudit.expand(cell.handClass) {
                #expect(
                    opened.contains(hand),
                    Comment(rawValue: "vs3bet-co-vs-btn 引用了 \(hand)，"
                        + "但 rfi-co 的开池范围不含它")
                )
            }
        }
    }

    // A hand is played as a mix because the lines are worth about the same. If
    // one carries a much better EV, the scorer marks the other an error while
    // the chart calls both correct — the content contradicts itself.
    @Test("混合策略手牌的各行动 EV 必须接近")
    func mixedHandsHaveComparableExpectedValues() throws {
        for (pack, node) in try allNodes() {
            let played = node.actions.filter { $0.frequencyBasisPoints > 0 }
            guard played.count > 1 else { continue }

            let values = played.map { $0.ev.milliBB }
            let spread = (values.max() ?? 0) - (values.min() ?? 0)
            let pot = node.pot.centiBB * 10
            let lossRateBasisPoints = spread * 10_000 / max(pot, 1)

            // 10 basis points is the top of DecisionScorer's `excellent` band.
            // A mix whose spread exceeds it has the app telling a user that the
            // chart-sanctioned line they picked was merely acceptable — i.e.
            // second best — which is not what a mixed strategy means.
            #expect(
                lossRateBasisPoints <= 10,
                Comment(rawValue: "\(pack)/\(node.id)：混合行动的 EV 差为 \(spread) milliBB，"
                    + "折合 \(lossRateBasisPoints) bp，超过 acceptable 的上限")
            )
        }
    }

    // Position is the single largest driver of a preflop opening range. A
    // catalogue where a later seat opens no wider than an earlier one teaches
    // the opposite of the first thing this curriculum node exists to teach.
    @Test("越靠后的位置开池必须越宽")
    func openingRangesWidenWithPosition() throws {
        let export = try coreExport()

        // Derived from the export, not a hardcoded list: the previous literal
        // named four seats while five RFI nodes shipped, so SB could open
        // narrower than UTG unnoticed. The blinds are excluded because they act
        // last preflop and their ranges are not comparable to the others.
        let opening = export.nodes
            .filter { $0.curriculumNodeID == "preflop-rfi" }
            .filter { $0.heroSeatOffsetFromButton >= 3 || $0.heroSeatOffsetFromButton == 0 }
            .sorted { lhs, rhs in
                // Action order preflop: UTG(3) → HJ(4) → CO(5) → BTN(0).
                let order = { (seat: Int) in seat == 0 ? 99 : seat }
                return order(lhs.heroSeatOffsetFromButton) < order(rhs.heroSeatOffsetFromButton)
            }

        #expect(opening.count >= 4, "开池节点少于 4 个，单调性无从检验")

        let widths = opening.map {
            ($0.id, ContentAudit.combinationWeightedBasisPoints($0.rangeCells))
        }

        for (earlier, later) in zip(widths, widths.dropFirst()) {
            #expect(
                later.1 > earlier.1,
                Comment(rawValue: "\(later.0) 开 \(Double(later.1) / 100)%，"
                    + "不比更早的 \(earlier.0) 的 \(Double(earlier.1) / 100)% 宽")
            )
        }
    }

    // Facing a raise, folding more than the pot odds justify hands the raiser a
    // profit with any two cards. This is the one check that would have caught
    // the review's headline finding: CO continued 23.54% against a three-bet
    // that needed 34.78%, making a pure bluff worth +1.29BB.
    @Test("面对加注的继续率不得低于最小防守频率")
    func defenceMeetsTheMinimumDefenceFrequency() throws {
        let export = try coreExport()

        for node in export.nodes {
            // Declaring the raise faced is mandatory whenever there is one.
            // As a plain optional it could be deleted to switch this whole rule
            // off, with no other observable effect anywhere.
            //
            // Owing more than one big blind is what distinguishes facing a
            // raise from merely owing the blind: amounts are centi-BB, so 100
            // is exactly one big blind and an unopened pot never exceeds it.
            let bigBlind = 100
            if node.amountToCall.centiBB > bigBlind, node.facingRaiseTo == nil {
                Issue.record(
                    Comment(rawValue: "\(node.id)：应跟金额大于 0 却没有声明 "
                        + "facingRaiseTo，最小防守频率无从计算")
                )
                continue
            }
            guard let facingRaiseTo = node.facingRaiseTo else { continue }
            guard let opening = export.nodes.first(where: {
                $0.curriculumNodeID == "preflop-rfi"
                    && $0.heroSeatOffsetFromButton == node.heroSeatOffsetFromButton
            }) else {
                Issue.record("\(node.id)：找不到同位置的开池节点，无法计算继续率")
                continue
            }

            let risked = facingRaiseTo.centiBB
            let attacked = node.pot.centiBB - risked
            // Nothing else cross-checks the declared pot, and shrinking it
            // drives the required defence toward zero.
            #expect(
                attacked > 0,
                Comment(rawValue: "\(node.id)：底池 \(node.pot.centiBB) 不大于"
                    + " 面对的加注 \(risked)，最小防守频率会退化为 0")
            )
            // A pure bluff risks `risked` to win `attacked`, so it breaks even
            // at risked/(risked+attacked) folds. Defence has to cover the rest.
            let minimumContinueBasisPoints =
                attacked * 10_000 / (risked + attacked)

            let continued = ContentAudit.continuationBasisPoints(
                facing: node.rangeCells,
                openedWith: opening.rangeCells
            )

            #expect(
                continued >= minimumContinueBasisPoints,
                Comment(rawValue: "\(node.id)：继续率 \(Double(continued) / 100)%，"
                    + "低于最小防守频率 \(Double(minimumContinueBasisPoints) / 100)%；"
                    + "对手可以用任意两张牌加注获利")
            )
        }
    }

    /// Every shipped export, not just the core one. The depth pack rides on
    /// Debug and Dogfood and was previously subject to none of these rules.
    // `facing` and `facingRaiseTo` are both author-declared, and nothing so far
    // forces them to agree. They describe one fact from two angles: a node
    // answering no raise has no raise size, and a node naming a raise size is
    // answering a raise. Left uncrossed, a scenario could claim `.unopened`
    // while carrying a 3-bet to answer, and the frequency report would file it
    // under the open-raising baseline — the single mistake `facing` was added
    // to prevent.
    @Test("facing 与 facingRaiseTo 互相印证")
    func facingAgreesWithTheRaiseBeingAnswered() throws {
        var unopened = 0
        var answering = 0

        for (pack, node) in try allNodes() {
            switch node.facing {
            case .unopened:
                unopened += 1
                #expect(
                    node.facingRaiseTo == nil,
                    "\(pack)/\(node.id) 声明未面对下注，却带着 facingRaiseTo"
                )
            case .singleRaise, .reraise:
                answering += 1
                #expect(
                    node.facingRaiseTo != nil,
                    "\(pack)/\(node.id) 声明面对加注，却没有 facingRaiseTo"
                )
            }
        }

        // Both shapes must occur, or the crossing above is vacuous.
        #expect(unopened > 0, "没有任何未面对下注的节点，本检查空转")
        #expect(answering > 0, "没有任何面对加注的节点，本检查空转")
    }

    private func allNodes() throws -> [(String, SolverNode)] {
        try exports().flatMap { entry in
            entry.export.nodes.map { (entry.name, $0) }
        }
    }

    private func allNodesWithExport() throws -> [(String, SolverExport, SolverNode)] {
        try exports().flatMap { entry in
            entry.export.nodes.map { (entry.name, entry.export, $0) }
        }
    }

    /// Every shipped export. Enumerated from disk rather than listed, so a new
    /// export cannot be added without these rules applying to it — which is how
    /// the postflop pack shipped subject to none of them.
    private func exports() throws -> [(name: String, export: SolverExport)] {
        let directory = repositoryRoot().appending(path: "Content/exports")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path())
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()

        #expect(!names.isEmpty, "Content/exports 下没有任何导出")
        return try names.map { (name: $0, export: try load($0)) }
    }

    private func repositoryRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // StrategyToolingTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StrategyTooling
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
    }

    private func coreExport() throws -> SolverExport {
        try load("core-6max-100bb")
    }

    private func load(_ name: String) throws -> SolverExport {
        try PackBuilder.makeDecoder().decode(
            SolverExport.self,
            from: try Data(
                contentsOf: repositoryRoot()
                    .appending(path: "Content/exports/\(name).json")
            )
        )
    }
}
