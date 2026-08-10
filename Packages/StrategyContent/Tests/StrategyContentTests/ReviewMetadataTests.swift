import Foundation
import Testing
@testable import StrategyContent

@Suite("审核元数据")
struct ReviewMetadataTests {
    private let reviewTime = Date(timeIntervalSince1970: 1_786_000_000)

    // GIVEN review status 为 reviewed 且 reviewed-at 为空
    // WHEN validator 校验
    // THEN 策略包被拒绝
    @Test("已审核内容缺少审核时间")
    func rejectsReviewedPackWithoutReviewTime() throws {
        let pack = try StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: "Meow Ding",
            reviewedAt: nil
        )

        #expect(throws: StrategyPackValidationError.missingReviewedAt) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // GIVEN review status 为 reviewed、reviewed-at 非空、但 reviewed-by 为空
    // WHEN validator 校验
    // THEN 策略包被拒绝，且错误指明缺失的是审核人
    @Test("已审核内容缺少审核人")
    func rejectsReviewedPackWithoutReviewer() throws {
        let pack = try StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: nil,
            reviewedAt: reviewTime
        )

        #expect(throws: StrategyPackValidationError.missingReviewedBy) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // A blank reviewer is the same lie as an absent one, and is what an
    // automated pipeline would produce if it filled the field to get past the
    // gate.
    @Test("审核人为空白字符串同样被拒绝")
    func rejectsReviewedPackWithBlankReviewer() throws {
        let pack = try StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: "   ",
            reviewedAt: reviewTime
        )

        #expect(throws: StrategyPackValidationError.missingReviewedBy) {
            try StrategyPackValidator().validate(pack)
        }
    }

    // GIVEN reviewed-by 与 reviewed-at 均非空且场景合法
    // WHEN validator 校验
    // THEN 策略包被接受，审核人与审核时间可读
    @Test("已审核内容元数据齐备")
    func acceptsFullyAttributedReviewedPack() throws {
        let pack = try StrategyPackFixture.pack(
            reviewStatus: .reviewed,
            reviewedBy: "Meow Ding",
            reviewedAt: reviewTime
        )

        try StrategyPackValidator().validate(pack)

        #expect(pack.manifest.reviewedBy == "Meow Ding")
        #expect(pack.manifest.reviewedAt == reviewTime)
    }

    // unverifiedDraft 不要求审核元数据——否则它与 reviewed 就没有区别了。
    @Test("未审核草稿不要求审核元数据")
    func acceptsUnverifiedDraftWithoutReviewMetadata() throws {
        let pack = try StrategyPackFixture.pack(
            reviewStatus: .unverifiedDraft,
            reviewedBy: nil,
            reviewedAt: nil
        )

        try StrategyPackValidator().validate(pack)

        #expect(pack.manifest.reviewStatus == .unverifiedDraft)
    }

    // The status has to survive a JSON round trip: it reaches the app as
    // decoded content, not as an in-memory value.
    @Test("未审核状态可编解码")
    func roundTripsTheUnverifiedDraftStatus() throws {
        let encoded = try JSONEncoder().encode(ReviewStatus.unverifiedDraft)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"unverifiedDraft\"")
        #expect(try JSONDecoder().decode(ReviewStatus.self, from: encoded) == .unverifiedDraft)
    }
}
