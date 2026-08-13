/// One row of a tournament's blind structure.
///
/// Amounts are plain integer chips, not `BBAmount`: `BBAmount` is centi-BB, a
/// cash-game unit where one big blind is a fixed 100. In a tournament the big
/// blind is chips and it climbs every level, so "how many big blinds do I
/// have" is a computed depth (`effectiveBigBlinds`), not a stored unit.
///
/// This is a plain memberwise value with no validation of its own; a single
/// row cannot tell whether it is consistent with the rows around it. All
/// validation lives in `BlindSchedule.init`.
public struct BlindLevel: Hashable, Sendable, Codable {
    public let level: Int
    public let smallBlindChips: Int
    public let bigBlindChips: Int
    public let anteChips: Int

    public init(level: Int, smallBlindChips: Int, bigBlindChips: Int, anteChips: Int) {
        self.level = level
        self.smallBlindChips = smallBlindChips
        self.bigBlindChips = bigBlindChips
        self.anteChips = anteChips
    }
}
