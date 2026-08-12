import Foundation
import SessionPersistence
import SessionSimulation

/// Plays part of a session into a directory and then dies.
///
/// Exists for one test: "the user terminates the process after hand 7". The
/// only way to write that test honestly is to have a process terminate, so this
/// binary plays the requested number of hands and then sends itself SIGKILL —
/// no unwinding, no `atexit`, no flush. Anything gentler leaves open the
/// question the test is asking, which is whether the hands on disk are enough
/// to carry on from.
///
/// Usage:
///   session-record-writer --directory <path> --session <uuid> --seed <n>
///                         --hands <n> --play <n> [--exit-cleanly]
struct Arguments {
    var directory: URL
    var sessionID: UUID
    var seed: UInt64
    var handCount: Int
    var play: Int
    var exitCleanly: Bool

    init(_ raw: [String]) {
        var directory: String?
        var sessionID: String?
        var seed: UInt64?
        var handCount: Int?
        var play: Int?
        var exitCleanly = false

        var index = 0
        while index < raw.count {
            let flag = raw[index]
            let value: String? = index + 1 < raw.count ? raw[index + 1] : nil
            switch flag {
            case "--directory": directory = value; index += 2
            case "--session": sessionID = value; index += 2
            case "--seed": seed = value.flatMap(UInt64.init); index += 2
            case "--hands": handCount = value.flatMap(Int.init); index += 2
            case "--play": play = value.flatMap(Int.init); index += 2
            case "--exit-cleanly": exitCleanly = true; index += 1
            default:
                FileHandle.standardError.write(Data("unknown argument \(flag)\n".utf8))
                exit(64)
            }
        }

        guard let directory,
              let sessionID, let parsedID = UUID(uuidString: sessionID),
              let seed, let handCount, let play
        else {
            FileHandle.standardError.write(
                Data("missing required arguments\n".utf8)
            )
            exit(64)
        }

        self.directory = URL(fileURLWithPath: directory)
        self.sessionID = parsedID
        self.seed = seed
        self.handCount = handCount
        self.play = play
        self.exitCleanly = exitCleanly
    }
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

let store = try FileSessionRecordStore(directory: arguments.directory)
try await store.create(
    SessionRecord(
        id: arguments.sessionID,
        seed: arguments.seed,
        handCount: arguments.handCount
    )
)

let played = try await SessionPlaythrough.play(
    sessionID: arguments.sessionID,
    store: store,
    stoppingAfter: arguments.play
)

// Written straight to the descriptor rather than with `print`: stdout is
// buffered, and the process is about to be killed without a flush.
FileHandle.standardOutput.write(Data("played \(played.count)\n".utf8))

guard arguments.exitCleanly else {
    // The point of the binary. `kill` rather than `exit` so nothing gets a
    // chance to tidy up: whatever is on disk at this instant is what a real
    // interruption would have left.
    kill(getpid(), SIGKILL)
    // Not reached.
    exit(1)
}
