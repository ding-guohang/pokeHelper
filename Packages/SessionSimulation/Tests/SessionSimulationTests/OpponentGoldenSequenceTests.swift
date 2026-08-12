import Foundation
import Testing
@testable import SessionSimulation

/// The committed per-profile action sequences, and the cross-process property.
///
/// Two different failures are guarded here and they are easy to conflate:
///
/// - **Drift.** The behaviour table changed and nobody bumped the version. The
///   committed `actions` no longer match, so the golden test goes red rather
///   than every recorded session quietly replaying differently.
/// - **A stale fixture.** The version was bumped and the files were not
///   regenerated. `tableVersion` no longer matches, so the same test goes red
///   rather than comparing this version's play against last version's record.
///
/// The cross-process half is separate again: `hashValue`, `Set` iteration order
/// and `SystemRandomNumberGenerator` are all perfectly stable within a single
/// launch, so asking the same policy the same question twice in one process
/// proves nothing about replay. The only way to see it is a second process.
@Suite("对手行动的黄金序列与跨进程确定性")
struct OpponentGoldenSequenceTests {
    private static let seed: UInt64 = 42
    private static let handCount = 30

    @Test("每个档案在种子 42 的 30 手上逐个等于提交的黄金序列", arguments: OpponentProfileID.allCases)
    func theRecordedSequenceIsStillWhatTheProfilePlays(_ id: OpponentProfileID) throws {
        let committed = try OpponentFixtures.loadGolden(id)
        let now = OpponentActionGolden.make(profile: id, seed: Self.seed, handCount: Self.handCount)

        let staleFixture = "夹具记录的行为表版本是 \(committed.tableVersion)，"
            + "当前是 \(OpponentProfileTable.version)。改了版本号就要重新生成："
            + OpponentFixtures.regenerationCommand(id)
        #expect(
            committed.tableVersion == OpponentProfileTable.version,
            Comment(rawValue: staleFixture)
        )
        #expect(committed.profile == id)
        #expect(committed.seed == Self.seed)
        #expect(committed.handCount == Self.handCount)

        // The sequence has to be worth comparing before it is compared. Two
        // empty arrays are equal, and so are two arrays of 288 identical folds.
        #expect(committed.actions.count >= 30, "黄金序列只有 \(committed.actions.count) 个行动")
        let kinds = Set(committed.actions.compactMap { $0.split(separator: ":").dropFirst(3).first })
        #expect(kinds.count > 1, "\(id) 的黄金序列里只有一种行动：\(kinds)")
        let heroEntries = committed.actions.filter { $0.split(separator: ":")[1] == "0" }
        #expect(heroEntries.isEmpty, "黄金序列里混进了英雄座位的行动：\(heroEntries.prefix(3))")
        let hands = Set(committed.actions.compactMap { $0.split(separator: ":").first })
        #expect(hands.count == Self.handCount, "黄金序列只覆盖了 \(hands.count) 手")

        guard committed.actions != now.actions else {
            return
        }
        let firstDifference = zip(committed.actions, now.actions)
            .enumerated()
            .first { $0.element.0 != $0.element.1 }
        let detail = firstDifference.map {
            "第 \($0.offset) 个行动：记录是 \($0.element.0)，现在是 \($0.element.1)"
        } ?? "长度不同：记录 \(committed.actions.count)，现在 \(now.actions.count)"
        Issue.record(
            Comment(
                rawValue: "\(id) 的行动与提交的黄金序列不同。\(detail)。"
                    + "如果这是有意的行为改动，必须先递增 OpponentProfileTable.version，再重新生成："
                    + OpponentFixtures.regenerationCommand(id)
            )
        )
    }

    /// Four profiles, four different sequences.
    ///
    /// Without this, a table whose four entries had collapsed into one would
    /// pass the golden test four times over — each file would faithfully record
    /// the same behaviour.
    @Test("四个档案的黄金序列两两不同")
    func theFourRecordedSequencesAreDifferent() throws {
        let goldens = try OpponentProfileID.allCases.map { try OpponentFixtures.loadGolden($0) }
        for (index, left) in goldens.enumerated() {
            for right in goldens.dropFirst(index + 1) {
                // Compared through a Bool so a failure prints the two profile
                // names rather than two three-hundred-entry arrays.
                let identical = left.actions == right.actions
                #expect(
                    !identical,
                    "\(left.profile) 与 \(right.profile) 的行动序列完全相同"
                )
            }
        }
    }

    @Test(
        "同一档案在两个独立进程中求出逐个相同的行动",
        arguments: OpponentProfileID.allCases
    )
    func twoProcessesAgreeOnWhatAProfileDoes(_ id: OpponentProfileID) throws {
        let binary = try TranscriptBinary.locate()
        let arguments = [
            "--profile", id.rawValue,
            "--seed", String(Self.seed),
            "--hands", String(Self.handCount),
            "--opponent-actions",
        ]

        let first = try TranscriptBinary.run(binary, arguments: arguments)
        let second = try TranscriptBinary.run(binary, arguments: arguments)

        #expect(
            first.processIdentifier != second.processIdentifier,
            "两次运行是同一个进程 \(first.processIdentifier)"
        )
        #expect(!first.text.isEmpty, "子进程没有输出")
        #expect(first.text == second.text, "\(id) 在两个进程中的行动序列不同")

        // And the two processes were really running this profile, not the
        // unversioned baseline: their output has to be the committed sequence.
        let committed = try OpponentFixtures.loadGolden(id)
        let printed = first.text.split(separator: "\n").map(String.init)
        #expect(printed == committed.actions, "子进程的行动序列与提交的黄金序列不同")
    }

    /// Different profiles have to produce different transcripts *through the
    /// executable* as well.
    ///
    /// The `--profile` flag could be silently ignored — an early version of
    /// this binary defaulted to the baseline when the name did not parse — and
    /// every determinism assertion above would still pass, because the baseline
    /// is perfectly deterministic too.
    @Test("子进程真的按档案切换行为")
    func theProfileFlagChangesWhatTheSubprocessPlays() throws {
        let binary = try TranscriptBinary.locate()
        let baseline = try TranscriptBinary.run(
            binary,
            arguments: ["--seed", "42", "--hands", "5", "--opponent-actions"]
        )
        var seen: Set<String> = [baseline.text]

        for id in OpponentProfileID.allCases {
            let output = try TranscriptBinary.run(
                binary,
                arguments: ["--profile", id.rawValue, "--seed", "42", "--hands", "5", "--opponent-actions"]
            )
            #expect(output.text != baseline.text, "\(id) 的输出与不带 --profile 的基线相同")
            seen.insert(output.text)
        }

        #expect(seen.count == 5, "五种策略只产生了 \(seen.count) 种输出")
    }
}
