import Foundation
import StrategyContent
import TrainingDomain
@testable import PokerCoach

struct DecisionSessionTestContext {
    let viewModel: DecisionSessionViewModel
    let scenario: DecisionScenario
    let store: InMemoryTrainingEventStore
}

actor InMemoryTrainingEventStore: TrainingEventStore {
    private var events: [TrainingEvent]

    init(events: [TrainingEvent] = []) {
        self.events = events
    }

    func append(_ event: TrainingEvent) {
        guard !events.contains(where: { $0.id == event.id }) else {
            return
        }
        events.append(event)
    }

    func allEvents() -> [TrainingEvent] {
        events.sorted {
            ($0.occurredAt, $0.id.uuidString)
                < ($1.occurredAt, $1.id.uuidString)
        }
    }

    func events(after checkpoint: UUID?) throws -> [TrainingEvent] {
        let orderedEvents = allEvents()
        guard let checkpoint else {
            return orderedEvents
        }
        guard let index = orderedEvents.firstIndex(where: {
            $0.id == checkpoint
        }) else {
            throw TrainingEventStoreError.checkpointNotFound
        }
        return Array(orderedEvents.dropFirst(index + 1))
    }
}
/// `makePack` throws rather than trapping: the JSON below goes stale whenever
/// the pack model gains a required field, and a trap took the whole XCTest host
/// process down instead of naming the field in a single failed test.
@MainActor
enum DecisionSessionFixture {
    static let localUserID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    static let deviceID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    static let eventID = UUID(
        uuidString: "30000000-0000-0000-0000-000000000003"
    )!
    static let occurredAt = Date(timeIntervalSince1970: 1_786_000_000)

    static func make() throws -> DecisionSessionTestContext {
        let pack = try makePack()
        let store = InMemoryTrainingEventStore()
        let viewModel = makeViewModel(
            provider: InMemoryStrategyPackProvider(pack: pack),
            store: store
        )
        return DecisionSessionTestContext(
            viewModel: viewModel,
            scenario: pack.scenarios[0],
            store: store
        )
    }

    static func makeViewModel() throws -> DecisionSessionViewModel {
        try make().viewModel
    }

    static func makeViewModel(
        provider: any StrategyPackProviding,
        store: any TrainingEventStore,
        grader: DecisionSessionViewModel.Grader? = nil
    ) -> DecisionSessionViewModel {
        if let grader {
            return DecisionSessionViewModel(
                scenarioID: "fixture-scenario",
                strategyProvider: provider,
                grader: grader,
                eventStore: store,
                localUserID: localUserID,
                deviceID: deviceID,
                makeEventID: { eventID },
                now: { occurredAt }
            )
        }

        return DecisionSessionViewModel(
            scenarioID: "fixture-scenario",
            strategyProvider: provider,
            scorer: DecisionScorer(),
            eventStore: store,
            localUserID: localUserID,
            deviceID: deviceID,
            makeEventID: { eventID },
            now: { occurredAt }
        )
    }

    static func makePack(
        packID: String = "cash-pack",
        contentVersion: String = "2026.08.06",
        generatedSource: String = "decision-session-fixture",
        scenarioID: String = "fixture-scenario",
        scenarioTitle: String = "按钮位",
        abilityDimension: String = "flop-cbet",
        foldEVMilliBB: Int = 0
    ) throws -> StrategyPack {
        let json = """
        {
          "manifest": {
            "id": "\(packID)",
            "schemaVersion": 1,
            "contentVersion": "\(contentVersion)",
            "reviewStatus": "testFixture",
            "generatedSource": "\(generatedSource)",
            "origin": "fixture",
            "reviewedBy": null,
            "reviewedAt": null
          },
          "curriculum": [{
            "id": "\(abilityDimension)",
            "title": "\(abilityDimension)",
            "prerequisiteNodeIDs": []
          }],
          "scenarios": [{
            "id": "\(scenarioID)",
            "title": "\(scenarioTitle)",
            "abilityDimension": "\(abilityDimension)",
            "curriculumNodeID": "\(abilityDimension)",
            "heroSeatOffsetFromButton": 0,
            "heroCards": ["As", "Kh"],
            "board": ["Qs", "Jh", "2c"],
            "decision": {
              "pot": {"centiBB": 1000},
              "effectiveStack": {"centiBB": 10000},
              "amountToCall": {"centiBB": 200},
              "minimumRaiseTo": {"centiBB": 800},
              "configuredBetSizes": [
                {"centiBB": 1200},
                {"centiBB": 800}
              ]
            },
            "options": [
              {
                "action": {"kind": "fold"},
                "frequencyBasisPoints": 1500,
                "ev": {"milliBB": \(foldEVMilliBB)}
              },
              {
                "action": {"kind": "call", "toCentiBB": 200},
                "frequencyBasisPoints": 3000,
                "ev": {"milliBB": 400}
              },
              {
                "action": {"kind": "raise", "toCentiBB": 800},
                "frequencyBasisPoints": 2000,
                "ev": {"milliBB": 500}
              },
              {
                "action": {"kind": "raise", "toCentiBB": 1200},
                "frequencyBasisPoints": 1500,
                "ev": {"milliBB": 450}
              },
              {
                "action": {"kind": "allIn", "toCentiBB": 10000},
                "frequencyBasisPoints": 2000,
                "ev": {"milliBB": 300}
              }
            ],
            "rangeCells": [],
            "assumptions": {
              "gameType": "NLHE cash",
              "tableSize": 6,
              "effectiveStack": {"centiBB": 10000},
              "rakeDescription": "5% capped",
              "allowedBetSizeDescription": "8BB, 12BB, all-in"
            },
            "explanation": {
              "conclusion": "根据范围与底池赔率选择行动。",
              "rangeReasoning": "按钮位范围较宽。",
              "boardReasoning": "高张牌面。",
              "opponentReasoning": "对手范围有上限。",
              "futurePlan": "转牌继续评估。",
              "gtoBaseline": "使用混合策略。",
              "exploitCondition": null
            }
          }]
        }
        """

        return try JSONDecoder().decode(
            StrategyPack.self,
            from: Data(json.utf8)
        )
    }
}
