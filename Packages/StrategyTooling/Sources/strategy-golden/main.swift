import Foundation
import StrategyContent
import StrategyToolingCore

/// Runs the golden-data regression that `docs/standards/strategy-content.md`
/// requires of every content upgrade.
///
/// Exits non-zero when a graded outcome crosses a quality boundary, moves
/// further than the tolerance, or when the new pack has dropped a scenario the
/// golden set covers. It prints every case either way: a report that lists only
/// breaches cannot distinguish "nothing moved" from "moved but stayed inside
/// tolerance".
@main
struct StrategyGolden {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as UsageError {
            FileHandle.standardError.write(Data("\(error.message)\n\n\(usage)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("regression failed: \(error)\n".utf8))
            exit(1)
        }
    }

    struct UsageError: Error {
        let message: String
    }

    static let usage = """
    usage: strategy-golden --old <pack.json> --new <pack.json> \
    --cases <cases.json> [--tolerance <basisPoints>]
    """

    static func run(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index + 1 < arguments.count {
            guard arguments[index].hasPrefix("--") else {
                throw UsageError(message: "unexpected argument \(arguments[index])")
            }
            values[String(arguments[index].dropFirst(2))] = arguments[index + 1]
            index += 2
        }

        guard let oldPath = values["old"],
              let newPath = values["new"],
              let casesPath = values["cases"]
        else {
            throw UsageError(message: "--old, --new and --cases are all required")
        }

        let tolerance: Int
        if let raw = values["tolerance"] {
            guard let parsed = Int(raw) else {
                throw UsageError(message: "--tolerance must be an integer, got \(raw)")
            }
            tolerance = parsed
        } else {
            tolerance = 50
        }

        let decoder = PackBuilder.makeDecoder()
        let loader = StrategyPackLoader()
        let old = try loader.load(
            data: try Data(contentsOf: URL(filePath: oldPath)),
            expectedSHA256: nil
        )
        let new = try loader.load(
            data: try Data(contentsOf: URL(filePath: newPath)),
            expectedSHA256: nil
        )
        let cases = try decoder.decode(
            [GoldenCase].self,
            from: try Data(contentsOf: URL(filePath: casesPath))
        )

        let regression = GoldenRegression()
        let report = try regression.compare(
            old: old,
            new: new,
            cases: cases,
            toleranceBasisPoints: tolerance
        )
        print(regression.render(report))
        exit(report.exitCode)
    }
}
