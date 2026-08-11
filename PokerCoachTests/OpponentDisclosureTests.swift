import SessionSimulation
import StrategyContent
import XCTest
@testable import PokerCoach

/// The opponents' provenance is a second, independent disclosure.
///
/// Strategy content and opponent behaviour are two different claims about two
/// different things, and the app is the only layer that can see both. A screen
/// that showed one and let the other stand unlabelled would leave the user
/// believing the table they are practising against carries whatever authority
/// the strategy content does.
final class OpponentDisclosureTests: XCTestCase {
    func testOpponentBehaviourIsDisclosedAsAFixedHeuristic() {
        let disclosure = OpponentProfileTable.disclosure

        XCTAssertTrue(
            disclosure.contains("不是求解器策略"),
            "对手披露没有否认求解器出身：\(disclosure)"
        )
        XCTAssertTrue(
            disclosure.contains("不代表真实牌手"),
            "对手披露没有否认它代表真人：\(disclosure)"
        )
    }

    /// The scenario requires two independent strings, not one banner reused.
    /// Reuse would be the cheapest implementation and would tell the user the
    /// wrong thing about whichever of the two it was not written for.
    func testOpponentDisclosureIsNotAnyOfTheContentDisclosures() {
        let contentDisclosures = [
            StrategyContentMetadata.developmentDisclosure,
            StrategyContentMetadata.modelAuthoredDisclosure,
            StrategyContentMetadata.unverifiedDisclosure,
            StrategyContentMetadata.retiredDisclosure,
            StrategyContentMetadata.unknownProvenanceDisclosure,
            StrategyContentMetadata.reviewedContentAvailableDisclosure,
            StrategyContentMetadata.reviewedContentUnavailableDisclosure,
        ]

        XCTAssertFalse(
            contentDisclosures.contains(OpponentProfileTable.disclosure),
            "对手披露与某条内容披露是同一条文案"
        )
    }

    /// Present regardless of what content is installed. The two are unrelated:
    /// signing off on a strategy pack says nothing about where the opponents
    /// came from, so reviewed content must not silence the opponent notice.
    func testOpponentDisclosureDoesNotDependOnTheContentReviewStatus() {
        for status in [ReviewStatus.testFixture, .unverifiedDraft, .reviewed, .retired] {
            for origin in [ContentOrigin.solver, .generativeModel, .fixture] {
                _ = StrategyContentMetadata.disclosure(
                    forReviewStatus: status,
                    origin: origin
                )
                XCTAssertFalse(
                    OpponentProfileTable.disclosure.isEmpty,
                    "内容为 \(status)/\(origin) 时对手披露被清空"
                )
            }
        }
    }

    /// The stated tendencies must be the profile's own defined values. A view
    /// that computed them from play would drift from what the user was told
    /// they signed up to practise against.
    func testEveryProfileStatesDistinctDefinedTendencies() {
        let profiles = OpponentProfileTable.profiles
        XCTAssertEqual(profiles.count, 4)

        XCTAssertEqual(Set(profiles.map(\.entryRateBasisPoints)).count, 4)
        XCTAssertEqual(Set(profiles.map(\.aggressionBasisPoints)).count, 4)
        XCTAssertEqual(Set(profiles.map(\.callingTendencyBasisPoints)).count, 4)
        XCTAssertEqual(Set(profiles.map(\.name)).count, 4)
    }

    /// A session record pins itself to the behaviour table that produced it,
    /// so the version has to be something a record can carry and compare.
    func testTheBehaviourTableCarriesAVersion() {
        XCTAssertFalse(OpponentProfileTable.version.isEmpty)
    }
}
