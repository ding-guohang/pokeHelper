import Testing
@testable import SessionSimulation

@Suite("确定性随机源")
struct SplitMix64Tests {
    /// A known-answer test, not a smoke test.
    ///
    /// These are the published SplitMix64 outputs for seed 0. Pinning them is
    /// the only thing standing between a tidy-up of the mixing function and
    /// every committed session fixture silently dealing different cards — the
    /// kind of change that looks correct in review because the algorithm is
    /// still "a SplitMix64".
    @Test("seed 0 的前四个输出等于 SplitMix64 的公开值")
    func matchesThePublishedReferenceVectors() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
        #expect(rng.next() == 0xF88B_B8A8_724C_81EC)
    }

    @Test("seed 42 的前四个输出等于参考实现")
    func matchesTheReferenceVectorsForTheSeedTheSpecNames() {
        var rng = SplitMix64(seed: 42)
        #expect(rng.next() == 0xBDD7_3226_2FEB_6E95)
        #expect(rng.next() == 0x28EF_E333_B266_F103)
        #expect(rng.next() == 0x4752_6757_130F_9F52)
        #expect(rng.next() == 0x581C_E1FF_0E4A_E394)
    }

    @Test("相同种子的两个实例产生相同序列")
    func twoGeneratorsWithTheSameSeedAgree() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        let left = (0 ..< 64).map { _ in first.next() }
        let right = (0 ..< 64).map { _ in second.next() }

        #expect(left == right)
        // Without this the assertion above would also hold for a generator that
        // returned zero forever.
        #expect(Set(left).count == 64, "序列里有重复值，随机源塌了")
    }

    @Test("不同种子产生不同序列")
    func differentSeedsDiverge() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 43)
        let left = (0 ..< 64).map { _ in first.next() }
        let right = (0 ..< 64).map { _ in second.next() }

        #expect(left != right)
        #expect(zip(left, right).count { $0 != $1 } == 64, "两条序列有位置相同")
    }

    @Test("nextBelow 落在区间内且覆盖每个值")
    func boundedDrawsStayInRangeAndReachEveryValue() {
        var rng = SplitMix64(seed: 42)
        var counts = [Int](repeating: 0, count: 52)

        for _ in 0 ..< 52_000 {
            let value = Int(rng.nextBelow(52))
            #expect(value >= 0 && value < 52, "\(value) 越界")
            counts[value] += 1
        }

        // Upper bounds alone are the classic empty assertion: `value < 52` is
        // satisfied by a generator that always returns 0. The coverage check is
        // what rules that out.
        #expect(counts.allSatisfy { $0 > 0 }, "有些值从未出现：\(counts)")
        // 52,000 draws over 52 values averages 1,000 each. A generator with a
        // gross bias — a stuck bit, a wrong shift — lands far outside this band;
        // the bounds are loose enough that ordinary sampling noise cannot.
        #expect(counts.allSatisfy { $0 > 700 && $0 < 1_300 }, "分布明显偏斜：\(counts)")
    }

    @Test("nextBelow(1) 恒为 0")
    func aSingleOutcomeIsAlwaysThatOutcome() {
        var rng = SplitMix64(seed: 42)
        for _ in 0 ..< 100 {
            #expect(rng.nextBelow(1) == 0)
        }
    }

    /// The deck stream and the action stream are derived from the same session
    /// seed. If the derivation collapsed them, the cards about to come off the
    /// deck would determine what the opponents did with them.
    @Test("不同 label 派生出互不相同的流")
    func derivedStreamsAreIndependent() {
        let base: UInt64 = 42
        let seeds = (0 ..< 32).map { SplitMix64.derivedSeed(base: base, label: UInt64($0)) }

        #expect(Set(seeds).count == 32, "派生种子发生碰撞")
        #expect(!seeds.contains(base), "某个派生种子等于基种子")

        var first = SplitMix64(seed: seeds[1])
        var second = SplitMix64(seed: seeds[2])
        #expect((0 ..< 16).map { _ in first.next() } != (0 ..< 16).map { _ in second.next() })
    }

    @Test("相同 base 与 label 派生出相同种子")
    func derivationIsAFunctionOfItsInputs() {
        #expect(
            SplitMix64.derivedSeed(base: 42, label: 7)
                == SplitMix64.derivedSeed(base: 42, label: 7)
        )
        #expect(
            SplitMix64.derivedSeed(base: 42, label: 7)
                != SplitMix64.derivedSeed(base: 43, label: 7)
        )
    }
}
