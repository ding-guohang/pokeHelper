import Foundation
import PokerCore
import Testing
@testable import StrategyContent

@Test
func developmentStrategyPackProvidesThreeIndependentTrainingRoutes()
    throws
{
    let pack = try StrategyPackLoader().load(
        data: Data(contentsOf: developmentStrategyPackURL()),
        expectedSHA256: nil
    )

    #expect(pack.manifest.reviewStatus == .testFixture)
    #expect(
        pack.scenarios.map(\.id) == [
            "cash-bet-sizing",
            "cash-preflop-range",
            "cash-flop-cbet",
        ]
    )
    #expect(Set(pack.scenarios.map(\.id)).count == 3)
    #expect(
        pack.scenarios.first?.options.contains {
            $0.action == .bet(to: .init(centiBB: 217))
        } == true
    )

    for scenario in pack.scenarios {
        #expect(scenario.assumptions.tableSize == 6)
        #expect(
            scenario.assumptions.effectiveStack == .init(centiBB: 10_000)
        )
        #expect(!scenario.assumptions.gameType.isEmpty)
        #expect(!scenario.assumptions.rakeDescription.isEmpty)
        #expect(!scenario.assumptions.allowedBetSizeDescription.isEmpty)
        #expect(!scenario.explanation.conclusion.isEmpty)
    }
}

private func developmentStrategyPackURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "PokerCoach/Resources/DevStrategyPack.json")
}
