public func effectiveBigBlinds(chips: Int, level: BlindLevel) -> Int {
    precondition(chips >= 0, "Chip count cannot be negative")
    return chips / level.bigBlindChips
}
