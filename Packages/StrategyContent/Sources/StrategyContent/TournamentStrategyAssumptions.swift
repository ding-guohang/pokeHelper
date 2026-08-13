import PokerCore

public enum TournamentEquilibrium: String, Codable, Hashable, Sendable {
    case chipEV
    case icm
}

public struct TournamentSolverAssumptions: Codable, Hashable, Sendable {
    public let effectiveBigBlinds: Int
    public let smallBlindCentiBB: Int
    public let bigBlindCentiBB: Int
    public let hasAnte: Bool
    public let anteDescription: String
    public let equilibrium: TournamentEquilibrium

    public init(
        effectiveBigBlinds: Int,
        smallBlindCentiBB: Int,
        bigBlindCentiBB: Int,
        hasAnte: Bool,
        anteDescription: String,
        equilibrium: TournamentEquilibrium
    ) {
        self.effectiveBigBlinds = effectiveBigBlinds
        self.smallBlindCentiBB = smallBlindCentiBB
        self.bigBlindCentiBB = bigBlindCentiBB
        self.hasAnte = hasAnte
        self.anteDescription = anteDescription
        self.equilibrium = equilibrium
    }
}
