import Foundation
import StrategyContent
import TrainingDomain

/// Builds the exact event captured in `Contracts/training-event-upload-v1.json`.
///
/// The identifiers deliberately contain hex letters. The original fixture used
/// UUIDs made only of digits, which made a byte-exact comparison blind to
/// letter casing — and Foundation encodes UUID in uppercase while Go's
/// convention is lowercase. That blind spot let a mismatch reach the wire
/// unnoticed, so the fixture now exercises the characters that can differ.
///
/// The grade comes from the real scorer rather than being hand-written, so the
/// canonical bytes this fixture produces can only match the shared contract if
/// the domain really does grade a pure check that way.
///
/// Both the decode and the grade throw rather than trapping: this JSON goes
/// stale whenever the pack model gains a required field, and a trap took the
/// XCTest host process down with it instead of naming the field.
@MainActor
enum ContractEventFixture {
    static func make(
        id: UUID = UUID(uuidString: "a1b2c3d4-0000-4000-8000-00000000000f")!
    ) throws -> TrainingEvent {
        let scenario = try pack().scenarios[0]
        let submission = DecisionSubmission(
            action: scenario.options[0].action,
            confidence: .verySure
        )
        let grade = try DecisionScorer().grade(
            submission: submission,
            scenario: scenario
        )
        return TrainingEvent(
            id: id,
            localUserID: UUID(uuidString: "1abcdef0-0000-4000-8000-00000000000a")!,
            deviceID: UUID(uuidString: "2bcdef01-0000-4000-8000-00000000000b")!,
            occurredAt: Date(timeIntervalSince1970: 1_786_060_800),
            scenarioID: "scenario-1",
            strategyPackID: "cash-pack",
            strategyContentVersion: "2026.08.06",
            abilityDimension: "bet-sizing",
            submission: submission,
            grade: grade
        )
    }

    private static func pack() throws -> StrategyPack {
        let json = """
        {
          "manifest": {
            "id": "cash-pack",
            "schemaVersion": 1,
            "contentVersion": "2026.08.06",
            "reviewStatus": "testFixture",
            "generatedSource": "contract-fixture",
            "origin": "fixture",
            "reviewedBy": null,
            "reviewedAt": null
          },
          "curriculum": [{
            "id": "bet-sizing",
            "title": "下注尺度",
            "prerequisiteNodeIDs": []
          }],
          "scenarios": [{
            "id": "scenario-1",
            "title": "大盲位",
            "abilityDimension": "bet-sizing",
            "curriculumNodeID": "bet-sizing",
            "heroSeatOffsetFromButton": 0,
            "heroCards": ["As", "Kh"],
            "board": ["Qs", "Jh", "2c"],
            "decision": {
              "pot": {"centiBB": 1000},
              "effectiveStack": {"centiBB": 10000},
              "amountToCall": {"centiBB": 0},
              "minimumRaiseTo": {"centiBB": 200},
              "configuredBetSizes": []
            },
            "options": [
              {
                "action": {"kind": "check"},
                "frequencyBasisPoints": 10000,
                "ev": {"milliBB": 1000}
              }
            ],
            "rangeCells": [],
            "assumptions": {
              "gameType": "NLHE cash",
              "tableSize": 6,
              "effectiveStack": {"centiBB": 10000},
              "rakeDescription": "5% capped",
              "allowedBetSizeDescription": "check only"
            },
            "explanation": {
              "conclusion": "过牌控制底池。",
              "rangeReasoning": "范围较宽。",
              "boardReasoning": "湿润牌面。",
              "opponentReasoning": "对手范围有上限。",
              "futurePlan": "转牌继续评估。",
              "gtoBaseline": "纯过牌。",
              "exploitCondition": null
            }
          }]
        }
        """
        return try JSONDecoder().decode(StrategyPack.self, from: Data(json.utf8))
    }
}
