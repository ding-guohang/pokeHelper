import Foundation
import XCTest
@testable import PokerCoach

@MainActor
final class LocalIdentityStoreTests: XCTestCase {
    func testIdentityPersistsAcrossStoreInstances() throws {
        let suiteName = "PokerCoachTests.LocalIdentity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var generatedIDs = [
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        ].makeIterator()
        let firstStore = LocalIdentityStore(
            userDefaults: defaults,
            makeUUID: { generatedIDs.next()! }
        )

        let firstIdentity = firstStore.loadOrCreate()
        let reopenedStore = LocalIdentityStore(
            userDefaults: defaults,
            makeUUID: {
                XCTFail("Reopening must not generate a new identity")
                return UUID()
            }
        )

        XCTAssertEqual(reopenedStore.loadOrCreate(), firstIdentity)
    }

    func testAvailableDependenciesReuseInjectedIdentityAcrossSessions()
        async throws
    {
        let identity = LocalIdentity(
            localUserID: UUID(
                uuidString: "10000000-0000-0000-0000-000000000010"
            )!,
            deviceID: UUID(
                uuidString: "20000000-0000-0000-0000-000000000020"
            )!
        )
        let pack = try DecisionSessionFixture.makePack(
            scenarioID: "stable-identity-scenario"
        )
        let store = InMemoryTrainingEventStore()
        let dependencies = AppDependencies.availableContent(
            eventStore: store,
            strategyPack: pack,
            localIdentity: identity,
            strategyContentAvailability: .developmentFixtureAvailable
        )

        for _ in 0 ..< 2 {
            let session = dependencies.makeDecisionSessionViewModel(
                scenarioID: "stable-identity-scenario"
            )
            await session.load()
            let scenario = try XCTUnwrap(session.scenario)
            let bestAction = try XCTUnwrap(
                scenario.options.max(by: { $0.ev < $1.ev })?.action
            )
            session.select(action: bestAction)
            session.setConfidence(.verySure)
            await session.submit()
        }

        let events = await store.allEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy {
            $0.localUserID == identity.localUserID
                && $0.deviceID == identity.deviceID
        })
    }
}
