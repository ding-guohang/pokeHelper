import Foundation
import Testing
@testable import PokerCore

@Suite("局面签名")
struct SpotSignatureTests {
    /// Boundaries asserted one value either side, not "roughly in range". A
    /// bucket edge that is off by one centi-BB makes equivalence wrong for
    /// exactly the hands sitting on it, and nothing else would notice.
    @Test("分桶边界值归属明确")
    func placesEveryBoundaryValueExplicitly() {
        let cases: [(Int, StackBucket)] = [
            (0, .short),
            (1_999, .short),
            (2_000, .medium),
            (5_999, .medium),
            (6_000, .deep),
            (11_999, .deep),
            (12_000, .veryDeep),
            (100_000, .veryDeep),
        ]

        for (centiBB, expected) in cases {
            #expect(
                StackBucket(effectiveStack: BBAmount(centiBB: centiBB)) == expected,
                "\(centiBB) centi-BB 应落在 \(expected)"
            )
        }
    }

    @Test("四个分桶都被某个筹码量命中")
    func everyBucketIsReachable() {
        let reached = Set(
            [1_000, 3_000, 8_000, 20_000].map {
                StackBucket(effectiveStack: BBAmount(centiBB: $0))
            }
        )
        #expect(reached == Set(StackBucket.allCases))
    }

    /// Five separate assertions rather than one loop over "some component
    /// differs". A signature that ignored, say, `facing` would still fail a
    /// combined assertion for the other four and could read as passing.
    @Test("五个分量任一不同则签名不同")
    func everyComponentParticipatesInEquality() throws {
        let base = Self.signature()

        #expect(base != Self.signature(street: .flop), "street 未参与比较")
        #expect(base != Self.signature(heroSeatOffsetFromButton: 3), "位置未参与比较")
        #expect(
            base != Self.signature(handClass: try #require(HandClass(notation: "72o"))),
            "手牌类别未参与比较"
        )
        #expect(base != Self.signature(facing: .reraise), "面对情形未参与比较")
        #expect(base != Self.signature(stackBucket: .short), "筹码分桶未参与比较")
    }

    @Test("全部分量相同则签名相等且哈希一致")
    func equalComponentsProduceEqualSignatures() {
        #expect(Self.signature() == Self.signature())
        #expect(Set([Self.signature(), Self.signature()]).count == 1)
    }

    @Test("街道由公共牌张数推出，非法张数被拒绝")
    func derivesStreetFromBoardSize() {
        #expect(Street(boardCardCount: 0) == .preflop)
        #expect(Street(boardCardCount: 3) == .flop)
        #expect(Street(boardCardCount: 4) == .turn)
        #expect(Street(boardCardCount: 5) == .river)

        for illegal in [1, 2, 6, 7, -1] {
            #expect(Street(boardCardCount: illegal) == nil, "\(illegal) 张公共牌不该成立")
        }

        for street in Street.allCases {
            #expect(Street(boardCardCount: street.boardCardCount) == street)
        }
    }

    /// Beyond a re-raise everything collapses, because no content distinguishes
    /// a 4-bet from a 5-bet. Asserted explicitly so the collapse is a decision
    /// on record rather than an accident of the switch.
    @Test("面对情形按加注次数归类，超过再加注一律归为再加注")
    func collapsesEverythingBeyondAReraise() {
        #expect(FacingAction(priorRaiseCount: 0) == .unopened)
        #expect(FacingAction(priorRaiseCount: 1) == .singleRaise)
        #expect(FacingAction(priorRaiseCount: 2) == .reraise)
        #expect(FacingAction(priorRaiseCount: 3) == .reraise)
        #expect(FacingAction(priorRaiseCount: 9) == .reraise)
    }

    /// The signature is persisted inside session records, so a round trip that
    /// silently loses a component would make replayed sessions stop matching
    /// content they matched when they were played.
    @Test("签名可编解码往返")
    func roundTripsThroughCoding() throws {
        let original = Self.signature()
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SpotSignature.self, from: data) == original)

        // The hand class must survive as its notation, not as a struct dump:
        // that is the form the content pack already uses.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"AKs\""), "手牌类别没有以 169 格记号编码：\(text)")
    }

    @Test("非法手牌记号在解码时被拒绝")
    func rejectsAMalformedHandClassOnDecode() throws {
        let data = try #require(#"{"street":"preflop","heroSeatOffsetFromButton":0,"handClass":"KAs","facing":"unopened","stackBucket":"deep"}"#.data(using: .utf8))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SpotSignature.self, from: data)
        }
    }

    private static func signature(
        street: Street = .preflop,
        heroSeatOffsetFromButton: Int = 0,
        handClass: HandClass = HandClass(notation: "AKs")!,
        facing: FacingAction = .unopened,
        stackBucket: StackBucket = .deep
    ) -> SpotSignature {
        SpotSignature(
            street: street,
            heroSeatOffsetFromButton: heroSeatOffsetFromButton,
            handClass: handClass,
            facing: facing,
            stackBucket: stackBucket
        )
    }
}
