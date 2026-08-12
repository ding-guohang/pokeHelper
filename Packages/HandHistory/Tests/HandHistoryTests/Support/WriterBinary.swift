import Foundation

/// Finds and runs `hand-model-writer`.
///
/// The cross-process determinism property is only tested honestly by two
/// processes: hash seeds, `Dictionary` iteration order and the like are stable
/// within one launch and only a second launch can expose a difference. So this
/// helper launches the writer as a child process; the test runs it twice and
/// compares the bytes. Modeled on `SessionPersistence`'s `WriterBinary`.
enum WriterBinary {
    enum LocationError: Error, CustomStringConvertible {
        case notFound(searchedUnder: String)

        var description: String {
            switch self {
            case let .notFound(root):
                "hand-model-writer was not found under \(root). It is a dependency of "
                    + "the test target, so `swift test` should have built it."
            }
        }
    }

    struct Output {
        let data: Data
        let processIdentifier: Int32
        let terminationStatus: Int32
    }

    /// The package root, from this file's own location: a test does not control
    /// its working directory.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // HandHistoryTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // HandHistory
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
        where url.lastPathComponent == "hand-model-writer"
            && !url.path.contains(".dSYM")
            && fileManager.isExecutableFile(atPath: url.path) {
            candidates.append(url)
        }

        guard let binary = candidates.sorted(by: { $0.path < $1.path }).first else {
            throw LocationError.notFound(searchedUnder: buildRoot.path)
        }
        return binary
    }

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
            data: data,
            processIdentifier: process.processIdentifier,
            terminationStatus: process.terminationStatus
        )
    }
}
