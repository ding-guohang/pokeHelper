import PokerCore
import Testing
@testable import SessionSimulation

/// The four profiles as *stated values*.
///
/// `virtual-opponents` requires the entry rate, aggression and calling tendency
/// shown to the user to be definitions rather than measurements. That is only
/// worth anything if the definitions are also what the opponent plays, so this
/// suite checks both halves: the numbers are what the table says, and the play
/// is what the numbers say.
@Suite("四种可披露的对手档案")
struct OpponentProfileTableTests {
    @Test("四个档案的名称与三项倾向逐字段等于定义")
    func theProfilesAreExactlyTheseValues() {
        // Written out rather than derived, so that changing a profile has to be
        // done twice: once in the table and once here, with the version bump in
        // between. A derived expectation would let a typo through silently.
        let expected: [(OpponentProfileID, String, Int, Int, Int)] = [
            (.rock, "岩石", 800, 2_500, 2_000),
            (.tag, "稳固加注者", 2_400, 6_000, 4_000),
            (.station, "跟注站", 4_400, 500, 8_500),
            (.maniac, "疯子", 6_200, 9_000, 6_000),
        ]

        #expect(OpponentProfileTable.profiles.count == 4)
        #expect(OpponentProfileID.allCases.count == 4)

        for (id, name, entry, aggression, calling) in expected {
            let profile = OpponentProfileTable.profile(id)
            #expect(profile.id == id)
            #expect(profile.name == name)
            #expect(profile.entryRateBasisPoints == entry, "\(id) 的入池率是 \(profile.entryRateBasisPoints)")
            #expect(
                profile.aggressionBasisPoints == aggression,
                "\(id) 的激进度是 \(profile.aggressionBasisPoints)"
            )
            #expect(
                profile.callingTendencyBasisPoints == calling,
                "\(id) 的跟注倾向是 \(profile.callingTendencyBasisPoints)"
            )
            #expect(!profile.tendencySummary.isEmpty)
            #expect(OpponentProfileTable.profiles.contains(profile), "\(id) 不在 profiles 列表里")
        }
    }

    /// The spec asks that the four displayed combinations be pairwise
    /// different. This asserts the stronger thing — every single field is
    /// pairwise different — because a table where two profiles shared an entry
    /// rate would satisfy the letter of the scenario while telling the user two
    /// opponents are looser or tighter than each other when they are not.
    @Test("四个档案两两不同，且每一项倾向都两两不同")
    func noTwoProfilesShareATendency() {
        let profiles = OpponentProfileTable.profiles
        for (index, left) in profiles.enumerated() {
            for right in profiles.dropFirst(index + 1) {
                #expect(left != right)
                #expect(left.id != right.id)
                #expect(left.name != right.name)
                #expect(
                    left.entryRateBasisPoints != right.entryRateBasisPoints,
                    "\(left.id) 与 \(right.id) 的入池率相同"
                )
                #expect(
                    left.aggressionBasisPoints != right.aggressionBasisPoints,
                    "\(left.id) 与 \(right.id) 的激进度相同"
                )
                #expect(
                    left.callingTendencyBasisPoints != right.callingTendencyBasisPoints,
                    "\(left.id) 与 \(right.id) 的跟注倾向相同"
                )
            }
        }
    }

    /// The stated numbers must survive a session. They are `static let`s, so
    /// this cannot fail today — it exists because the scenario is written
    /// against the *displayed* values, and the obvious future implementation of
    /// "show the opponent's tendencies" is one that recomputes them from what
    /// the opponent has done so far. That implementation would pass every other
    /// test in this file.
    @Test("打完 30 手后档案的数值未改变")
    func playingASessionDoesNotChangeTheStatedTendencies() {
        let before = OpponentProfileTable.profiles

        for id in OpponentProfileID.allCases {
            let run = SessionRunner(seed: 42, policy: OpponentProfileTable.policy(id))
                .run(handCount: 30)
            #expect(run.hands.count == 30)
        }

        #expect(OpponentProfileTable.profiles == before)
    }

    @Test("披露文案写明对手是固定启发式而非求解器策略")
    func theDisclosureSaysWhereTheBehaviourComesFrom() {
        let disclosure = OpponentProfileTable.disclosure

        #expect(disclosure.contains("固定启发式"), "披露文案没有说明这是固定启发式：\(disclosure)")
        #expect(disclosure.contains("不是求解器策略"), "披露文案没有否认这是求解器策略：\(disclosure)")

        // The strategy-content disclosures live in the app target and stay
        // there; this only checks that the opponent disclosure is a constant of
        // its own with its own content, which is what lets a session screen
        // show both at once. That they are two separate texts on screen is T7's
        // to assert, in the layer that can see both.
        #expect(!disclosure.isEmpty)
    }

    @Test("行为表版本非空，且黄金夹具与它绑定")
    func theTableCarriesAVersion() {
        #expect(!OpponentProfileTable.version.isEmpty)
        // The binding itself is asserted in OpponentGoldenSequenceTests; this
        // is here so that deleting the constant fails in the file that defines
        // what it is for.
        let golden = OpponentActionGolden.make(profile: .rock, seed: 42, handCount: 1)
        #expect(golden.tableVersion == OpponentProfileTable.version)
    }

    // MARK: - The numbers are what the opponents play

    /// The entry rate is the share of the 1,326 starting combinations the
    /// profile puts money in with, averaged over the six seats.
    ///
    /// Measured through `chooseAction` rather than by reading the threshold, so
    /// this is a claim about the play and not about the arithmetic. The
    /// tolerance is one percentage point: a hand class is up to twelve
    /// combinations wide, so the realised share can only land within about
    /// ninety basis points of any stated figure.
    @Test("实际入池组合比例等于声明的入池率")
    func theStatedEntryRateIsTheRateThatIsPlayed() throws {
        for profile in OpponentProfileTable.profiles {
            var totalOverSeats = 0
            var seatShares: [Int] = []

            for offset in 0 ..< TableRules.seatCount {
                var enteredCombinations = 0
                for handClass in HandClass.all {
                    let action = try action(
                        of: profile,
                        holdingClass: handClass,
                        seatOffsetFromButton: offset
                    )
                    if action != .fold {
                        enteredCombinations += handClass.combinationCount
                    }
                }
                let share = enteredCombinations * 10_000 / PreflopHandRanking.combinationCount
                seatShares.append(share)
                totalOverSeats += share
            }

            let realised = totalOverSeats / TableRules.seatCount
            #expect(
                abs(realised - profile.entryRateBasisPoints) <= 100,
                "\(profile.id) 声明入池率 \(profile.entryRateBasisPoints)，实际 \(realised)，各位置 \(seatShares)"
            )

            // Position has to matter, or the average above would be six copies
            // of one number and the "averaged over the six seats" in the stated
            // definition would be decoration.
            #expect(
                Set(seatShares).count >= 4,
                "\(profile.id) 在六个位置上的入池率只有 \(Set(seatShares).count) 种取值：\(seatShares)"
            )
            #expect(
                seatShares[0] > seatShares[3],
                "\(profile.id) 在按钮位并不比 UTG 打得宽：\(seatShares)"
            )
        }
    }

    /// Looser profiles enter more. Ordering rather than exact values, because
    /// the exact values are the previous test's job.
    @Test("入池率的排序就是实际入池宽度的排序")
    func aLooserStatedEntryRateMeansAWiderRange() throws {
        var realised: [(OpponentProfileID, Int)] = []
        for profile in OpponentProfileTable.profiles {
            var combinations = 0
            for handClass in HandClass.all {
                let action = try action(of: profile, holdingClass: handClass, seatOffsetFromButton: 5)
                if action != .fold {
                    combinations += handClass.combinationCount
                }
            }
            realised.append((profile.id, combinations))
        }

        let byStated = OpponentProfileTable.profiles
            .sorted { $0.entryRateBasisPoints < $1.entryRateBasisPoints }
            .map(\.id)
        let byRealised = realised.sorted { $0.1 < $1.1 }.map(\.0)
        #expect(byStated == byRealised, "声明的入池率排序 \(byStated) 与实际 \(byRealised) 不一致")
        #expect(Set(realised.map(\.1)).count == 4, "四个档案的实际入池宽度有重复：\(realised)")
    }

    /// The aggression figure orders how often a profile bets rather than
    /// checks, and the calling tendency orders how often it continues rather
    /// than folds.
    ///
    /// Swept over many generator seeds at fixed spots, because a single roll
    /// says nothing about a frequency. The two spots are held constant across
    /// profiles so the only difference is the table.
    @Test("激进度与跟注倾向的排序就是实际频率的排序")
    func theStatedTendenciesOrderTheRealisedFrequencies() throws {
        let trials = 400
        let unopened = try OpponentSpotBuilder.postflopUnopened()
        let facingBet = try OpponentSpotBuilder.postflopFacingBet()

        var bets: [(OpponentProfileID, Int)] = []
        var continues: [(OpponentProfileID, Int)] = []

        for profile in OpponentProfileTable.profiles {
            let policy = OpponentActionPolicy(profile: profile)
            var betCount = 0
            var continueCount = 0
            for trial in 0 ..< trials {
                var rng = SplitMix64(seed: SplitMix64.derivedSeed(base: 1_000, label: UInt64(trial)))
                if policy.chooseAction(at: unopened, using: &rng) != .check {
                    betCount += 1
                }
                var otherRng = SplitMix64(
                    seed: SplitMix64.derivedSeed(base: 2_000, label: UInt64(trial))
                )
                if policy.chooseAction(at: facingBet, using: &otherRng) != .fold {
                    continueCount += 1
                }
            }
            bets.append((profile.id, betCount))
            continues.append((profile.id, continueCount))
        }

        // Anti-vacuity: a policy that never bet and never continued would order
        // perfectly by being all zeroes.
        #expect(bets.allSatisfy { $0.1 > 0 }, "有档案在 \(trials) 次里一次都没下注：\(bets)")
        #expect(bets.contains { $0.1 < trials }, "所有档案每一次都下注：\(bets)")
        #expect(continues.allSatisfy { $0.1 > 0 }, "有档案在 \(trials) 次里一次都没跟：\(continues)")
        #expect(continues.contains { $0.1 < trials }, "所有档案每一次都跟：\(continues)")

        let byStatedAggression = OpponentProfileTable.profiles
            .sorted { $0.aggressionBasisPoints < $1.aggressionBasisPoints }
            .map(\.id)
        #expect(
            bets.sorted { $0.1 < $1.1 }.map(\.0) == byStatedAggression,
            "下注频率排序 \(bets) 与声明的激进度排序 \(byStatedAggression) 不一致"
        )

        let byStatedCalling = OpponentProfileTable.profiles
            .sorted { $0.callingTendencyBasisPoints < $1.callingTendencyBasisPoints }
            .map(\.id)
        #expect(
            continues.sorted { $0.1 < $1.1 }.map(\.0) == byStatedCalling,
            "继续频率排序 \(continues) 与声明的跟注倾向排序 \(byStatedCalling) 不一致"
        )
    }

    /// A preflop spot facing the big blind, from a given seat, holding a given
    /// class. The suits are chosen to match the class rather than the other way
    /// round.
    private func action(
        of profile: OpponentProfile,
        holdingClass handClass: HandClass,
        seatOffsetFromButton offset: Int
    ) throws -> DecisionAction {
        let decision = try OpponentSpotBuilder.preflopFacingBlind(
            handClass: handClass,
            seatOffsetFromButton: offset
        )
        // Whether a hand is entered at all is not a roll, so the generator seed
        // cannot change the answer; it still has to be supplied, and holding it
        // constant keeps that visible.
        var rng = SplitMix64(seed: 7)
        return OpponentActionPolicy(profile: profile).chooseAction(at: decision, using: &rng)
    }
}
