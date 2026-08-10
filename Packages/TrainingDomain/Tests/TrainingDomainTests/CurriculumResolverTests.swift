import Foundation
import StrategyContent
import Testing
@testable import TrainingDomain

@Suite("节点归属")
struct CurriculumResolverTests {
    // GIVEN 事件的 pack 与 content version 与当前包一致
    // WHEN 求节点归属
    // THEN 归到内容声明的节点
    @Test("版本一致时归到内容声明的节点")
    func resolvesNodeFromContentWhenVersionMatches() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("scenario-1", "turn-barrel")]
        )
        let event = CurriculumFixture.event(scenarioID: "scenario-1")

        let resolution = CurriculumResolver(pack: pack).resolve(event)

        #expect(resolution == .node("turn-barrel"))
        #expect(resolution.countsTowardMastery)
    }

    // GIVEN 事件记录 2026.08.06，本机只有 2026.09.01
    // WHEN 归约器求节点归属
    // THEN 回退到事件自带的 abilityDimension，且不参与掌握判定
    @Test("内容版本不在本机时回退到事件自带维度")
    func fallsBackToEventDimensionWhenContentVersionAbsent() throws {
        let pack = CurriculumFixture.pack(contentVersion: "2026.09.01")
        let event = CurriculumFixture.event(
            scenarioID: "scenario-1",
            contentVersion: "2026.08.06",
            abilityDimension: "bet-sizing"
        )

        let resolution = CurriculumResolver(pack: pack).resolve(event)

        #expect(resolution == .dimensionOnly("bet-sizing"))
        #expect(resolution.countsTowardMastery == false)
        #expect(resolution.abilityDimension == "bet-sizing")
    }

    // A matching version from a different pack is still not this content.
    @Test("pack ID 不同时同样回退")
    func fallsBackWhenThePackIDDiffers() throws {
        let pack = CurriculumFixture.pack(packID: "other-pack")
        let event = CurriculumFixture.event(
            scenarioID: "scenario-1",
            packID: "cash-pack",
            abilityDimension: "bet-sizing"
        )

        #expect(
            CurriculumResolver(pack: pack).resolve(event)
                == .dimensionOnly("bet-sizing")
        )
    }

    // Same pack and version, but the scenario is gone. Attributing it to some
    // other node would be worse than declining to attribute it at all.
    @Test("同版本但场景已不存在时回退")
    func fallsBackWhenTheScenarioIsAbsentFromAMatchingPack() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("scenario-2", "turn-barrel")]
        )
        let event = CurriculumFixture.event(
            scenarioID: "scenario-1",
            abilityDimension: "bet-sizing"
        )

        #expect(
            CurriculumResolver(pack: pack).resolve(event)
                == .dimensionOnly("bet-sizing")
        )
    }

    // Dropping the event would let a content upgrade shrink the user's history.
    @Test("回退事件仍计入维度样本")
    func fallbackEventStillCountsTowardTheDimensionSample() throws {
        let events = [
            CurriculumFixture.event(
                scenarioID: "scenario-from-old-pack",
                contentVersion: "2026.08.06",
                abilityDimension: "bet-sizing"
            ),
            CurriculumFixture.event(
                scenarioID: "scenario-1",
                contentVersion: "2026.09.01",
                abilityDimension: "bet-sizing"
            ),
        ]

        let profile = PlayerModelReducer().reduce(events: events)

        #expect(profile["bet-sizing"]?.sampleCount == 2)
    }

    @Test("按节点分组只收录归属明确的事件")
    func groupsOnlyResolvedEventsByNode() throws {
        let pack = CurriculumFixture.pack(
            scenarios: [("scenario-1", "turn-barrel"), ("scenario-2", "flop-cbet")],
            nodes: [("turn-barrel", []), ("flop-cbet", [])]
        )
        let resolver = CurriculumResolver(pack: pack)
        let events = [
            CurriculumFixture.event(scenarioID: "scenario-1"),
            CurriculumFixture.event(scenarioID: "scenario-1"),
            CurriculumFixture.event(scenarioID: "scenario-2"),
            CurriculumFixture.event(
                scenarioID: "scenario-1",
                contentVersion: "2020.01.01"
            ),
        ]

        let grouped = resolver.eventsByNode(events)

        #expect(grouped["turn-barrel"]?.count == 2)
        #expect(grouped["flop-cbet"]?.count == 1)
        #expect(grouped.values.map { $0.count }.reduce(0, +) == 3)
    }

    // GIVEN 两台设备持有相同的去重事件集合但写入顺序不同
    // WHEN 各自独立归约
    // THEN 得到逐字段相等的画像
    @Test("两台设备独立归约得到相同画像")
    func reducesIdenticallyRegardlessOfLocalWriteOrder() throws {
        let events = [
            CurriculumFixture.event(quality: .excellent, confidence: .verySure, daysAfterEpoch: 0),
            CurriculumFixture.event(quality: .blunder, confidence: .verySure, daysAfterEpoch: 1),
            CurriculumFixture.event(quality: .acceptable, confidence: .unsure, daysAfterEpoch: 2),
            CurriculumFixture.event(quality: .improvable, confidence: .verySure, daysAfterEpoch: 3),
            CurriculumFixture.event(quality: .excellent, confidence: .guessing, daysAfterEpoch: 4),
        ]
        let reducer = PlayerModelReducer()

        let deviceA = reducer.reduce(events: events)
        let deviceB = reducer.reduce(events: events.reversed())

        #expect(deviceA == deviceB)
        let snapshot = try #require(deviceA["bet-sizing"])
        #expect(snapshot.sampleCount == 5)
        #expect(snapshot.highConfidenceErrorCount == 2)
    }
}
