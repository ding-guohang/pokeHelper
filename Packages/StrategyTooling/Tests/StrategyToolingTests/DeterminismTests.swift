import Foundation
import Testing
@testable import StrategyToolingCore

@Suite("导入确定性")
struct DeterminismTests {
    // GIVEN 同一份导出
    // WHEN 在两个独立进程中导入，两次工作目录、时钟与哈希种子均不同
    // THEN 两次产出的策略包字节完全相同
    //
    // The two runs must be separate processes. `RangeCell.actionWeightsBasisPoints`
    // is a dictionary and Swift seeds its hashing per process, so importing
    // twice inside one process reuses one seed and cannot observe key-order
    // drift — the most likely cause of a checksum that changes between machines.
    @Test("跨进程字节一致")
    func producesIdenticalBytesAcrossProcesses() throws {
        let export = try writeExportFixture()

        let first = try runImporter(
            export: export,
            workingDirectory: try makeScratchDirectory(),
            environment: ["SWIFT_DETERMINISTIC_HASHING": "1", "TZ": "UTC"]
        )
        let second = try runImporter(
            export: export,
            workingDirectory: try makeScratchDirectory(),
            environment: ["TZ": "Asia/Shanghai"]
        )

        #expect(
            first.bytes == second.bytes,
            "两个进程产出的字节不同——最可能是字典序列化顺序随哈希种子变化"
        )
        #expect(first.sha256 == second.sha256)
        #expect(first.sha256 == Self.goldenChecksum)
    }

    // The importer also writes the checksum beside the pack. If that file could
    // disagree with the bytes it names, every downstream verification of it
    // would be checking the wrong thing.
    @Test("写出的 checksum 与字节一致")
    func recordsAChecksumThatMatchesTheBytesItNames() throws {
        let export = try writeExportFixture()
        let run = try runImporter(
            export: export,
            workingDirectory: try makeScratchDirectory(),
            environment: [:]
        )

        #expect(run.recordedChecksum == PackBuilder.sha256Hex(run.bytes))
    }

    /// Pinned so a change in encoding shows up as a failing assertion rather
    /// than as two runs that agree with each other but not with what shipped.
    static let goldenChecksum =
        "333d4049c428f5e2e29fc39aaeaa28cd92306f3b9470a99305018276593e314f"

    // MARK: - Harness

    private struct ImportRun {
        let bytes: Data
        let sha256: String
        let recordedChecksum: String
    }

    private func writeExportFixture() throws -> URL {
        let directory = try makeScratchDirectory()
        let url = directory.appending(path: "export.json")
        try PackBuilder.makeEncoder()
            .encode(SolverExportFixture.export(nodeCount: 3))
            .write(to: url)
        return url
    }

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "strategy-tooling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func runImporter(
        export: URL,
        workingDirectory: URL,
        environment: [String: String]
    ) throws -> ImportRun {
        let output = workingDirectory.appending(path: "pack.json")
        let process = Process()
        process.executableURL = try Self.importerBinary()
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.arguments = [
            "--export", export.path(),
            "--content-version", "2026.08.10",
            "--review-status", "unverifiedDraft",
            "--origin", "fixture",
            "--output", output.path(),
        ]
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HarnessError.importerFailed(
                status: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
            )
        }

        let bytes = try Data(contentsOf: output)
        let recorded = try String(
            contentsOf: workingDirectory.appending(path: "pack.sha256"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return ImportRun(
            bytes: bytes,
            sha256: PackBuilder.sha256Hex(bytes),
            recordedChecksum: recorded
        )
    }

    /// Locates the built importer under the package's build directory.
    ///
    /// Not `Bundle.main`: under `swift test` that resolves to the toolchain's
    /// test runner, not to the build products, so every lookup would miss.
    ///
    /// Throws rather than skipping when the binary is absent. A determinism
    /// test that quietly does nothing is worse than no test, because the gate
    /// stays green while proving nothing.
    private static func importerBinary() throws -> URL {
        let packageRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()   // StrategyToolingTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StrategyTooling
        let buildDirectory = packageRoot.appending(path: ".build")

        var candidates = [buildDirectory.appending(path: "debug/strategy-import")]
        if let entries = try? FileManager.default.contentsOfDirectory(
            atPath: buildDirectory.path()
        ) {
            candidates += entries
                .filter { $0.hasSuffix("-apple-macosx") }
                .map { buildDirectory.appending(path: "\($0)/debug/strategy-import") }
        }

        guard let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path())
        }) else {
            throw HarnessError.importerMissing(
                candidates.map { $0.path() }.joined(separator: ", ")
            )
        }
        return found
    }

    private enum HarnessError: Error, CustomStringConvertible {
        case importerMissing(String)
        case importerFailed(status: Int32, message: String)

        var description: String {
            switch self {
            case let .importerMissing(path):
                "strategy-import 不在 \(path)；跨进程测试无法运行"
            case let .importerFailed(status, message):
                "strategy-import 以 \(status) 退出：\(message)"
            }
        }
    }
}
