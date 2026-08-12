import Foundation

/// One field the parser could not read unambiguously.
///
/// The parser never invents a value it cannot read from the supported grammar;
/// it records the field and the line instead, and the hand cannot be adopted
/// until the conflict is resolved.
public struct HandImportConflict: Hashable, Sendable, Codable {
    /// A stable field identifier, e.g. "hero.action.preflop", "straddle",
    /// "amount.rake".
    public let field: String
    /// The 1-based line number in the raw text.
    public let sourceLine: Int

    public init(field: String, sourceLine: Int) {
        self.field = field
        self.sourceLine = sourceLine
    }
}

/// The outcome of parsing a text hand.
///
/// `.parsed` with a non-empty `conflicts` is a hand that was understood well
/// enough to preview but must not be adopted until its conflicts clear.
/// `.unsupported` is text outside the supported class (a tournament, a variant),
/// rejected with the line that triggered the decision rather than partially
/// guessed.
public enum HandImportResult: Hashable, Sendable, Codable {
    case parsed(ObservedHand, conflicts: [HandImportConflict])
    case unsupported(reason: String, sourceLine: Int)
}
