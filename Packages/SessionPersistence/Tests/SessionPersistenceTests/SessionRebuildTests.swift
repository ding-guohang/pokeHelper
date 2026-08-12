import Foundation
import PokerCore
import SessionSimulation
import Testing
@testable import SessionPersistence

@Suite("从记录重建 Session")
struct SessionRebuildTests {
    private static let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000010")!

    /// Plays a session with a hero who is not the default autopilot, so that a
    /// rebuild has to read the recorded hero actions rather than re-derive
    /// them, and stores it.
    private func storedSession(
        seed: UInt64 = 42,
        handCount: Int = 15
    ) async throws -> (record: SessionRecord, hands: [SessionHandRecord]) {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        let record = SessionRecord(id: Self.sessionID, seed: seed, handCount: handCount)
        try await store.create(record)
        try await SessionPlaythrough.play(
            sessionID: Self.sessionID,
            store: store,
            heroPolicy: ScriptedHeroPolicy()
        )

        let reopened = try FileSessionRecordStore(directory: directory)
        return (record, try await reopened.hands(for: Self.sessionID))
    }

    @Test("用记录重建得到逐手相同的牌与逐个相同的对手行动")
    func rebuildingFromTheRecordReproducesCardsAndOpponentActions() async throws {
        let (record, saved) = try await storedSession()

        // The fixture produced something to compare. Two empty lists are equal.
        #expect(saved.count == 15)
        let savedOpponentActions = SessionFixture.opponentActions(saved)
        #expect(savedOpponentActions.count >= 15, "对手行动只有 \(savedOpponentActions.count) 个")
        #expect(
            Set(savedOpponentActions.map { $0.split(separator: ":").last.map(String.init) ?? "" }).count > 1,
            "对手只做过一种行动"
        )

        // And the hero really did play differently from the autopilot, so a
        // rebuild that ignored the recorded hero actions could not reproduce
        // the session by accident.
        let autopilot = SessionFixture.uninterruptedHands(record: record)
        #expect(
            SessionFixture.heroActions(saved) != SessionFixture.heroActions(autopilot),
            "脚本英雄与默认英雄打得一样，重建就不必读记录了"
        )

        let result = SessionReplay.replay(record: record, savedHands: saved)
        let rebuilt = try #require(result.rebuiltHands)

        #expect(SessionFixture.cards(rebuilt) == SessionFixture.cards(saved))
        #expect(SessionFixture.opponentActions(rebuilt) == savedOpponentActions)
        #expect(result.claimsFaithfulReplay)
        #expect(result.firstDivergentHandIndex == nil)
    }

    @Test("另一个种子的记录重建出不同的牌")
    func adifferentSeedRebuildsDifferentCards() async throws {
        let (record, saved) = try await storedSession(seed: 42)
        let other = SessionRecord(id: Self.sessionID, seed: 43, handCount: 15)

        let sameSeed = SessionReplay.replay(record: record, savedHands: saved)
        let otherSeed = SessionReplay.replay(record: other, savedHands: saved)

        // Without this the comparison above would pass on a rebuild that copied
        // the record straight back out.
        #expect(try #require(sameSeed.rebuiltHands) == saved)
        #expect(try #require(otherSeed.rebuiltHands) != saved)
        #expect(!otherSeed.claimsFaithfulReplay)
    }

    @Test("行为表版本不同时不声称重放一致，但仍给出已保存的手牌")
    func aChangedBehaviourTableIsNotReplayedSilently() async throws {
        let (_, saved) = try await storedSession()
        let stale = "0"
        #expect(stale != OpponentProfileTable.version, "夹具用的旧版本号与当前版本相同")

        let recordFromAnotherTable = SessionRecord(
            id: Self.sessionID,
            seed: 42,
            seating: .derived(seed: 42),
            opponentProfileTableVersion: stale,
            handCount: 15
        )
        let result = SessionReplay.replay(
            record: recordFromAnotherTable,
            savedHands: saved
        )

        #expect(result.behaviourTableChanged)
        #expect(!result.claimsFaithfulReplay)
        // Nothing was rebuilt: replaying under the current table and showing the
        // result is the silent repainting this is here to prevent.
        #expect(result.rebuiltHands == nil)

        // The saved hands are still available to show.
        #expect(result.savedHands == saved)
        #expect(result.savedHands.count == 15)

        let notice = try #require(result.behaviourTableNotice)
        #expect(notice.contains("对手行为表"))
        #expect(notice.contains(stale))
        #expect(notice.contains(OpponentProfileTable.version))
    }

    @Test("行为表版本相同时确实声称一致——版本检查不是无脑拒绝")
    func amatchingBehaviourTableDoesClaimAFaithfulReplay() async throws {
        let (record, saved) = try await storedSession()
        let result = SessionReplay.replay(record: record, savedHands: saved)

        #expect(!result.behaviourTableChanged)
        #expect(result.behaviourTableNotice == nil)
        #expect(result.claimsFaithfulReplay)
    }
}
