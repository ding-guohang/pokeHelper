public func effectiveBigBlinds(chips: Int, atLevel level: BlindLevel) -> Int {
    precondition(chips >= 0, "Chip count cannot be negative")
    return chips / level.bigBlindChips
}
