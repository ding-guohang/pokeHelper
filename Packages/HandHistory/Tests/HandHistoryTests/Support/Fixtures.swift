import Foundation

/// Reads the committed hand fixtures under `Tests/Fixtures/`.
///
/// Located from this file's own position rather than the working directory: a
/// test does not choose its working directory. The files sit at the paths the
/// spec names, so they are read from disk rather than bundled as SwiftPM
/// resources.
enum Fixtures {
    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case let .missing(path): "夹具缺失：\(path)"
            }
        }
    }

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // HandHistoryTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures")
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func text(_ name: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw FixtureError.missing(url.path)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func data(_ name: String) throws -> Data {
        let url = directory.appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw FixtureError.missing(url.path)
        }
        return data
    }
}
