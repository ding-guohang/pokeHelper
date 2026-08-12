import Foundation
import SessionSimulation

// Prints a session transcript. Exists only so a test can obtain one from a
// process that is not the test process.
//
// Cross-process determinism is the one property in this package that a
// single-process test cannot observe: per-process hash seeding and
// `SystemRandomNumberGenerator`'s per-process seed are both perfectly stable
// within one launch, so calling the dealer twice in one process would agree
// even if the dealer were built entirely on them. The test runs this binary
// twice and compares the two outputs.
//
// Deliberately tiny. Everything it prints comes from `SessionTranscript`, so
// the test is comparing the library's rendering rather than this file's.

func value(for option: String, default fallback: UInt64) -> UInt64 {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: option),
          index + 1 < arguments.count,
          let parsed = UInt64(arguments[index + 1])
    else {
        return fallback
    }
    return parsed
}

/// The profile named by `--profile`, or the unversioned baseline when the flag
/// is absent.
///
/// An unrecognised name exits non-zero rather than falling back. A silent
/// fallback would let the profile determinism test compare two runs of the
/// baseline and report the profile as deterministic without ever having run it.
func policy() -> any SessionActionPolicy {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--profile"), index + 1 < arguments.count else {
        return BaselineActionPolicy()
    }
    let name = arguments[index + 1]
    guard let id = OpponentProfileID(rawValue: name) else {
        FileHandle.standardError.write(Data("unknown profile \(name)\n".utf8))
        exit(2)
    }
    return OpponentProfileTable.policy(id)
}

let seed = value(for: "--seed", default: 42)
let handCount = Int(value(for: "--hands", default: 30))

// Regenerating a committed golden sequence, which is the only way one should
// ever be produced:
//
//     swift run session-transcript --profile rock --golden \
//         > Tests/Fixtures/opponent-rock-seed42.json
//
// The behaviour table version is stamped in by `OpponentActionGolden.make`
// rather than passed on the command line, so a regenerated file cannot claim a
// version the code is not running.
if CommandLine.arguments.contains("--golden") {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--profile"),
          index + 1 < arguments.count,
          let id = OpponentProfileID(rawValue: arguments[index + 1])
    else {
        FileHandle.standardError.write(Data("--golden requires a valid --profile\n".utf8))
        exit(2)
    }
    let golden = OpponentActionGolden.make(profile: id, seed: seed, handCount: handCount)
    FileHandle.standardOutput.write(try golden.encodedJSON())
    print()
    exit(0)
}

let run = SessionRunner(seed: seed, policy: policy()).run(handCount: handCount)

if CommandLine.arguments.contains("--opponent-actions") {
    print(SessionTranscript.opponentActions(run).joined(separator: "\n"))
} else {
    print(SessionTranscript.render(run), terminator: "")
}
