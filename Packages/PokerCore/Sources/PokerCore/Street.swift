import Foundation

/// Which betting round a spot belongs to.
public enum Street: String, Hashable, Sendable, CaseIterable, Codable {
    case preflop
    case flop
    case turn
    case river

    /// The street implied by how many community cards are out.
    public init?(boardCardCount: Int) {
        switch boardCardCount {
        case 0: self = .preflop
        case 3: self = .flop
        case 4: self = .turn
        case 5: self = .river
        default: return nil
        }
    }

    public var boardCardCount: Int {
        switch self {
        case .preflop: 0
        case .flop: 3
        case .turn: 4
        case .river: 5
        }
    }
}
