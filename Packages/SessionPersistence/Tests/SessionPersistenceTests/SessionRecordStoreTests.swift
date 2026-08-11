import Foundation
import PokerCore
import SessionSimulation
import Testing
@testable import SessionPersistence

@Suite("Session 记录")
struct SessionRecordStoreTests {
    private static let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000001")!

    @Test("记录保存种子、五个座位的档案指派、行为表版本与手数")
    func recordStoresSeedSeatingVersionAndHandCount() async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        try await store.create(
            SessionRecord(id: Self.sessionID, seed: 42, handCount: 30)
        )

        // Reopened rather than reused: the claim is about what is on disk, and
        // a store still holding the value in memory would satisfy it either way.
        let reopened = try FileSessionRecordStore(directory: directory)
        let loaded = try await reopened.record(id: Self.sessionID)

        #expect(loaded.seed == 42)
        #expect(loaded.handCount == 30)
        #expect(loaded.opponentProfileTableVersion == OpponentProfileTable.version)
        #expect(loaded.seating.opponentProfiles.count == TableRules.seatCount - 1)
        for seat in 1 ..< TableRules.seatCount {
            #expect(
                loaded.seating.profile(forSeat: seat)
                    == loaded.seating.opponentProfiles[seat - 1]
            )
        }
        // Seat 0 is the user. A seating that answered here would mean the hero
        // had been assigned a behaviour table.
        #expect(loaded.seating.profile(forSeat: TableRules.heroSeat) == nil)
    }

    @Test("座位指派来自记录本身，不是重放时重新算的")
    func seatingComesFromTheRecordRatherThanFromTheSeed() async throws {
        // Chosen to differ from what seed 42 derives, so that a store which
        // dropped the field and recomputed it would come back with something
        // else. Without this the round-trip above passes on a record that
        // stores no seating at all.
        let derived = SeatAssignment.derived(seed: 42)
        let deliberate = SeatAssignment(
            opponentProfiles: [.maniac, .maniac, .maniac, .maniac, .maniac]
        )
        #expect(deliberate != derived, "夹具没有区分度：手工指派恰好等于种子推出的指派")

        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        try await store.create(
            SessionRecord(
                id: Self.sessionID,
                seed: 42,
                seating: deliberate,
                handCount: 15
            )
        )

        let reopened = try FileSessionRecordStore(directory: directory)
        let loaded = try await reopened.record(id: Self.sessionID)

        #expect(loaded.seating == deliberate)
        #expect(loaded.seating != derived)
    }

    @Test("行为表版本来自记录本身，不是读取时填上当前版本")
    func tableVersionComesFromTheRecord() async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        let stale = "0"
        #expect(stale != OpponentProfileTable.version, "夹具用的旧版本号与当前版本相同")

        try await store.create(
            SessionRecord(
                id: Self.sessionID,
                seed: 42,
                seating: .derived(seed: 42),
                opponentProfileTableVersion: stale,
                handCount: 15
            )
        )

        let reopened = try FileSessionRecordStore(directory: directory)
        #expect(try await reopened.record(id: Self.sessionID).opponentProfileTableVersion == stale)
    }

    @Test("种子决定座位指派，且四种档案都会被指派到")
    func seatingIsDerivedFromTheSeedAndUsesAllFourProfiles() {
        // Same seed, same table. The engine's whole replay story rests on this.
        #expect(SeatAssignment.derived(seed: 42) == SeatAssignment.derived(seed: 42))

        var seen: Set<OpponentProfileID> = []
        var assignments: Set<[OpponentProfileID]> = []
        for seed in UInt64(0) ..< 200 {
            let seating = SeatAssignment.derived(seed: seed)
            seen.formUnion(seating.opponentProfiles)
            assignments.insert(seating.opponentProfiles)
        }

        // A derivation that returned the same profile for every seat, or the
        // same table for every seed, would pass "same seed, same table".
        #expect(seen == Set(OpponentProfileID.allCases), "有档案从未被指派：\(seen)")
        #expect(assignments.count > 1, "200 个种子指派出同一张桌子")
    }

    @Test("手牌按顺序追加，缺口被拒绝")
    func handsAppendInOrderAndGapsAreRefused() async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        let record = SessionRecord(id: Self.sessionID, seed: 7, handCount: 15)
        try await store.create(record)

        let hands = SessionFixture.uninterruptedHands(record: record)
        #expect(hands.count == 15)

        try await store.appendHand(hands[0], to: Self.sessionID)
        try await store.appendHand(hands[1], to: Self.sessionID)

        await #expect(throws: SessionRecordStoreError.handOutOfOrder(expected: 2, found: 5)) {
            try await store.appendHand(hands[5], to: Self.sessionID)
        }

        let stored = try await store.hands(for: Self.sessionID)
        #expect(stored == Array(hands.prefix(2)))
        #expect(try await store.progress(for: Self.sessionID).nextHandIndex == 2)
    }

    @Test("读不到的 Session 返回 typed error")
    func missingSessionReturnsTypedError() async throws {
        let store = try FileSessionRecordStore(directory: SessionFixture.temporaryDirectory())
        let absent = UUID(uuidString: "5E551000-0000-0000-0000-0000000000FF")!

        await #expect(throws: SessionRecordStoreError.recordNotFound(absent)) {
            try await store.record(id: absent)
        }
    }

    @Test("坏掉的手牌行返回带行号的 typed error")
    func corruptedHandLineReturnsItsLineNumber() async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        let record = SessionRecord(id: Self.sessionID, seed: 7, handCount: 15)
        try await store.create(record)
        let hands = SessionFixture.uninterruptedHands(record: record)
        try await store.appendHand(hands[0], to: Self.sessionID)

        let file = SessionFixture.handsFile(in: directory, sessionID: Self.sessionID)
        var contents = try Data(contentsOf: file)
        contents.append(Data("not-json\n".utf8))
        try contents.write(to: file)

        await #expect(
            throws: SessionRecordStoreError.corruptedHandLine(
                sessionID: Self.sessionID,
                line: 2
            )
        ) {
            try await store.hands(for: Self.sessionID)
        }
    }
}

/// The three session lengths the product offers, each played to the end.
///
/// The suite above exercises 15 and 30. The proposal names 15, 30 and 60, and
/// 60 had no test at all — the longest session was the one nobody ran. It is
/// also the one where stacks have drifted furthest from the 100BB the content
/// is written for, so it is the least like the others rather than more of the
/// same.
@Suite("三种长度的 Session")
struct SessionLengthTests {
    @Test("15、30、60 手各自打完并存满", arguments: [15, 30, 60])
    func aSessionOfEachOfferedLengthCompletes(handCount: Int) async throws {
        let directory = SessionFixture.temporaryDirectory()
        let store = try FileSessionRecordStore(directory: directory)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", handCount))")!
        let record = SessionRecord(id: id, seed: 42, handCount: handCount)
        try await store.create(record)

        let hands = SessionFixture.uninterruptedHands(record: record)
        #expect(hands.count == handCount, "夹具只发了 \(hands.count) 手")
        for hand in hands {
            try await store.appendHand(hand, to: id)
        }

        let stored = try await store.hands(for: id)
        #expect(stored.count == handCount)
        #expect(stored.map(\.handIndex) == Array(0 ..< handCount))
        #expect(try await store.progress(for: id).nextHandIndex == handCount)

        let loaded = try await store.record(id: id)
        #expect(loaded.handCount == handCount)
        #expect(loaded.seed == 42)
    }
}
