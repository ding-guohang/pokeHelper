/// How far a played action sat from a range table that folds it.
///
/// A range table gives the hero's line a weight out of 10,000 basis points;
/// the magnitude of the deviation is simply how much of that weight is missing.
/// A line the range never takes (weight 0) is a deviation of the full 10,000; a
/// line it always takes (weight 10,000) is no deviation at all. The function is
/// a strict decreasing function of the weight, which is the only property the
/// key-node ordering depends on.
func deviationMagnitude(weightBasisPoints: Int) -> Int {
    10_000 - weightBasisPoints
}
