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

/// The deal itself, pinned to bytes that are in the repository.
///
/// The suite above compares two child processes against *each other*, which
/// catches a deal that varies between launches but not one that changed on
/// purpose or by accident and now varies from what shipped: both runs move
/// together and the comparison stays green. A recorded session's whole promise
/// is that the seed replays the same cards, and that promise spans releases,
/// not just two processes started a second apart.
@Suite("发牌黄金记录")
struct SessionGoldenTranscriptTests {
    /// Regenerate with:
    ///   swift run session-transcript --seed 42 --hands 30 \
    ///     > Tests/Fixtures/session-seed42-30hands.txt
    ///
    /// Do that only when the deal was meant to change. Every recorded session
    /// on every device replays differently afterwards, so this file changing is
    /// a release-note event, not a test fixup.
    @Test("种子 42 的 30 手与提交的黄金记录逐字节相同")
    func matchesTheCommittedTranscript() throws {
        let binary = try TranscriptBinary.locate()
        let run = try TranscriptBinary.run(binary, arguments: ["--seed", "42", "--hands", "30"])
        let committed = try Self.committedTranscript()

        // The fixture has to be a real transcript, not an empty file that would
        // match an empty run.
        #expect(committed.contains("hand 0 "), "黄金记录里没有第 0 手")
        #expect(committed.contains("hand 29 "), "黄金记录里没有第 29 手")
        #expect(committed.count > 10_000, "黄金记录只有 \(committed.count) 个字符，太短")

        guard run.text == committed else {
            let runLines = run.text.split(separator: "\n", omittingEmptySubsequences: false)
            let goldenLines = committed.split(separator: "\n", omittingEmptySubsequences: false)
            let firstDifference = zip(runLines, goldenLines).enumerated()
                .first { $0.element.0 != $0.element.1 }
            let detail = firstDifference.map {
                "第 \($0.offset + 1) 行：记录是「\($0.element.1)」，现在是「\($0.element.0)」"
            } ?? "行数不同：记录 \(goldenLines.count) 行，现在 \(runLines.count) 行"

            Issue.record(
                Comment(rawValue: """
                发牌与提交的黄金记录不同。\(detail)。
                如果这是有意的改动，所有已记录的 Session 都会在所有设备上重放出不同的牌；\
                重新生成：swift run session-transcript --seed 42 --hands 30 > \
                Tests/Fixtures/session-seed42-30hands.txt
                """)
            )
            return
        }
    }

    /// A different seed must not match it, or the assertion above would pass
    /// against a transcript that ignored its input.
    @Test("另一个种子与该黄金记录不同")
    func aDifferentSeedDoesNotMatchTheCommittedTranscript() throws {
        let binary = try TranscriptBinary.locate()
        let other = try TranscriptBinary.run(binary, arguments: ["--seed", "43", "--hands", "30"])

        #expect(other.text != (try Self.committedTranscript()))
    }

    private static func committedTranscript() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/session-seed42-30hands.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
