import PokerCore
import Testing
@testable import SessionSimulation

/// The twenty fixed spots, and what the four profiles do on them.
///
/// The spots live in `Tests/Fixtures/opponent-spots-20.json` and are inputs,
/// not expectations — nothing in this suite compares an action against a
/// recorded one. What is asserted is a relation *between* the profiles, so the
/// suite fails if the four ever collapse into fewer than four distinguishable
/// opponents, whatever any one of them happens to do.
@Suite("四种档案在同一局面下行为可区分")
struct OpponentDistinguishabilityTests {
    /// Before anything is asserted about the twenty spots, they have to be
    /// twenty real spots. Every relation below is over a loop, and a loop over
    /// an empty or malformed fixture is silent.
    @Test("夹具确实是 20 个互不相同的合法局面")
    func theFixtureIsTwentyUsableSpots() throws {
        let spotSet = try OpponentFixtures.loadSpotSet()
        let spots = spotSet.spots

        #expect(spots.count == 20, "夹具里有 \(spots.count) 个局面")
        #expect(!spotSet.provenance.isEmpty, "夹具没有说明这 20 个局面从哪来")
        #expect(Set(spots.map(\.id)) == Set(0 ..< 20), "局面编号不是 0…19")
        #expect(Set(spots.map(\.rngSeed)).count == 20, "有局面共用了随机种子")

        var streets: Set<Street> = []
        var facings: Set<FacingAction> = []
        var handClasses: Set<HandClass> = []
        var facedCount = 0

        for spot in spots {
            let decision = try spot.decisionPoint()
            #expect(!decision.legalActions.isEmpty, "第 \(spot.id) 个局面没有合法行动")
            #expect(
                decision.context.amountToCall <= decision.context.effectiveStack,
                "第 \(spot.id) 个局面的须跟注额超过有效筹码"
            )
            streets.insert(decision.street)
            facings.insert(decision.facing)
            handClasses.insert(decision.handClass)
            if decision.context.amountToCall.centiBB > 0 {
                facedCount += 1
            }
        }

