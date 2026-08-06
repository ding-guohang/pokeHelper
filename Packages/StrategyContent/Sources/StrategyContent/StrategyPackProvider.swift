public protocol StrategyPackProviding: Sendable {
    func pack() async throws -> StrategyPack
    func scenario(id: String) async throws -> DecisionScenario
}

public struct InMemoryStrategyPackProvider: StrategyPackProviding, Sendable {
    private let storedPack: StrategyPack

    public init(pack: StrategyPack) {
        storedPack = pack
    }

    public func pack() async throws -> StrategyPack {
        storedPack
    }

    public func scenario(id: String) async throws -> DecisionScenario {
        guard let scenario = storedPack.scenarios.first(where: { $0.id == id }) else {
            throw StrategyPackLookupError.scenarioNotFound(id: id)
        }

        return scenario
    }
}
