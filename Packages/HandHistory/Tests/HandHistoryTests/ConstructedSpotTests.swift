import Foundation
import PokerCore
import Testing

@testable import HandHistory

@Suite("手动构造 spot")
struct ConstructedSpotTests {
    /// spot 甲: BTN, A5s, unopened, 100BB deep.
    private static func spotJia() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 0,
            holeCardCodes: ["Ah", "5h"],
            facing: FacingAction(priorRaiseCount: 0),
            effectiveStackCentiBB: 10_000,
            action: .raise(to: BBAmount(centiBB: 300))
        )
    }

    /// spot 乙: CO, 72o, facing a single raise, 16BB short.
    private static func spotYi() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 5,
            holeCardCodes: ["7c", "2d"],
            facing: FacingAction(priorRaiseCount: 1),
            effectiveStackCentiBB: 1_600,
            action: .fold
        )
    }

    // T1 covers:1 — two distinct legal spots produce signatures whose four
    // components each equal their computed reference, differ from each other on
    // all four, and are byte-for-byte reproducible.
    @Test("两个合法构造签名各异且确定")
    func twoLegalSpotsHaveDistinctDeterministicSignatures() throws {
        let jia = try Self.spotJia()
        let yi = try Self.spotYi()

        let jiaSig = jia.signature()
        let yiSig = yi.signature()

        // Each component equals the reference computed straight from the inputs.
        #expect(jiaSig.street == .preflop)
        #expect(jiaSig.heroSeatOffsetFromButton == 0)
        #expect(jiaSig.handClass == HandClass(Card(code: "Ah")!, Card(code: "5h")!))
        #expect(jiaSig.facing == FacingAction(priorRaiseCount: 0))
        #expect(jiaSig.stackBucket == StackBucket(effectiveStack: BBAmount(centiBB: 10_000)))

        #expect(yiSig.street == .preflop)
        #expect(yiSig.heroSeatOffsetFromButton == 5)
        #expect(yiSig.handClass == HandClass(Card(code: "7c")!, Card(code: "2d")!))
        #expect(yiSig.facing == FacingAction(priorRaiseCount: 1))
        #expect(yiSig.stackBucket == StackBucket(effectiveStack: BBAmount(centiBB: 1_600)))

        // The two spots differ on every one of the four keyed fields, so a
        // signature() that ignored its inputs could not pass all four.
        #expect(jiaSig.heroSeatOffsetFromButton != yiSig.heroSeatOffsetFromButton)
        #expect(jiaSig.handClass != yiSig.handClass)
        #expect(jiaSig.facing != yiSig.facing)
        #expect(jiaSig.stackBucket != yiSig.stackBucket)

        // Building 甲 twice is deterministic: identical signatures and identical
        // canonical bytes, no clock or randomness in the path.
        let jiaAgain = try Self.spotJia()
        #expect(jiaAgain.signature() == jiaSig)
        #expect(try jiaAgain.canonicalJSON() == jia.canonicalJSON())
        #expect(jiaAgain.identity == jia.identity)
    }

    // T1 covers:2 — each illegal build throws the one error its input earns, and
    // the four errors are mutually distinguishable.
    @Test("四种非法各因被拒且错误互不相等")
    func fourIllegalBuildsThrowFourDistinctErrors() throws {
        func errorFrom(
            offset: Int = 0,
            codes: [String] = ["Ah", "5h"],
            stack: Int = 10_000
        ) -> ConstructedSpotError? {
            do {
                _ = try ConstructedSpot(
                    heroSeatOffsetFromButton: offset,
                    holeCardCodes: codes,
                    facing: FacingAction(priorRaiseCount: 0),
                    effectiveStackCentiBB: stack,
                    action: .fold
                )
                return nil
            } catch let error as ConstructedSpotError {
                return error
            } catch {
                return nil
            }
        }

        let duplicate = errorFrom(codes: ["Ah", "Ah"])
        let unparseable = errorFrom(codes: ["Zx", "5h"])
        let seat = errorFrom(offset: 6)
        let stack = errorFrom(stack: 0)

        #expect(duplicate == .duplicateCards)
        #expect(unparseable == .unparseableCard("Zx"))
        #expect(seat == .seatOutOfRange)
        #expect(stack == .nonPositiveStack)

        // The four are pairwise different, so asserting one rules the others out.
        let all: [ConstructedSpotError] = [
            .duplicateCards,
            .unparseableCard("Zx"),
            .seatOutOfRange,
            .nonPositiveStack,
        ]
        for i in all.indices {
            for j in all.indices where j != i {
                #expect(all[i] != all[j])
            }
        }
    }
}
