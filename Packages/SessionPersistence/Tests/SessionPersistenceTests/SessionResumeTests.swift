import Foundation
import PokerCore
import SessionSimulation
import Testing
@testable import SessionPersistence

/// The interrupted-session scenario, with a real interruption.
///
/// `session-record-writer` plays seven hands into a directory and then sends
/// itself SIGKILL. Nothing it held survives — no runner, no stacks, no cached
/// deck — so whatever the resume works from came off the disk. A stand-in that
/// merely stopped calling a function, or dropped a view model, would satisfy a
/// weaker reading of "terminate the process" and would let a resume that leans
/// on in-memory state pass.
@Suite("中断后续打")
struct SessionResumeTests {
    private static let sessionID = UUID(uuidString: "5E551000-0000-0000-0000-000000000020")!
    private static let seed: UInt64 = 42
    private static let handCount = 15
    private static let playedBeforeTheKill = 7

    @Test("进程在第 7 手后被杀，重开从第 8 手继续，前 7 手未被改写，8–15 手与不中断的同种子 Session 相同")
    func resumingAfterTheProcessDiesContinuesTheSameSession() async throws {
        let binary = try WriterBinary.locate()
        let directory = SessionFixture.temporaryDirectory()

        let crashed = try WriterBinary.run(binary, arguments: [
            "--directory", directory.path(percentEncoded: false),
            "--session", Self.sessionID.uuidString,
            "--seed", String(Self.seed),
            "--hands", String(Self.handCount),
            "--play", String(Self.playedBeforeTheKill),
        ])

        // The process really died, and died by signal rather than returning.
        #expect(crashed.terminationReason == .uncaughtSignal)
        #expect(crashed.terminationStatus == SIGKILL)
        #expect(crashed.text.contains("played \(Self.playedBeforeTheKill)"))

        let store = try FileSessionRecordStore(directory: directory)
        let survived = try await store.hands(for: Self.sessionID)
        #expect(survived.count == Self.playedBeforeTheKill)

        let progress = try await store.progress(for: Self.sessionID)
        #expect(progress.nextHandIndex == Self.playedBeforeTheKill)
        #expect(!progress.isComplete)
        // The stacks carried, rather than being reset to six full buy-ins. A
        // fresh table would deal the same cards and play them differently.
        #expect(progress.stacks == survived[Self.playedBeforeTheKill - 1].endingStacks)

        let handsFile = SessionFixture.handsFile(in: directory, sessionID: Self.sessionID)
        let bytesAfterTheKill = try Data(contentsOf: handsFile)
        #expect(!bytesAfterTheKill.isEmpty)

        let resumed = try await SessionPlaythrough.play(
            sessionID: Self.sessionID,
            store: store
        )

        #expect(resumed.count == Self.handCount - Self.playedBeforeTheKill)
        #expect(resumed.first?.handIndex == Self.playedBeforeTheKill)

        let all = try await store.hands(for: Self.sessionID)
        #expect(all.count == Self.handCount)
        #expect(try await store.progress(for: Self.sessionID).isComplete)

        // The first seven hands were not rewritten. Checked as bytes, and with
        // the total count above: a resume that replayed hands 0 to 6 and
        // appended them again would leave this prefix intact and the file 22
        // lines long.
        let bytesNow = try Data(contentsOf: handsFile)
        #expect(bytesNow.prefix(bytesAfterTheKill.count) == bytesAfterTheKill)
        #expect(Array(all.prefix(Self.playedBeforeTheKill)) == survived)

        // Hands 8 through 15 are what an uninterrupted run of the same seed
        // produces. This is the clause that catches a resume which re-derives
        // the deal from index 0, or one that starts the table from 100BB again.
        let uninterrupted = SessionFixture.uninterruptedHands(
            record: try await store.record(id: Self.sessionID)
        )
        #expect(uninterrupted.count == Self.handCount)

        let resumedTail = Array(all.suffix(Self.handCount - Self.playedBeforeTheKill))
        let referenceTail = Array(
            uninterrupted.suffix(Self.handCount - Self.playedBeforeTheKill)
        )
        #expect(!resumedTail.isEmpty)
        #expect(resumedTail == referenceTail)

        // Non-vacuity: the tail is not the head, so "the tail matches" is not a
        // statement two identical prefixes could satisfy.
        #expect(
            SessionFixture.cards(resumedTail)
                != SessionFixture.cards(Array(all.prefix(resumedTail.count))),
            "第 8–15 手与第 1–7 手的牌相同，比较没有意义"
        )

        // And the whole session, the part written by the dead process included,
        // is the session that seed produces.
        #expect(all == uninterrupted)
    }

    @Test("续打完的 Session 可以从记录重建，且声称一致")
    func aresumedSessionStillRebuildsFromItsRecord() async throws {
        let binary = try WriterBinary.locate()
        let directory = SessionFixture.temporaryDirectory()

        _ = try WriterBinary.run(binary, arguments: [
            "--directory", directory.path(percentEncoded: false),
            "--session", Self.sessionID.uuidString,
            "--seed", String(Self.seed),
            "--hands", String(Self.handCount),
            "--play", String(Self.playedBeforeTheKill),
        ])

        let store = try FileSessionRecordStore(directory: directory)
        try await SessionPlaythrough.play(sessionID: Self.sessionID, store: store)

        let record = try await store.record(id: Self.sessionID)
        let hands = try await store.hands(for: Self.sessionID)
        let result = SessionReplay.replay(record: record, savedHands: hands)

        #expect(hands.count == Self.handCount)
        #expect(result.claimsFaithfulReplay)
        #expect(try #require(result.rebuiltHands).count == Self.handCount)
    }
}
