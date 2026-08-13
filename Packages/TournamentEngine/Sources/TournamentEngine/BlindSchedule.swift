public enum BlindScheduleError: Error, Equatable, Sendable {
    case empty
    case levelsNotStartingAtOne
    case levelsNotConsecutive
    case bigBlindNotStrictlyIncreasing(level: Int)
    case smallBlindExceedsBigBlind(level: Int)
    case nonPositiveBigBlind(level: Int)
    case negativeAnte(level: Int)
    case negativeSmallBlind(level: Int)
}

public struct BlindSchedule: Hashable, Sendable {
    public let levels: [BlindLevel]

    public init(levels: [BlindLevel]) throws {
        guard let first = levels.first else { throw BlindScheduleError.empty }
        guard first.level == 1 else { throw BlindScheduleError.levelsNotStartingAtOne }

        // Structural check first: the levels must be 1, 2, 3, … with no gap.
        for (offset, level) in levels.enumerated() {
            guard level.level == offset + 1 else { throw BlindScheduleError.levelsNotConsecutive }
        }

        // Then each row's own well-formedness, before comparing rows to each
        // other. Ordering these three ahead of the cross-level increasing check
        // is what lets a big blind of zero surface as `.nonPositiveBigBlind`
        // rather than masquerading as a non-increasing step.
        for level in levels {
            guard level.bigBlindChips > 0 else {
                throw BlindScheduleError.nonPositiveBigBlind(level: level.level)
            }
            guard level.anteChips >= 0 else { throw BlindScheduleError.negativeAnte(level: level.level) }
            guard level.smallBlindChips >= 0 else {
                throw BlindScheduleError.negativeSmallBlind(level: level.level)
            }
            guard level.smallBlindChips <= level.bigBlindChips else {
                throw BlindScheduleError.smallBlindExceedsBigBlind(level: level.level)
            }
        }

        for pair in zip(levels, levels.dropFirst()) {
            guard pair.1.bigBlindChips > pair.0.bigBlindChips else {
                throw BlindScheduleError.bigBlindNotStrictlyIncreasing(level: pair.1.level)
            }
        }

        self.levels = levels
    }

    public func level(atHandIndex handIndex: Int, handsPerLevel: Int) -> BlindLevel {
        precondition(handIndex >= 0, "Hand index cannot be negative")
        precondition(handsPerLevel >= 1, "Hands per level must be at least one")
        return levels[min(handIndex / handsPerLevel, levels.count - 1)]
    }
}
