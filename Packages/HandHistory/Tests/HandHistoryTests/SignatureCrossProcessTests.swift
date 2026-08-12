import Foundation
import Testing
@testable import HandHistory

/// The `--signatures` output, tested with two processes on purpose.
///
/// As with the model golden, hash seeds and `Dictionary` iteration order are
/// stable within one launch; only a second launch can expose a difference. So
/// the writer runs as a child process twice in `--signatures` mode, and the
/// bytes are compared against each other and against the committed golden.
@Suite("跨进程签名黄金")
struct SignatureCrossProcessTests {
    @Test("两个独立进程导出附录 A 的英雄签名得到逐字节相同的输出，且等于黄金")
    func twoProcessesAgreeAndMatchGolden() throws {
        let binary = try WriterBinary.locate()
        let fixture = Fixtures.url("sample-ps-6max-nlhe.txt").path
        let arguments = ["--signatures", "--fixture", fixture]

        let first = try WriterBinary.run(binary, arguments: arguments)
        let second = try WriterBinary.run(binary, arguments: arguments)

        #expect(first.terminationStatus == 0, "写入器非零退出：\(first.terminationStatus)")
        #expect(second.terminationStatus == 0)

        // The two runs really were two processes.
        #expect(
            first.processIdentifier != second.processIdentifier,
            "两次运行是同一个进程 \(first.processIdentifier)"
        )

        // And they produced something that looks like the signature array.
        #expect(!first.data.isEmpty, "写入器没有输出")
        let asText = String(decoding: first.data, as: UTF8.self)
        #expect(asText.contains("heroSeatOffsetFromButton"), "输出不像签名序列化")

        #expect(first.data == second.data, "两个进程的签名序列化不同")

        let golden = try Fixtures.data("sample-ps-6max-nlhe.signatures.json")
        #expect(golden.count > 200, "黄金夹具只有 \(golden.count) 字节，太短")

        guard first.data == golden else {
            Issue.record(Comment(rawValue: """
            签名序列化与提交的黄金 sample-ps-6max-nlhe.signatures.json 不同。
            如果这是有意的改动，重新生成：
              swift run --package-path Packages/HandHistory hand-model-writer \
                --signatures \
                --fixture Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.txt \
                > Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.signatures.json
            """))
            return
        }
    }
}
