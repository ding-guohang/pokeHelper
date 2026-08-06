import Foundation
import PokerCore
import Testing
@testable import StrategyContent

@Test func validPackLoadsAndPreservesProvenance() throws {
    let data = try fixture("valid-pack.json")
    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)

    #expect(pack.manifest.id == "cash-6max-100bb-dev")
    #expect(pack.manifest.schemaVersion == 1)
    #expect(pack.scenarios[0].options.reduce(0) { $0 + $1.frequencyBasisPoints } == 10_000)
    #expect(pack.scenarios[0].assumptions.effectiveStack == .init(centiBB: 10_000))
    #expect(pack.scenarios[0].heroSeatOffsetFromButton == 0)
}

@Test func invalidFrequencyTotalIsRejected() throws {
    let data = try fixture("invalid-frequency-pack.json")

    #expect(throws: StrategyPackValidationError.self) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func missingHeroSeatOffsetIsRejectedAsInvalidSchema() throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            scenario.removeValue(forKey: "heroSeatOffsetFromButton")
        }
    }

    #expect(throws: StrategyPackLoadingError.decodingFailed) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test(arguments: [1, 10])
func tableSizeOutsideTwoThroughNineIsRejected(tableSize: Int) throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            var assumptions = scenario["assumptions"] as! [String: Any]
            assumptions["tableSize"] = tableSize
            scenario["assumptions"] = assumptions
        }
    }

    #expect(
        throws: StrategyPackValidationError.invalidTableSize(
            scenarioID: "btn-check",
            tableSize: tableSize
        )
    ) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test(arguments: [-1, 6])
func heroSeatOffsetOutsideTableIsRejected(
    heroSeatOffsetFromButton: Int
) throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            scenario["heroSeatOffsetFromButton"] = heroSeatOffsetFromButton
        }
    }

    #expect(
        throws: StrategyPackValidationError.invalidHeroSeatOffset(
            scenarioID: "btn-check",
            tableSize: 6,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton
        )
    ) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func negativeFrequencyCannotBeOffsetByAnotherOption() throws {
    let data = try validPackWithFrequencies([-1_000, 11_000])

    #expect(
        throws: StrategyPackValidationError.invalidFrequencyTotal(
            scenarioID: "btn-check",
            actual: -1_000
        )
    ) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func frequencyAboveBasisPointMaximumCannotBeOffsetByAnotherOption() throws {
    let data = try validPackWithFrequencies([11_000, -1_000])

    #expect(
        throws: StrategyPackValidationError.invalidFrequencyTotal(
            scenarioID: "btn-check",
            actual: 11_000
        )
    ) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func extremeFrequencyThrowsTypedErrorInsteadOfOverflowing() throws {
    let data = try validPackWithFrequencies([Int.max, 1])

    #expect(
        throws: StrategyPackValidationError.invalidFrequencyTotal(
            scenarioID: "btn-check",
            actual: Int.max
        )
    ) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func unsupportedSchemaVersionIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateManifest(in: &root) { manifest in
            manifest["schemaVersion"] = 2
        }
    }

    #expect(throws: StrategyPackValidationError.unsupportedSchemaVersion(2)) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func duplicateScenarioIDIsRejected() throws {
    let data = try mutatedValidPack { root in
        var scenarios = scenarios(in: root)
        scenarios.append(scenarios[0])
        root["scenarios"] = scenarios
    }

    #expect(throws: StrategyPackValidationError.duplicateScenarioID("btn-check")) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func duplicateCardIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            scenario["board"] = ["As", "7d", "Jh"]
        }
    }

    #expect(throws: StrategyPackValidationError.duplicateCard("As")) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func illegalActionIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            var options = scenario["options"] as! [[String: Any]]
            options[0]["action"] = ["kind": "fold"]
            scenario["options"] = options
        }
    }

    #expect(throws: StrategyPackValidationError.illegalAction(scenarioID: "btn-check")) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func raiseBelowCallFromConstructedContextIsRejected() throws {
    let loadedPack = try StrategyPackLoader().load(
        data: fixture("valid-pack.json"),
        expectedSHA256: nil
    )
    let sourceScenario = try #require(loadedPack.scenarios.first)
    let invalidRaiseScenario = DecisionScenario(
        id: sourceScenario.id,
        title: sourceScenario.title,
        abilityDimension: sourceScenario.abilityDimension,
        heroSeatOffsetFromButton: sourceScenario.heroSeatOffsetFromButton,
        heroCards: sourceScenario.heroCards,
        board: sourceScenario.board,
        decision: BettingDecisionContext(
            pot: .init(centiBB: 1_000),
            effectiveStack: .init(centiBB: 2_000),
            amountToCall: .init(centiBB: 300),
            minimumRaiseTo: .init(centiBB: 200),
            configuredBetSizes: [.init(centiBB: 250)]
        ),
        options: [
            StrategyOption(
                action: .raise(to: .init(centiBB: 250)),
                frequencyBasisPoints: 10_000,
                ev: .init(milliBB: 100)
            )
        ],
        rangeCells: sourceScenario.rangeCells,
        assumptions: sourceScenario.assumptions,
        explanation: sourceScenario.explanation
    )
    let invalidPack = StrategyPack(
        manifest: loadedPack.manifest,
        scenarios: [invalidRaiseScenario]
    )

    #expect(
        throws: StrategyPackValidationError.illegalAction(
            scenarioID: sourceScenario.id
        )
    ) {
        try StrategyPackValidator().validate(invalidPack)
    }
}

