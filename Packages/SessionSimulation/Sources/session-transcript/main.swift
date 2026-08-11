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

let seed = value(for: "--seed", default: 42)
let handCount = Int(value(for: "--hands", default: 30))

let run = SessionRunner(seed: seed).run(handCount: handCount)

if CommandLine.arguments.contains("--opponent-actions") {
    print(SessionTranscript.opponentActions(run).joined(separator: "\n"))
} else {
    print(SessionTranscript.render(run), terminator: "")
}
