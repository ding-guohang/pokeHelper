import Foundation
import HandHistory

extension HandImportResult {
    /// The parsed hand and its conflicts, or a failed expectation's `nil`.
    var parsedPair: (hand: ObservedHand, conflicts: [HandImportConflict])? {
        switch self {
        case let .parsed(hand, conflicts): (hand, conflicts)
        case .unsupported: nil
        }
    }

    var unsupportedLine: Int? {
        switch self {
        case .parsed: nil
        case let .unsupported(_, sourceLine): sourceLine
        }
    }
}