@Test func duplicateActionIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            var options = scenario["options"] as! [[String: Any]]
            options[1]["action"] = ["kind": "check"]
            scenario["options"] = options
        }
    }

    #expect(throws: StrategyPackValidationError.duplicateAction(scenarioID: "btn-check")) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func emptyGeneratedSourceIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateManifest(in: &root) { manifest in
            manifest["generatedSource"] = ""
        }
    }

    #expect(throws: StrategyPackValidationError.emptyGeneratedSource) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func whitespaceOnlyGeneratedSourceIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateManifest(in: &root) { manifest in
            manifest["generatedSource"] = " \n\t "
        }
    }

    #expect(throws: StrategyPackValidationError.emptyGeneratedSource) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func reviewedPackWithoutReviewedAtIsRejected() throws {
    let data = try mutatedValidPack { root in
        updateManifest(in: &root) { manifest in
            manifest["reviewStatus"] = "reviewed"
        }
    }

    #expect(throws: StrategyPackValidationError.missingReviewedAt) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func reviewedPackAcceptsISO8601ReviewedAt() throws {
    let data = try mutatedValidPack { root in
        updateManifest(in: &root) { manifest in
            manifest["reviewStatus"] = "reviewed"
            manifest["reviewedAt"] = "2026-08-06T08:30:00Z"
        }
    }

    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)

    #expect(pack.manifest.reviewedAt != nil)
}

@Test func emptyPackIsRejected() throws {
    let data = try mutatedValidPack { root in
        root["scenarios"] = []
    }

    #expect(throws: StrategyPackValidationError.emptyScenarios) {
        try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    }
}

@Test func malformedJSONReturnsDecodingError() {
    #expect(throws: StrategyPackLoadingError.decodingFailed) {
        try StrategyPackLoader().load(data: Data("not-json".utf8), expectedSHA256: nil)
    }
}

@Test func checksumMismatchIsReportedBeforeDecoding() {
    #expect(throws: StrategyPackLoadingError.checksumMismatch) {
        try StrategyPackLoader().load(
            data: Data("not-json".utf8),
            expectedSHA256: String(repeating: "0", count: 64)
        )
    }
}

@Test func matchingChecksumAllowsLoading() throws {
    let data = try fixture("valid-pack.json")
    let pack = try StrategyPackLoader().load(
        data: data,
        expectedSHA256: "6b14c519a3fec910d7d2ccfffe629a556a08be5fadc1762641aa4b79f30580d1"
    )

    #expect(pack.manifest.id == "cash-6max-100bb-dev")
}

@Test func inMemoryProviderReturnsPackAndLooksUpScenario() async throws {
    let data = try fixture("valid-pack.json")
    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    let provider = InMemoryStrategyPackProvider(pack: pack)

    #expect(try await provider.pack().manifest.id == "cash-6max-100bb-dev")
    #expect(try await provider.scenario(id: "btn-check").title == "Button checks the flop")
}

@Test func inMemoryProviderRejectsMissingScenario() async throws {
    let data = try fixture("valid-pack.json")
    let pack = try StrategyPackLoader().load(data: data, expectedSHA256: nil)
    let provider = InMemoryStrategyPackProvider(pack: pack)

    await #expect(throws: StrategyPackLookupError.scenarioNotFound(id: "missing")) {
        try await provider.scenario(id: "missing")
    }
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
        throw FixtureError.missing(name)
    }

    return try Data(contentsOf: url)
}

private func mutatedValidPack(
    _ mutation: (inout [String: Any]) -> Void
) throws -> Data {
    var root = try #require(
        JSONSerialization.jsonObject(with: fixture("valid-pack.json")) as? [String: Any]
    )
    mutation(&root)
    return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
}

private func scenarios(in root: [String: Any]) -> [[String: Any]] {
    root["scenarios"] as! [[String: Any]]
}

private func validPackWithFrequencies(_ frequencies: [Int]) throws -> Data {
    try mutatedValidPack { root in
        updateFirstScenario(in: &root) { scenario in
            var options = scenario["options"] as! [[String: Any]]
            for index in options.indices {
                options[index]["frequencyBasisPoints"] = frequencies[index]
            }
            scenario["options"] = options
        }
    }
}

private func updateManifest(
    in root: inout [String: Any],
    _ update: (inout [String: Any]) -> Void
) {
    var packManifest = root["manifest"] as! [String: Any]
    update(&packManifest)
    root["manifest"] = packManifest
}

private func updateFirstScenario(
    in root: inout [String: Any],
    _ update: (inout [String: Any]) -> Void
) {
    var allScenarios = scenarios(in: root)
    update(&allScenarios[0])
    root["scenarios"] = allScenarios
}

private enum FixtureError: Error {
    case missing(String)
}
