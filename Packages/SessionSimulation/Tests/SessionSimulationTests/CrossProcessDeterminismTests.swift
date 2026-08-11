import Foundation
import Testing
@testable import SessionSimulation

/// The cross-process property.
///
/// Everything here runs `session-transcript` as a child process, twice, and
/// compares what the two printed. That is deliberate and it is the whole point:
/// this project has been bitten three times by per-process hash seeding, and
/// each time the test that failed to catch it called the same function twice in
/// one process and compared the results. Hash seeds, `SystemRandomNumber‑
/// Generator` and `Dictionary` iteration order are all perfectly stable inside
/// a single launch. Only a second launch can tell.
@Suite("跨进程确定性")
struct CrossProcessDeterminismTests {
    @Test("同种子在两个独立进程中重放出逐张相同的牌局")
    func twoIndependentProcessesDealTheSameCards() throws {
        let binary = try TranscriptBinary.locate()
        let arguments = ["--seed", "42", "--hands", "30"]

        let first = try TranscriptBinary.run(binary, arguments: arguments)
        let second = try TranscriptBinary.run(binary, arguments: arguments)

        // The two runs really were two processes. Without this the test would
        // still pass if the helper were quietly changed to run in-process,
        // which is precisely the degradation this suite exists to prevent.
        #expect(
            first.processIdentifier != second.processIdentifier,
            "两次运行是同一个进程 \(first.processIdentifier)"
        )

        // And they really produced something. Two empty strings compare equal.
        #expect(!first.text.isEmpty, "子进程没有输出")
        #expect(first.text.contains("hand 0 "), "输出里没有第 0 手")
        #expect(first.text.contains("hand 29 "), "输出里没有第 29 手")
        #expect(first.text.contains("hole 0 "), "输出里没有英雄底牌")

        #expect(first.text == second.text, "两个进程的牌局不同")
    }

    @Test("同种子在两个独立进程中重放出逐个相同的对手行动，且序列长度不少于 30")
    func twoIndependentProcessesProduceTheSameOpponentActions() throws {
        let binary = try TranscriptBinary.locate()
        let arguments = ["--seed", "42", "--hands", "30", "--opponent-actions"]

        let first = try TranscriptBinary.run(binary, arguments: arguments)
        let second = try TranscriptBinary.run(binary, arguments: arguments)
        #expect(first.processIdentifier != second.processIdentifier)

        let firstActions = first.text.split(separator: "\n").map(String.init)
        let secondActions = second.text.split(separator: "\n").map(String.init)

        #expect(firstActions.count >= 30, "对手行动序列只有 \(firstActions.count) 个")
        #expect(firstActions == secondActions, "两个进程的对手行动序列不同")

        // A sequence of 288 identical folds would satisfy everything above.
        let kinds = Set(firstActions.compactMap { $0.split(separator: ":").last.map(String.init) })
        #expect(kinds.count > 1, "对手只做过一种行动：\(kinds)")

        // And it really is the opponents: component 1 is the seat, and the hero
        // sits in seat 0.
        let heroEntries = firstActions.filter { $0.split(separator: ":")[1] == "0" }
        #expect(heroEntries.isEmpty, "对手行动序列里混进了英雄的行动：\(heroEntries.prefix(3))")
    }

    @Test("库内直接跑出的记录与子进程输出逐字节相同")
    func theLibraryAndTheSubprocessAgree() throws {
        let binary = try TranscriptBinary.locate()
        let subprocess = try TranscriptBinary.run(
            binary,
            arguments: ["--seed", "42", "--hands", "30"]
        )
        let inProcess = SessionTranscript.render(SessionRunner(seed: 42).run(handCount: 30))

        // Ties the two together: without it the subprocess could be rendering
        // something the library never produces, and the comparison above would
        // be checking that a constant equals itself.
        #expect(inProcess == subprocess.text)
    }

    @Test("不同种子在子进程中产生不同牌局")
    func differentSeedsProduceDifferentSessionsAcrossProcesses() throws {
        let binary = try TranscriptBinary.locate()
        let first = try TranscriptBinary.run(binary, arguments: ["--seed", "42", "--hands", "30"])
        let second = try TranscriptBinary.run(binary, arguments: ["--seed", "43", "--hands", "30"])

        #expect(first.text != second.text)

        let heroHands: (String) -> [String] = { text in
            text.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("  hole 0 ") }
        }
        let left = heroHands(first.text)
        let right = heroHands(second.text)

        #expect(left.count == 30, "第一局只有 \(left.count) 手英雄底牌")
        #expect(right.count == 30)
        #expect(zip(left, right).count { $0 != $1 } >= 29, "不同种子的英雄手牌重合过多")
    }
}
