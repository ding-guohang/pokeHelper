import Foundation
import PokerCore
import StrategyContent
import Testing
@testable import StrategyToolingCore

@Suite("求解器导出导入")
struct PackBuilderTests {
    // GIVEN 一份含 N 个决策节点的求解器导出
    // WHEN 导入工具生成策略包
    // THEN 场景数等于 N，且每条 (action, frequency, ev) 在输出中逐字段可找到
    @Test("输出逐条对应输入")
    func outputCorrespondsToInput() throws {
        let export = SolverExportFixture.export(nodeCount: 3)

        let pack = try PackBuilder().build(
            from: export,
            contentVersion: "2026.08.10",
            reviewStatus: .unverifiedDraft,
            origin: .fixture,
            reviewedBy: nil,
            reviewedAt: nil
        )

        #expect(pack.scenarios.count == 3)
        for node in export.nodes {
            let scenario = try #require(pack.scenarios.first { $0.id == node.id })
            #expect(scenario.options.count == node.actions.count)
            for action in node.actions {
                let option = try #require(
                    scenario.options.first { $0.action == action.action }
                )
                #expect(option.frequencyBasisPoints == action.frequencyBasisPoints)
                #expect(option.ev == action.ev)
            }
            #expect(scenario.curriculumNodeID == node.curriculumNodeID)
            #expect(scenario.heroSeatOffsetFromButton == node.heroSeatOffsetFromButton)
        }
        try StrategyPackValidator().validate(pack)
    }

    @Test("manifest 记录来源与版本")
    func stampsProvenanceOntoTheManifest() throws {
        let export = SolverExportFixture.export(nodeCount: 1)

        let pack = try PackBuilder().build(
            from: export,
            contentVersion: "2026.08.10",
            reviewStatus: .unverifiedDraft,
            origin: .fixture,
            reviewedBy: nil,
            reviewedAt: nil
        )

        #expect(pack.manifest.id == export.packID)
        #expect(pack.manifest.schemaVersion == 1)
        #expect(pack.manifest.contentVersion == "2026.08.10")
        #expect(pack.manifest.reviewStatus == .unverifiedDraft)
        #expect(pack.manifest.generatedSource.contains("fixture-solver 1.0"))
        #expect(pack.manifest.reviewedBy == nil)
    }

    // The importer must not be able to mint reviewed content on its own.
    @Test("导入工具不能凭空产出已审核内容")
    func refusesToMarkContentReviewedWithoutAReviewer() throws {
        let export = SolverExportFixture.export(nodeCount: 1)

        #expect(throws: PackBuildError.invalidPack(.missingReviewedBy)) {
            try PackBuilder().build(
                from: export,
                contentVersion: "2026.08.10",
                reviewStatus: .reviewed,
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: Date(timeIntervalSince1970: 1_786_000_000)
            )
        }
    }

    // GIVEN 某节点频率总和不是 10,000
    // WHEN 导入处理该导出
    // THEN 失败并指明场景 ID 与实际总和
    //
    // The importer surfaces the validator's typed error rather than restating
    // the frequency rule. A second copy of the rule is a second thing that can
    // drift away from the content model.
    @Test("频率总和不合法时导入失败")
    func rejectsABadFrequencyTotal() throws {
        let export = SolverExportFixture.export(
            nodeCount: 2,
            frequencyTotalOverride: 9_900
        )

        #expect(
            throws: PackBuildError.invalidPack(
                .invalidFrequencyTotal(scenarioID: "node-1", actual: 9_900)
            )
        ) {
            try PackBuilder().build(
                from: export,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            )
        }
    }

    // AND 不产出任何部分写入的策略包
    @Test("导入失败时输出目录为空")
    func leavesNoPartialFileBehindWhenTheExportIsInvalid() throws {
        let export = SolverExportFixture.export(
            nodeCount: 2,
            frequencyTotalOverride: 9_900
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: (any Error).self) {
            try PackBuilder().write(
                from: export,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil,
                to: directory.appending(path: "pack.json")
            )
        }

        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: directory.path()
        )
        #expect(leftovers.isEmpty, "失败的导入在输出目录留下了 \(leftovers)")
    }

    @Test("成功导入会写出策略包与 checksum")
    func writesThePackAndItsChecksum() throws {
        let export = SolverExportFixture.export(nodeCount: 2)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "pack.json")

        let result = try PackBuilder().write(
            from: export,
            contentVersion: "2026.08.10",
            reviewStatus: .unverifiedDraft,
            origin: .fixture,
            reviewedBy: nil,
            reviewedAt: nil,
            to: output
        )

        let written = try Data(contentsOf: output)
        #expect(result.sha256 == PackBuilder.sha256Hex(written))

        let checksumFile = directory.appending(path: "pack.sha256")
        let recorded = try String(contentsOf: checksumFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(recorded == result.sha256)

        // The written bytes have to survive the app's own loader, checksum and
        // all. Producing something only the importer can read would be useless.
        let reloaded = try StrategyPackLoader().load(
            data: written,
            expectedSHA256: result.sha256
        )
        #expect(reloaded.scenarios.count == 2)
    }

    @Test("空导出被拒绝")
    func rejectsAnExportWithNoNodes() throws {
        let export = SolverExportFixture.export(nodeCount: 0)

        #expect(throws: PackBuildError.invalidPack(.emptyScenarios)) {
            try PackBuilder().build(
                from: export,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            )
        }
    }

    @Test("无法解析的牌面被拒绝")
    func rejectsAnUnparseableCard() throws {
        var export = SolverExportFixture.export(nodeCount: 1)
        export = SolverExport(
            packID: export.packID,
            generatedSource: export.generatedSource,
            exportedAt: export.exportedAt,
            gameType: export.gameType,
            tableSize: export.tableSize,
            effectiveStack: export.effectiveStack,
            rakeDescription: export.rakeDescription,
            allowedBetSizeDescription: export.allowedBetSizeDescription,
            curriculum: export.curriculum,
            nodes: [
                SolverNode(
                    id: "node-0",
                    title: export.nodes[0].title,
                    abilityDimension: export.nodes[0].abilityDimension,
                    curriculumNodeID: export.nodes[0].curriculumNodeID,
                    heroSeatOffsetFromButton: 0,
                    facing: export.nodes[0].facing,
                    heroCards: ["Zz", "Kd"],
                    board: export.nodes[0].board,
                    pot: export.nodes[0].pot,
                    amountToCall: export.nodes[0].amountToCall,
                    minimumRaiseTo: export.nodes[0].minimumRaiseTo,
                    configuredBetSizes: export.nodes[0].configuredBetSizes,
                    actions: export.nodes[0].actions,
                    rangeCells: export.nodes[0].rangeCells,
                    explanation: export.nodes[0].explanation
                ),
            ]
        )

        #expect(
            throws: PackBuildError.unparseableCard(scenarioID: "node-0", code: "Zz")
        ) {
            try PackBuilder().build(
                from: export,
                contentVersion: "2026.08.10",
                reviewStatus: .unverifiedDraft,
                origin: .fixture,
                reviewedBy: nil,
                reviewedAt: nil
            )
        }
    }
}
