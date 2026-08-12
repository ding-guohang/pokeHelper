import Foundation
import Testing
@testable import HandHistory

/// The cross-process property, tested with two processes on purpose.
///
/// Hash seeds, `Dictionary` iteration order and `SortedKeys` are all stable
/// inside a single launch; only a second launch can expose a difference. So the
/// writer runs as a child process twice, and the canonical JSON bytes are
/// compared against each other and against the committed golden.
@Suite("跨进程规范序列化与黄金")
struct CrossProcessDeterminismTests {
    @Test("两个独立进程解析附录 A 得到逐字节相同的规范序列化，且等于黄金夹具")
    func twoProcessesAgreeAndMatchGolden() throws {
        let binary = try WriterBinary.locate()
        let fixture = Fixtures.url("sample-ps-6max-nlhe.txt").path
        let arguments = ["--fixture", fixture]

        let first = try WriterBinary.run(binary, arguments: arguments)
        let second = try WriterBinary.run(binary, arguments: arguments)

        #expect(first.terminationStatus == 0, "写入器非零退出：\(first.terminationStatus)")
        #expect(second.terminationStatus == 0)

        // The two runs really were two processes.
        #expect(
            first.processIdentifier != second.processIdentifier,
            "两次运行是同一个进程 \(first.processIdentifier)"
        )

        // And they produced something.
        #expect(!first.data.isEmpty, "写入器没有输出")
        let asText = String(decoding: first.data, as: UTF8.self)
        #expect(asText.contains("bigBlindCentiBB"), "输出不像规范序列化")

        #expect(first.data == second.data, "两个进程的规范序列化不同")

        let golden = try Fixtures.data("sample-ps-6max-nlhe.model.json")
        #expect(golden.count > 200, "黄金夹具只有 \(golden.count) 字节，太短")

        guard first.data == golden else {
            Issue.record(Comment(rawValue: """
            规范序列化与提交的黄金 sample-ps-6max-nlhe.model.json 不同。
            如果这是有意的模型改动，重新生成：
              swift run --package-path Packages/HandHistory hand-model-writer \
                --fixture Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.txt \
                > Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.model.json
            """))
            return
        }
    }

    @Test("不支持的输入使写入器非零退出")
    func unsupportedExitsNonZero() throws {
        let binary = try WriterBinary.locate()
        let fixture = Fixtures.url("sample-ps-tournament.txt").path
        let output = try WriterBinary.run(binary, arguments: ["--fixture", fixture])

        #expect(output.terminationStatus != 0, "锦标赛应使写入器非零退出")
        #expect(output.data.isEmpty, "不支持时不应向 stdout 打印模型")
    }
}