        // Coverage, so that "twenty spots" is not twenty copies of one spot.
        #expect(streets.count >= 3, "20 个局面只覆盖了 \(streets.count) 条街道：\(streets)")
        #expect(facings.count >= 2, "20 个局面只覆盖了 \(facings.count) 种面对情形")
        #expect(handClasses.count >= 15, "20 个局面只用了 \(handClasses.count) 种手牌类别")
        #expect(facedCount >= 5, "只有 \(facedCount) 个局面面对下注")
        #expect(20 - facedCount >= 5, "只有 \(20 - facedCount) 个局面未面对下注")
    }

    @Test("四种档案在每个局面给出的行动都在该局面的合法集合内，且每种档案都弃过、跟过、也进攻过")
    func everyProfileStaysInsideTheLegalSetAndUsesAllOfIt() throws {
        let spots = try OpponentFixtures.loadSpotSet().spots
        var checked = 0
        var folds: [OpponentProfileID: Int] = [:]
        var passives: [OpponentProfileID: Int] = [:]
        var aggressions: [OpponentProfileID: Int] = [:]

        for spot in spots {
            let decision = try spot.decisionPoint()
            for profile in OpponentProfileTable.profiles {
                // Many generator seeds per spot: the action depends on the
                // roll, and one roll only exercises one branch of the table.
                for trial in 0 ..< 50 {
                    var rng = SplitMix64(
                        seed: SplitMix64.derivedSeed(base: spot.rngSeed, label: UInt64(trial))
                    )
                    let action = OpponentActionPolicy(profile: profile)
                        .chooseAction(at: decision, using: &rng)
                    let complaint = "\(profile.id) 在第 \(spot.id) 个局面返回了非法行动 \(action)，"
                        + "合法集合是 \(decision.orderedLegalActions)"
                    #expect(
                        decision.legalActions.contains(action),
                        Comment(rawValue: complaint)
                    )
                    switch action {
                    case .fold: folds[profile.id, default: 0] += 1
                    case .check, .call: passives[profile.id, default: 0] += 1
                    case .bet, .raise, .allIn: aggressions[profile.id, default: 0] += 1
                    }
                    checked += 1
                }
            }
        }

        #expect(checked == 20 * 4 * 50, "只检查了 \(checked) 次求解")

        // The spec asks that no profile give the same action on all twenty
        // spots. On a fixture that mixes spots facing a bet with spots facing
        // none, that is *implied by legality* — no single action is legal
        // everywhere — so it is not worth asserting on its own. This is the
        // claim it was reaching for: each of the four actually uses the three
        // things a poker player can do, rather than being a fold button with a
        // name.
        for profile in OpponentProfileTable.profiles {
            #expect((folds[profile.id] ?? 0) > 0, "\(profile.id) 在 1000 次求解里一次都没弃牌")
            #expect(
                (passives[profile.id] ?? 0) > 0,
                "\(profile.id) 在 1000 次求解里一次都没过牌或跟注"
            )
            #expect(
                (aggressions[profile.id] ?? 0) > 0,
                "\(profile.id) 在 1000 次求解里一次都没下注或加注"
            )
        }
    }

    @Test("任意两种档案之间至少在 5 个局面上行动不同")
    func theFourProfilesAreDistinguishable() throws {
        let spots = try OpponentFixtures.loadSpotSet().spots
        #expect(spots.count == 20)

        var rows: [(OpponentProfileID, [String])] = []
        for profile in OpponentProfileTable.profiles {
            var row: [String] = []
            for spot in spots {
                var rng = SplitMix64(seed: spot.rngSeed)
                let action = OpponentActionPolicy(profile: profile)
                    .chooseAction(at: try spot.decisionPoint(), using: &rng)
                row.append(SessionTranscript.describe(action))
            }
            rows.append((profile.id, row))
        }

        // The whole matrix in the failure message: knowing that two profiles
        // agreed four times is useless without seeing where.
        let matrix = rows
            .map { "\($0.0.rawValue): \($0.1.joined(separator: " "))" }
            .joined(separator: "\n")

        for (index, left) in rows.enumerated() {
            for right in rows.dropFirst(index + 1) {
                let differing = zip(left.1, right.1).count { $0 != $1 }
                #expect(
                    differing >= 5,
                    "\(left.0) 与 \(right.0) 只在 \(differing) 个局面上不同\n\(matrix)"
                )
            }
        }
    }

    /// The spec's short-stack scenario, built exactly as written: 3BB behind,
    /// facing a 5BB bet the state machine has already capped to 3BB.
    @Test("短码对手不会超额下注，且四种档案里既有弃牌也有跟注")
    func aShortStackedOpponentEitherFoldsOrShoves() throws {
        let handClass = try #require(HandClass(notation: "KJo"))
        let decision = try OpponentSpotBuilder.shortStackFacingShove(handClass: handClass)
        let call = DecisionAction.call(to: BBAmount(centiBB: 300))

        // The premise of the scenario, not an aside: if the legal set held a
        // separate all-in the rest of this test would be about a different
        // spot than the one the spec describes.
        #expect(
            decision.legalActions == [.fold, call],
            "合法集合是 \(decision.orderedLegalActions)，不是恰好的 fold 与 call"
        )

        var actions: [OpponentProfileID: DecisionAction] = [:]
        for profile in OpponentProfileTable.profiles {
            var rng = SplitMix64(seed: 99)
            let action = OpponentActionPolicy(profile: profile).chooseAction(at: decision, using: &rng)
            #expect(
                action == .fold || action == call,
                "\(profile.id) 在 3BB 短码下返回了 \(action)"
            )
            actions[profile.id] = action
        }

        #expect(
            actions.values.contains(.fold),
            "四种档案没有一种弃牌：\(actions.map { "\($0.key)=\($0.value)" }.sorted())"
        )
        #expect(
            actions.values.contains(call),
            "四种档案没有一种跟注：\(actions.map { "\($0.key)=\($0.value)" }.sorted())"
        )
    }

    /// The same spot swept over all 169 hand classes and six seats.
    ///
    /// The scenario above is satisfied by a table that folds every hand except
    /// one contrived class. This says each of the four both folds somewhere and
    /// calls somewhere at this stack depth, and that nothing outside the legal
    /// pair is ever returned — 169 × 6 × 4 spots, not one.
    @Test("短码全下决策在全部 169 个手牌类别上都合法，且每个档案既弃过牌也跟过注")
    func theShortStackRuleHoldsAcrossEveryHoldingAndSeat() throws {
        let call = DecisionAction.call(to: BBAmount(centiBB: 300))
        var folds: [OpponentProfileID: Int] = [:]
        var calls: [OpponentProfileID: Int] = [:]
        var checked = 0

        for handClass in HandClass.all {
            for offset in 0 ..< TableRules.seatCount {
                let decision = try OpponentSpotBuilder.shortStackFacingShove(
                    handClass: handClass,
                    seatOffsetFromButton: offset
                )
                for profile in OpponentProfileTable.profiles {
                    var rng = SplitMix64(seed: UInt64(offset) &* 1_000 &+ 17)
                    let action = OpponentActionPolicy(profile: profile)
                        .chooseAction(at: decision, using: &rng)
                    switch action {
                    case .fold: folds[profile.id, default: 0] += 1
                    case call: calls[profile.id, default: 0] += 1
                    default:
                        Issue.record(
                            Comment(rawValue: "\(profile.id) 拿 \(handClass) 在 offset \(offset) 返回了 \(action)")
                        )
                    }
                    checked += 1
                }
            }
        }

        #expect(checked == 169 * TableRules.seatCount * 4, "只检查了 \(checked) 次")
        for profile in OpponentProfileTable.profiles {
            #expect(
                (folds[profile.id] ?? 0) > 0,
                "\(profile.id) 在 169 × 6 个短码局面上一次都没弃牌"
            )
            #expect(
                (calls[profile.id] ?? 0) > 0,
                "\(profile.id) 在 169 × 6 个短码局面上一次都没跟注"
            )
        }
    }
}
