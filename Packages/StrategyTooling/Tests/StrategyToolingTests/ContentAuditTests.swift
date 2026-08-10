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
        for node in try coreExport().nodes {
            guard let cell = ContentAudit.rangeCell(
                forHeroHand: node.heroCards,
                in: node.rangeCells
            ) else {
                Issue.record("\(node.id)：范围表里没有覆盖英雄手牌的格子")
                continue
            }

            for action in node.actions {
                let key = ContentAudit.rangeKey(for: action.action)
                let weight = cell.actionWeightsBasisPoints[key] ?? 0
                #expect(
                    weight == action.frequencyBasisPoints,
                    Comment(rawValue: "\(node.id)：\(key) 在 options 里是 "
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
        for node in try coreExport().nodes {
            guard let stated = ContentAudit.statedFrequencyBasisPoints(
                in: node.explanation.conclusion
            ) else {
                continue
            }

            let actual = ContentAudit.combinationWeightedBasisPoints(node.rangeCells)
            let drift = abs(actual - stated)

            #expect(
                drift <= 100,
                Comment(rawValue: "\(node.id)：解释声明 \(Double(stated) / 100)%，"
                    + "范围表实际 \(Double(actual) / 100)%")
            )
        }
    }

    // The label a reader sees comes from TablePosition, not from the title the
    // author typed. Four of six nodes disagreed: a node titled "CO" sat at
    // offset 1, which a six-handed table renders as SB.
    @Test("场景标题里的位置必须与 heroSeatOffsetFromButton 解析结果一致")
    func titlesAgreeWithTheResolvedPosition() throws {
        let export = try coreExport()
        for node in export.nodes {
            let resolved = try TablePosition(
                tableSize: export.tableSize,
                heroSeatOffsetFromButton: node.heroSeatOffsetFromButton
            )
            guard let claimed = ContentAudit.positionMentioned(in: node.title) else {
                Issue.record("\(node.id)：标题没有写明位置，无法校验")
                continue
            }
            #expect(
                claimed == resolved.label,
                Comment(rawValue: "\(node.id)：标题写 \(claimed)，offset "
                    + "\(node.heroSeatOffsetFromButton) 在 \(export.tableSize) "
                    + "人桌解析为 \(resolved.label)")
            )
        }
    }

    // The pack declares its bet tree in prose. Every sizing a scenario actually
    // uses has to appear in it, or the declaration describes a different game.
    @Test("场景使用的尺度必须出现在声明的下注树里")
    func everySizingAppearsInTheDeclaredBetTree() throws {
        let export = try coreExport()
        let declared = ContentAudit.declaredSizesBB(export.allowedBetSizeDescription)

        for node in export.nodes {
            for action in node.actions {
                guard let toCentiBB = ContentAudit.targetCentiBB(action.action) else {
                    continue
                }
                let sizeBB = Double(toCentiBB) / 100
                #expect(
                    declared.contains(where: { abs($0 - sizeBB) < 0.01 }),
                    Comment(rawValue: "\(node.id)：使用了 \(sizeBB)BB，"
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
        for node in try coreExport().nodes {
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
                Comment(rawValue: "\(node.id)：混合行动的 EV 差为 \(spread) milliBB，"
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
        // Order of action preflop, from first to act to last.
        let seatOrder = ["UTG", "HJ", "CO", "BTN"]

        let widths = try seatOrder.map { position -> (String, Int) in
            let node = try #require(
                export.nodes.first { $0.id == "rfi-\(position.lowercased())" },
                Comment(rawValue: "缺少 \(position) 的开池节点")
            )
            return (
                position,
                ContentAudit.combinationWeightedBasisPoints(node.rangeCells)
            )
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

    private func coreExport() throws -> SolverExport {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()   // StrategyToolingTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StrategyTooling
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
            .appending(path: "Content/exports/core-6max-100bb.json")

        return try PackBuilder.makeDecoder().decode(
            SolverExport.self,
            from: try Data(contentsOf: url)
        )
    }
}
