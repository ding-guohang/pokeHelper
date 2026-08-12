import Foundation

/// Finds and runs `session-record-writer`.
///
/// The scenario says the user terminates the process after hand 7. A test that
/// tears down a view model, releases an actor or simply stops calling a
/// function satisfies a weaker reading of that sentence: everything the object
/// graph held is still there, and a resume that leans on it looks correct. The
/// only way to be sure the hands on disk are enough is for the process holding
/// everything else to stop existing.
enum WriterBinary {
    enum LocationError: Error, CustomStringConvertible {
        case notFound(searchedUnder: String)

        var description: String {
            switch self {
            case let .notFound(root):
                "session-record-writer was not found under \(root). It is a dependency of "
                    + "the test target, so `swift test` should have built it."
            }
        }
    }

    struct Output {
        let text: String
        let processIdentifier: Int32
        let terminationStatus: Int32
        let terminationReason: Process.TerminationReason
    }

    /// The package root, from this file's own location: a test does not control
    /// its working directory.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // SessionPersistenceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SessionPersistence
    }

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
        where url.lastPathComponent == "session-record-writer"
            && !url.path.contains(".dSYM")
            && fileManager.isExecutableFile(atPath: url.path) {
            candidates.append(url)
        }

        guard let binary = candidates.sorted(by: { $0.path < $1.path }).first else {
            throw LocationError.notFound(searchedUnder: buildRoot.path)
        }
        return binary
    }

    /// Runs the binary and waits for it to die, however it dies. The exit
    /// status is returned rather than checked, because the interesting run is
    /// the one that does not exit cleanly.
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

        return Output(
            text: String(decoding: data, as: UTF8.self),
            processIdentifier: process.processIdentifier,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )
    }
}
