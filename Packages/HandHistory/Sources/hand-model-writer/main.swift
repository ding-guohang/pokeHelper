import Foundation
import HandHistory

// Parses a fixture in a process that can be launched twice, for the
// cross-process determinism test. On `.parsed` it prints `canonicalJSON()` to
// stdout; on `.unsupported` it writes the reason to stderr and exits non-zero.
//
// Usage: hand-model-writer --fixture <path>

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var fixturePath: String?
var index = 0
let raw = Array(CommandLine.arguments.dropFirst())
while index < raw.count {
    switch raw[index] {
    case "--fixture":
        fixturePath = index + 1 < raw.count ? raw[index + 1] : nil
        index += 2
    default:
        fail("unknown argument \(raw[index])", code: 64)
    }
}

guard let fixturePath else {
    fail("missing --fixture", code: 64)
}

guard let data = FileManager.default.contents(atPath: fixturePath) else {
    fail("cannot read fixture at \(fixturePath)", code: 66)
}
let text = String(decoding: data, as: UTF8.self)

switch PokerStarsParser.parse(text) {
case let .parsed(hand, _):
    let json = try hand.canonicalJSON()
    FileHandle.standardOutput.write(json)
case let .unsupported(reason, sourceLine):
    fail("unsupported at line \(sourceLine): \(reason)")
}
