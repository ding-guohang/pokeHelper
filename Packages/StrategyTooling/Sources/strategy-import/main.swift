import Foundation
import StrategyContent
import StrategyToolingCore

/// Turns a solver export into a versioned strategy pack.
///
/// Review status is an explicit argument with no default. The tool will not
/// mint `reviewed` content on its own: that status asserts a human checked the
/// strategy, and the validator refuses it without a named reviewer.
@main
struct StrategyImport {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as UsageError {
            FileHandle.standardError.write(Data("\(error.message)\n\n\(usage)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("import failed: \(error)\n".utf8))
            exit(1)
        }
    }

    struct UsageError: Error {
        let message: String
    }

    static let usage = """
    usage: strategy-import --export <path> --content-version <version> \
    --review-status <testFixture|unverifiedDraft|reviewed|retired> \
    --origin <solver|generativeModel|fixture> \
    [--reviewed-by <name>] [--reviewed-at <ISO8601>] \
    (--output <path> | --print-range-tables)
    """

    static func run(arguments: [String]) throws {
        let options = try Options(arguments: arguments)
        let exportData = try Data(contentsOf: URL(filePath: options.exportPath))
        let export = try PackBuilder.makeDecoder().decode(
            SolverExport.self,
            from: exportData
        )

        if options.printRangeTables {
            print(RangeTableReport().render(export))
            return
        }

        guard let outputPath = options.outputPath else {
            throw UsageError(
                message: "--output is required unless --print-range-tables is used"
            )
        }

        let result = try PackBuilder().write(
            from: export,
            contentVersion: options.contentVersion,
            reviewStatus: options.reviewStatus,
            origin: options.origin,
            reviewedBy: options.reviewedBy,
            reviewedAt: options.reviewedAt,
            to: URL(filePath: outputPath)
        )
        print("wrote \(outputPath) (\(result.byteCount) bytes)")
        print("sha256 \(result.sha256)")
    }

    struct Options {
        let exportPath: String
        let contentVersion: String
        let reviewStatus: ReviewStatus
        let origin: ContentOrigin
        let reviewedBy: String?
        let reviewedAt: Date?
        let outputPath: String?
        let printRangeTables: Bool

        init(arguments: [String]) throws {
            var values: [String: String] = [:]
            var printRangeTables = false
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--print-range-tables" {
                    printRangeTables = true
                    index += 1
                    continue
                }
                guard argument.hasPrefix("--"), index + 1 < arguments.count else {
                    throw UsageError(message: "unexpected argument \(argument)")
                }
                values[String(argument.dropFirst(2))] = arguments[index + 1]
                index += 2
            }

            guard let exportPath = values["export"] else {
                throw UsageError(message: "--export is required")
            }

            // Printing range tables reads the export and writes nothing, so it
            // needs neither a content version nor a review status. Demanding
            // them would force the reviewer to name a status before they have
            // reviewed anything.
            var reviewStatus = ReviewStatus.unverifiedDraft
            if let rawStatus = values["review-status"] {
                guard let parsed = ReviewStatus(rawValue: rawStatus) else {
                    throw UsageError(message: "unknown review status \(rawStatus)")
                }
                reviewStatus = parsed
            } else if !printRangeTables {
                throw UsageError(message: "--review-status is required")
            }

            // No default. Origin decides whether the app discloses provenance,
            // so guessing it would be guessing at what the user is told.
            var origin = ContentOrigin.fixture
            if let rawOrigin = values["origin"] {
                guard let parsed = ContentOrigin(rawValue: rawOrigin) else {
                    throw UsageError(message: "unknown origin \(rawOrigin)")
                }
                origin = parsed
            } else if !printRangeTables {
                throw UsageError(message: "--origin is required")
            }

            let contentVersion = values["content-version"] ?? ""
            if contentVersion.isEmpty, !printRangeTables {
                throw UsageError(message: "--content-version is required")
            }

            var parsedReviewedAt: Date?
            if let rawReviewedAt = values["reviewed-at"] {
                guard let parsed = ISO8601DateFormatter().date(from: rawReviewedAt) else {
                    throw UsageError(
                        message: "--reviewed-at must be ISO8601, got \(rawReviewedAt)"
                    )
                }
                parsedReviewedAt = parsed
            }

            self.exportPath = exportPath
            self.contentVersion = contentVersion
            self.reviewStatus = reviewStatus
            self.origin = origin
            reviewedBy = values["reviewed-by"]
            reviewedAt = parsedReviewedAt
            outputPath = values["output"]
            self.printRangeTables = printRangeTables
        }
    }
}
