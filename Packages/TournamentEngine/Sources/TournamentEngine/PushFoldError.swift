/// Why a push/fold context could not be built or classified.
///
/// The cases are distinct and equatable so a test can assert which rule fired.
/// `thresholdOverflow` is separate from the input errors: the threshold was
/// legal but converting it to chips (`threshold × bigBlindChips`) exceeds `Int`,
/// which the classifier reports rather than trapping.
public enum PushFoldError: Error, Equatable, Sendable {
    case nonPositiveEffectiveStack
    case nonPositiveBigBlind
    case negativeThreshold
    case thresholdOverflow
}
