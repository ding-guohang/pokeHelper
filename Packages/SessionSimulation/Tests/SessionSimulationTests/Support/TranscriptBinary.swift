import Foundation

/// Finds and runs the `session-transcript` executable.
///
/// The determinism scenario says "in two independent processes", and it says so
/// because the failure it guards against is invisible from inside one. Per-
/// process hash seeding and `SystemRandomNumberGenerator`'s per-process seed
/// are both perfectly stable for the lifetime of a launch, so a dealer built on
/// either would return identical results to two calls in the same process and
/// different results tomorrow. Calling a pure function twice is not a test of
/// this property; spawning the binary twice is.
enum TranscriptBinary {
    enum LocationError: Error, CustomStringConvertible {
        case notFound(searchedUnder: String)

        var description: String {
            switch self {
            case let .notFound(root):
                "session-transcript was not found under \(root). It is a dependency of the "
                    + "test target, so `swift test` should have built it."
            }
        }
    }

    struct Output {
        let text: String
        let processIdentifier: Int32
    }

    /// The package root, derived from this file's own location rather than from
    /// the working directory — a test's working directory is not something the
    /// test controls.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // SessionSimulationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SessionSimulation
    }

    /// Searches the build directory rather than assuming `.build/debug`.
    ///
    /// SwiftPM puts the binary under a triple-specific directory and the
    /// scratch path can be overridden, so a hardcoded path would work on one
    /// machine and produce a confusing "not found" everywhere else.
    static func locate() throws -> URL {
        let buildRoot = packageRoot.appendingPathComponent(".build")
        let fileManager = FileManager.default

        guard
            let enumerator = fileManager.enumerator(
                at: buildRoot,
                includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey]
            )
        else {
            throw LocationError.notFound(searchedUnder: buildRoot.path)
        }

        var candidates: [URL] = []
        for case let url as URL in enumerator
        where url.lastPathComponent == "session-transcript"
            && !url.path.contains(".dSYM")
            && fileManager.isExecutableFile(atPath: url.path) {
            candidates.append(url)
        }

        // Sorted so the choice does not depend on directory enumeration order.
        guard let binary = candidates.sorted(by: { $0.path < $1.path }).first else {
            throw LocationError.notFound(searchedUnder: buildRoot.path)
        }
        return binary
    }

    /// Runs the binary in a genuinely separate process and returns what it
    /// printed, along with the process ID so a test can show the two runs were
    /// not the same process.
    static func run(_ binary: URL, arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            struct ExitFailure: Error, CustomStringConvertible {
                let status: Int32
                var description: String { "session-transcript exited with status \(status)" }
            }
            throw ExitFailure(status: process.terminationStatus)
        }

        return Output(
            text: String(decoding: data, as: UTF8.self),
            processIdentifier: process.processIdentifier
        )
    }
}
