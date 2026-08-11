import Foundation
import StrategyContent
import TrainingDomain
@testable import PokerCoach

struct FeedbackFixtureContext {
    let manifest: StrategyPackManifest
    let scenario: DecisionScenario
    let submission: DecisionSubmission
    let grade: DecisionGrade
}

/// Throwing rather than trapping on purpose.
///
/// These fixtures decode hand-written pack JSON, so they go stale whenever the
/// pack model gains a required field. When the failure was a
/// `preconditionFailure` it killed the XCTest host process, xcodebuild retried
/// the whole bundle, and the decode error naming the missing field never
/// reached anyone — it surfaced as "the app crashes on launch". A thrown error
/// fails one test and prints the field.
enum FeedbackFixture {
    static func mixedStrategy() throws -> FeedbackFixtureContext {
        try context(
            reviewStatus: "testFixture",
            contentVersion: "1.2.3",
            exploitCondition: nil
        )
    }

    static func developmentPresentation() throws -> FeedbackPresentation {
        presentation(from: try mixedStrategy())
    }

    static func exploitPresentation() throws -> FeedbackPresentation {
        presentation(
            from: try context(
                reviewStatus: "testFixture",
                contentVersion: "1.2.3",
                exploitCondition: "仅当对手过度弃牌时提高下注频率。"
            )
        )
    }

    static func reviewedPresentation() throws -> FeedbackPresentation {
        presentation(
            from: try context(
                reviewStatus: "reviewed",
                contentVersion: "2.0.0",
                exploitCondition: nil
            )
        )
    }

    private static func context(
        reviewStatus: String,
        contentVersion: String,
        exploitCondition: String?
    ) throws -> FeedbackFixtureContext {
        let pack = try decodePack(
            reviewStatus: reviewStatus,
            contentVersion: contentVersion,
            exploitCondition: exploitCondition
        )
        let scenario = pack.scenarios[0]
        let submission = DecisionSubmission(
            action: scenario.options[1].action,
            confidence: .unsure
        )

        return FeedbackFixtureContext(
            manifest: pack.manifest,
            scenario: scenario,
            submission: submission,
            grade: try DecisionScorer().grade(
                submission: submission,
                scenario: scenario
            )
        )
    }

    private static func presentation(
        from fixture: FeedbackFixtureContext
    ) -> FeedbackPresentation {
        return FeedbackPresentation(
            scenario: fixture.scenario,
            submission: fixture.submission,
            grade: fixture.grade,
            manifest: fixture.manifest
        )
    }

    private static func decodePack(
        reviewStatus: String,
        contentVersion: String,
        exploitCondition: String?
    ) throws -> StrategyPack {
        let exploitJSON = exploitCondition.map { "\"\($0)\"" } ?? "null"
        let reviewedAtJSON = reviewStatus == "reviewed"
            ? "\"2026-08-06T00:00:00Z\""
            : "null"
        // reviewed content is rejected without a reviewer, so the fixture has
        // to name one for exactly the statuses that require it.
        let reviewedByJSON = reviewStatus == "reviewed"
            ? "\"Meow Ding\""
            : "null"
        let json = """
        {
          "manifest": {
            "id": "feedback-fixture",
            "schemaVersion": 1,
            "contentVersion": "\(contentVersion)",
            "reviewStatus": "\(reviewStatus)",
            "generatedSource": "feedback-unit-test",
            "origin": "fixture",
            "reviewedBy": \(reviewedByJSON),
            "reviewedAt": \(reviewedAtJSON)
          },
          "curriculum": [{
            "id": "flop-cbet",
            "title": "翻牌持续下注",
            "prerequisiteNodeIDs": []
          }],
          "scenarios": [{
            "id": "mixed-feedback",
            "title": "混合策略反馈",
            "abilityDimension": "flop-cbet",
            "curriculumNodeID": "flop-cbet",
            "heroSeatOffsetFromButton": 0,
            "heroCards": ["As", "Kd"],
            "board": ["7c", "8h", "2s"],
            "decision": {
              "pot": {"centiBB": 650},
              "effectiveStack": {"centiBB": 10000},
              "amountToCall": {"centiBB": 0},
              "minimumRaiseTo": null,
              "configuredBetSizes": [
                {"centiBB": 217},
                {"centiBB": 488}
              ]
            },
            "options": [
              {
                "action": {"kind": "check"},
                "frequencyBasisPoints": 4000,
                "ev": {"milliBB": 1000}
              },
              {
                "action": {"kind": "bet", "toCentiBB": 217},
                "frequencyBasisPoints": 3500,
                "ev": {"milliBB": 980}
              },
              {
                "action": {"kind": "bet", "toCentiBB": 488},
                "frequencyBasisPoints": 2500,
                "ev": {"milliBB": 700}
              }
            ],
            "rangeCells": [{
              "handClass": "AKo",
              "actionWeightsBasisPoints": {
                "check": 4000,
                "bet-217": 3500,
                "bet-488": 2500
              }
            }],
            "assumptions": {
              "gameType": "NLHE cash",
              "tableSize": 6,
              "effectiveStack": {"centiBB": 10000},
              "rakeDescription": "5% capped",
              "allowedBetSizeDescription": "2.17BB, 4.88BB"
            },
            "explanation": {
              "conclusion": "本节点保留过牌与两种下注频率。",
              "rangeReasoning": "范围中包含强牌与需要保护的边缘牌。",
              "boardReasoning": "低张连通牌面让多种尺度都有用途。",
              "opponentReasoning": "假设对手采用平衡继续范围。",
              "futurePlan": "根据转牌与所选尺度继续规划。",
              "gtoBaseline": "基线保留三个行动的混合策略。",
              "exploitCondition": \(exploitJSON)
            }
          }]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            StrategyPack.self,
            from: Data(json.utf8)
        )
    }
}
