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
    var opponentSeatInput = ""

    private(set) var equityLines: [String] = []
    private(set) var bubbleFactorText: String?
    private(set) var errorText: String?

    private static let decimalPlaces = 2

    func compute() {
        equityLines = []
        bubbleFactorText = nil
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

        // The bubble factor is optional: only when the user names both seats.
        let hero = heroSeatInput.trimmingCharacters(in: .whitespaces)
        let opponent = opponentSeatInput.trimmingCharacters(in: .whitespaces)
        guard !hero.isEmpty || !opponent.isEmpty else { return }
        guard let heroIndex = Int(hero), let opponentIndex = Int(opponent) else {
            errorText = "英雄与对手座位需为整数。"
            return
        }
        do {
            let bubbleFactor = try ICMPressure.bubbleFactor(
                chipStacks: stacks,
                payouts: payouts,
                heroIndex: heroIndex,
                opponentIndex: opponentIndex
            )
            bubbleFactorText = TournamentICMPresentation.decimalString(bubbleFactor, places: Self.decimalPlaces)
        } catch let error as ICMError {
            errorText = TournamentICMPresentation.message(for: error)
        } catch {
            errorText = "计算失败。"
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
