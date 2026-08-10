import Foundation
import Testing
@testable import StrategyContent

@Suite("能力树校验")
struct CurriculumTreeTests {
    @Test("场景引用了不存在的节点")
    func rejectsScenarioPointingAtUnknownNode() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: []),
            ],
            scenarioNodeID: "turn-barrel"
        )

        #expect(
            throws: StrategyPackValidationError.unknownCurriculumNode(
                scenarioID: StrategyPackFixture.scenarioID,
                nodeID: "turn-barrel"
            )
        ) {
            try StrategyPackValidator().validate(pack)
        }
    }

    @Test("前置节点无法解析")
    func rejectsUnresolvablePrerequisite() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(
                    id: "turn-barrel",
                    title: "转牌持续下注",
                    prerequisiteNodeIDs: ["flop-cbet"]
                ),
            ],
            scenarioNodeID: "turn-barrel"
        )

        #expect(
            throws: StrategyPackValidationError.unknownPrerequisite(
                nodeID: "turn-barrel",
                prerequisiteID: "flop-cbet"
            )
        ) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // A cycle makes "unlocked once every prerequisite is mastered" permanently
    // unsatisfiable, and makes any depth-first walk of the tree non-terminating.
    // It has to be refused at load time rather than survive into the UI.
    @Test("能力树有环")
    func rejectsCyclicTree() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "a", title: "A", prerequisiteNodeIDs: ["b"]),
                CurriculumNode(id: "b", title: "B", prerequisiteNodeIDs: ["a"]),
            ],
            scenarioNodeID: "a"
        )

        #expect(
            throws: StrategyPackValidationError.cyclicCurriculum(nodeIDs: ["a", "b"])
        ) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // A node that lists itself is the shortest cycle and is easy to miss with a
    // detector that only tracks edges between distinct nodes.
    @Test("节点以自身为前置")
    func rejectsSelfReferencingNode() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "a", title: "A", prerequisiteNodeIDs: ["a"]),
            ],
            scenarioNodeID: "a"
        )

        #expect(
            throws: StrategyPackValidationError.cyclicCurriculum(nodeIDs: ["a"])
        ) {
            try StrategyPackValidator().validate(pack)
        }
    }

    @Test("合法能力树通过校验")
    func acceptsAcyclicResolvableTree() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: []),
                CurriculumNode(
                    id: "flop-cbet",
                    title: "翻牌持续下注",
                    prerequisiteNodeIDs: ["preflop-rfi"]
                ),
            ],
            scenarioNodeID: "flop-cbet"
        )

        try StrategyPackValidator().validate(pack)

        #expect(pack.curriculum.count == 2)
        #expect(pack.scenarios[0].curriculumNodeID == "flop-cbet")
    }

    // A diamond is acyclic but revisits a node along two different paths. A
    // detector that marks nodes visited-forever without distinguishing
    // "on the current path" would call this a cycle.
    @Test("菱形依赖不是环")
    func acceptsADiamondDependency() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "root", title: "根", prerequisiteNodeIDs: []),
                CurriculumNode(id: "left", title: "左", prerequisiteNodeIDs: ["root"]),
                CurriculumNode(id: "right", title: "右", prerequisiteNodeIDs: ["root"]),
                CurriculumNode(id: "join", title: "汇合", prerequisiteNodeIDs: ["left", "right"]),
            ],
            scenarioNodeID: "join"
        )

        try StrategyPackValidator().validate(pack)
    }

    // The curriculum travels inside the pack, so it has to survive decoding.
    @Test("能力树可编解码")
    func roundTripsThroughJSON() throws {
        let pack = try StrategyPackFixture.pack(
            curriculum: [
                CurriculumNode(id: "preflop-rfi", title: "翻前开池", prerequisiteNodeIDs: []),
            ],
            scenarioNodeID: "preflop-rfi"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            StrategyPack.self,
            from: encoder.encode(pack)
        )

        #expect(decoded.curriculum == pack.curriculum)
        #expect(decoded.scenarios[0].curriculumNodeID == "preflop-rfi")
    }
}
