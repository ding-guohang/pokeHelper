import Observation
import TournamentEngine

/// Drives the tournament ICM calculator: parses the user's chip and payout
/// input, runs the content-free engine, and holds display strings.
///
/// It computes nothing itself — every number comes from `ICMCalculator` /
/// `ICMPressure` on exact `Fraction`s and is turned to text only in
/// `TournamentICMPresentation`. It is a calculator, not training: it scores no
/// action, suggests no range, and produces no `TrainingEvent`.
@MainActor
@Observable
final class TournamentICMViewModel {
    var stacksInput = ""
    var payoutsInput = ""
    var heroSeatInput = ""
    var bigBlindInput = ""
    var pushFoldThresholdInput = ""

    private(set) var equityLines: [String] = []
    /// One line per seat when a big blind is set: the seat's effective depth in
    /// big blinds, optionally flagged as a disclosed jam-or-fold zone.
    private(set) var depthLines: [DepthLine] = []
    /// One line per opponent seat when a hero seat is set: the bubble factor of
    /// the hero against that seat, or a readable reason if it cannot be formed.
    private(set) var bubbleFactorLines: [BubbleFactorLine] = []
    private(set) var errorText: String?

    struct DepthLine: Identifiable {
        let seat: Int
        let text: String
        var id: Int { seat }
    }

    struct BubbleFactorLine: Identifiable {
        let opponentSeat: Int
        let text: String
        var id: Int { opponentSeat }
    }

    private static let decimalPlaces = 2

    func compute() {
        equityLines = []
        depthLines = []
        bubbleFactorLines = []
        errorText = nil

        guard let stacks = Self.parseIntegers(stacksInput) else {
            errorText = "筹码需为逗号分隔的整数，例如 1000,2000,3000。"
            return
        }
        guard let payouts = Self.parseIntegers(payoutsInput) else {
            errorText = "派彩需为逗号分隔的整数，例如 500,300,200。"
            return
        }

        let equities: [Fraction]
        do {
            equities = try ICMCalculator.equities(chipStacks: stacks, payouts: payouts)
        } catch let error as ICMError {
            errorText = TournamentICMPresentation.message(for: error)
            return
        } catch {
            errorText = "计算失败。"
            return
        }

        equityLines = equities.enumerated().map { index, equity in
            "座位 \(index)：\(TournamentICMPresentation.decimalString(equity, places: Self.decimalPlaces))"
        }

        // Effective depth is optional: only when the user gives a big blind.
        // A push/fold threshold, if also given, flags the disclosed jam-or-fold
        // zone — the engine endorses no threshold and offers no range.
        if !computeDepth(stacks: stacks) { return }

        // The bubble factor is optional: only when the user names a hero seat.
        // Then the hero is measured against every other seat — the pro's read
        // of who they can and cannot afford to clash with.
        let hero = heroSeatInput.trimmingCharacters(in: .whitespaces)
        guard !hero.isEmpty else { return }
        guard let heroIndex = Int(hero), heroIndex >= 0, heroIndex < stacks.count else {
            errorText = "英雄座位需为 0 到 \(stacks.count - 1) 之间的整数。"
            return
        }

        for opponentIndex in stacks.indices where opponentIndex != heroIndex {
            let text: String
            do {
                let bubbleFactor = try ICMPressure.bubbleFactor(
                    chipStacks: stacks,
                    payouts: payouts,
                    heroIndex: heroIndex,
                    opponentIndex: opponentIndex
                )
                text = "对 座位 \(opponentIndex)：\(TournamentICMPresentation.decimalString(bubbleFactor, places: Self.decimalPlaces))"
            } catch let error as ICMError {
                // A single opponent that cannot be formed (e.g. flat payouts →
                // noEquityGain) shows its reason inline without aborting the rest.
                text = "对 座位 \(opponentIndex)：\(TournamentICMPresentation.message(for: error))"
            } catch {
                text = "对 座位 \(opponentIndex)：计算失败。"
            }
            bubbleFactorLines.append(BubbleFactorLine(opponentSeat: opponentIndex, text: text))
        }
    }

    /// Fills `depthLines` from the optional big blind and push/fold threshold.
    /// Returns false (and sets `errorText`) if an input is malformed, so the
    /// caller can stop.
    private func computeDepth(stacks: [Int]) -> Bool {
        let bigBlindTrimmed = bigBlindInput.trimmingCharacters(in: .whitespaces)
        guard !bigBlindTrimmed.isEmpty else { return true }
        guard let bigBlind = Int(bigBlindTrimmed), bigBlind > 0 else {
            errorText = "大盲（筹码）需为正整数。"
            return false
        }
        let level = BlindLevel(level: 1, smallBlindChips: bigBlind / 2, bigBlindChips: bigBlind, anteChips: 0)

        let thresholdTrimmed = pushFoldThresholdInput.trimmingCharacters(in: .whitespaces)
        var threshold: Int?
        if !thresholdTrimmed.isEmpty {
            guard let parsed = Int(thresholdTrimmed), parsed >= 0 else {
                errorText = "push/fold 阈值（BB）需为非负整数。"
                return false
            }
            threshold = parsed
        }

        for (index, stack) in stacks.enumerated() {
            var text = "座位 \(index)：\(effectiveBigBlinds(chips: stack, atLevel: level)) BB"
            if let threshold {
                do {
                    // Stack > 0 is guaranteed: equities already rejected nonPositiveStack.
                    let context = try PushFoldContext(effectiveChips: stack, level: level)
                    if try context.isAtOrBelow(thresholdBigBlinds: threshold) {
                        text += "（push/fold 区：全下/弃牌模型）"
                    }
                } catch let error as PushFoldError {
                    errorText = Self.pushFoldMessage(for: error)
                    return false
                } catch {
                    errorText = "计算失败。"
                    return false
                }
            }
            depthLines.append(DepthLine(seat: index, text: text))
        }
        return true
    }

    private static func pushFoldMessage(for error: PushFoldError) -> String {
        switch error {
        case .nonPositiveEffectiveStack: "筹码必须为正整数。"
        case .nonPositiveBigBlind: "大盲（筹码）需为正整数。"
        case .negativeThreshold: "push/fold 阈值（BB）不能为负。"
        case .thresholdOverflow: "阈值过大，超出计算范围。"
        }
    }

    /// Parses a comma-separated list of integers, or nil if empty or any entry
    /// is not a plain integer.
    private static func parseIntegers(_ input: String) -> [Int]? {
        let pieces = input
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !pieces.isEmpty else { return nil }
        var values: [Int] = []
        for piece in pieces {
            guard let value = Int(piece) else { return nil }
            values.append(value)
        }
        return values
    }
}
