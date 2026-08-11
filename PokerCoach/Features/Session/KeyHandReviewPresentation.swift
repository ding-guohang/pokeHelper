import PokerCore
import SessionSimulation
import StrategyContent

/// One action inside a street replay.
struct KeyHandActionLine: Identifiable, Equatable {
    /// Street plus position within it, so two identical actions on the same
    /// street stay distinguishable to `ForEach` and to a UI test.
    let id: String
    let actorLabel: String
    let actionTitle: String
    let potAfterText: String
    let isHero: Bool
}

/// One street of a key hand as the review screen shows it.
///
/// The three numbers a street carries are the three the spec names, and each
/// one is per-street rather than per-hand:
///
/// - `board` holds the cards that were out **during** this street: none
///   preflop, three on the flop, four on the turn, five on the river. A screen
///   that showed the final board on every street would satisfy "the user can
///   look through the streets" and teach the hand backwards.
/// - `potAtEnd` is the pot when this street's betting finished, not the final
///   pot.
/// - `actions` holds only what happened on this street.
struct KeyHandStreet: Identifiable, Equatable {
    let street: Street
    let board: [Card]
    let potAtEnd: BBAmount
    let actions: [KeyHandActionLine]

    var id: String { street.rawValue }

    var title: String {
        switch street {
        case .preflop: "翻前"
        case .flop: "翻牌"
        case .turn: "转牌"
        case .river: "河牌"
        }
    }
}

/// One row of the content comparison: what the installed scenario does with
/// this spot, and whether it is what the hero did.
struct KeyHandComparisonRow: Identifiable, Equatable {
    let id: String
    let actionTitle: String
    let frequencyText: String
    let evText: String
    /// Whether the hero's action at the table was this one.
    ///
    /// Matched on the *kind* of action — fold, call, or put money in — and not
    /// on the amount. A range chart names the decision and not the sizing;
    /// `RangeBaseline.actionKey` says so, and it is the same rule the weight
    /// lookup uses. Comparing exact amounts would mark nothing, ever: the
    /// scenario opens to 2.5BB and the session's state machine offered 2.17BB,
    /// so a user who raised would be told the content's raise row was somebody
    /// else's line.
    let isHeroAction: Bool
}

/// The installed content's answer to a spot the hero played, placed beside what
/// they actually did.
///
/// ## This is a comparison and not a grade, structurally
///
/// There is no EV loss here, no score and no quality band, and their absence is
/// not an oversight to be filled in later. Grading requires the action and the
/// confidence submitted together — `explainable-decision-training` says so —
/// and a session asks for neither: the hero played the hand, they did not
/// answer a question. A number that looked like a score would be a grade
/// awarded for a submission that never happened, and it would be attached to a
/// hand the ability profile deliberately knows nothing about.
///
/// What the user can do with this is replay the spot as training, which does
/// ask for a confidence and does produce an event. That entry point is offered
/// only where a comparison exists, because it is the same condition: a spot
/// installed content covers.
struct KeyHandComparison: Equatable {
    /// Shown verbatim on the screen. Written as a sentence rather than a badge
    /// because "对照" alone would read as a milder word for the same thing.
    static let notice = "这是与已安装内容的对照，不是对这手牌的评分。"

    /// The label on the button that routes this spot into ordinary training.
    static let replayTitle = "以训练模式重打"

    let scenarioID: String
    let scenarioTitle: String

    /// The spot itself: seat, aggression faced, hand class. Stated so the user
    /// can see *why* this scenario is the one being compared against.
    let spotSummary: String

    /// What the hero did at the table.
    let heroActionTitle: String

    /// What the covering scenario's range table gives that action for the
    /// hero's hand class, or `nil` when the action has no name in a range
    /// table's vocabulary.
    let heroActionWeightText: String?

    /// The scenario's own frequencies and EVs, in the pack's order.
    let rows: [KeyHandComparisonRow]
}

/// A key hand, prepared for the review screen.
struct KeyHandReview: Identifiable, Equatable {
    let handIndex: Int
    let reason: KeyHandReason
    let heroCards: [Card]
    let streets: [KeyHandStreet]

    /// Absent when installed content does not cover this hand's preflop spot.
    ///
    /// Absent means the screen shows the street replay and nothing else — no
    /// comparison, and no way into training. Inventing either would mean
    /// putting a curated range in front of a spot it was not written for.
    let comparison: KeyHandComparison?

    var id: Int { handIndex }

    /// The scenario a replay would train, or nothing at all.
    var replayScenarioID: String? { comparison?.scenarioID }

    var reasonText: String {
        switch reason {
        case .deviation: "与内容范围不一致"
        case .allIn: "有人全下"
        case .bigSwing: "筹码波动大"
        case .bigPot: "本局大底池"
        }
    }
}

/// Turns a finished session into the hands the review screen opens with.
///
/// Presentation only: it selects nothing and scores nothing. Which hands are
/// key is `KeyHandSelection`'s answer, and whether content covers a spot is
/// `SessionContentMatcher`'s. This assembles what those two already decided
/// into rows, streets and strings.
struct KeyHandReviewBuilder {
    private let matcher: SessionContentMatcher
    private let scenariosByID: [String: DecisionScenario]

    init(scenarios: [DecisionScenario]) {
        matcher = SessionContentMatcher(scenarios: scenarios)
        scenariosByID = Dictionary(scenarios.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func reviews(
        from summary: SessionRunSummary,
        seating: SeatAssignment
    ) -> [KeyHandReview] {
        let handsByIndex = Dictionary(
            summary.hands.map { ($0.handIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return summary.keyHands.compactMap { keyHand in
            guard let hand = handsByIndex[keyHand.handIndex] else {
                return nil
            }
            return KeyHandReview(
                handIndex: hand.handIndex,
                reason: keyHand.reason,
                heroCards: hand.holeCards[TableRules.heroSeat],
                streets: Self.streets(of: hand, seating: seating),
                comparison: comparison(for: hand)
            )
        }
    }

    // MARK: - Street replay

    /// The streets this hand actually reached, each carrying only its own
    /// board, pot and actions.
    ///
    /// A hand that ended preflop has one street, not four showing the same
    /// thing. The pot of a street with no betting on it — everyone was already
    /// all in — is the pot carried in from the street before, which is the
    /// truth about that street rather than a gap.
    static func streets(
        of hand: SessionHandRecord,
        seating: SeatAssignment
    ) -> [KeyHandStreet] {
        let reached = hand.result.streetReached
        var potSoFar = blindsPosted(in: hand)
        var streets: [KeyHandStreet] = []

        for street in Street.allCases
        where street.boardCardCount <= reached.boardCardCount {
            let actions = hand.actions.filter { $0.street == street }
            if let last = actions.last {
                potSoFar = last.potAfter
            }
            streets.append(
                KeyHandStreet(
                    street: street,
                    board: Array(hand.board.prefix(street.boardCardCount)),
                    potAtEnd: potSoFar,
                    actions: actions.enumerated().map { offset, recorded in
                        KeyHandActionLine(
                            id: "\(street.rawValue)-\(offset)",
                            actorLabel: actorLabel(
                                seat: recorded.seat,
                                buttonSeat: hand.buttonSeat,
                                seating: seating
                            ),
                            actionTitle: recorded.action.displayTitle,
                            potAfterText: recorded.potAfter.displayText,
                            isHero: recorded.seat == TableRules.heroSeat
                        )
                    }
                )
            )
        }

        return streets
    }

    /// The blinds that were actually posted.
    ///
    /// Computed rather than assumed to be 1.5BB: a seat shorter than its blind
    /// posts what it has. This is the pot before the first logged action, and
    /// blind posts are not logged as actions — so without it a street with no
    /// betting would report a pot of zero while chips were already in.
    private static func blindsPosted(in hand: SessionHandRecord) -> BBAmount {
        let small = TableRules.seat(atOffset: 1, buttonSeat: hand.buttonSeat)
        let big = TableRules.seat(atOffset: 2, buttonSeat: hand.buttonSeat)
        return BBAmount(
            centiBB: min(TableRules.smallBlind.centiBB, hand.startingStacks[small].centiBB)
                + min(TableRules.bigBlind.centiBB, hand.startingStacks[big].centiBB)
        )
    }

    /// Who acted, by position, and which of the four disclosed profiles they
    /// are playing.
    ///
    /// The profile is named on every opponent action rather than only on the
    /// setup screen, because a replay read afterwards is where knowing that the
    /// three-bet came from the maniac is worth anything.
    private static func actorLabel(
        seat: Int,
        buttonSeat: Int,
        seating: SeatAssignment
    ) -> String {
        let position = (try? TableRules.position(seat: seat, buttonSeat: buttonSeat))?.label
            ?? "座位 \(seat)"
        guard seat != TableRules.heroSeat else {
            return "你（\(position)）"
        }
        guard let profileID = seating.profile(forSeat: seat) else {
            return position
        }
        return "\(position) · \(OpponentProfileTable.profile(profileID).name)"
    }

    // MARK: - Comparison

    /// The comparison for this hand, if installed content covers one of the
    /// preflop spots the hero played.
    ///
    /// When several are covered — opening the cutoff and then answering a
    /// three-bet there, both of which the shipped pack covers — the one shown
    /// is the spot whose range gives the hero's action the least weight. That
    /// is the same spot `KeyHandSelection` scored the hand on, so the reason
    /// printed at the top of the screen and the comparison below it are about
    /// the same decision. Ties resolve to the earlier spot.
    private func comparison(for hand: SessionHandRecord) -> KeyHandComparison? {
        let matches = matcher.matches(in: hand)
        guard !matches.isEmpty else {
            return nil
        }

        var chosen = matches[0]
        for match in matches.dropFirst() {
            let candidate = match.heroActionWeightBasisPoints ?? Int.max
            let incumbent = chosen.heroActionWeightBasisPoints ?? Int.max
            if candidate < incumbent {
                chosen = match
            }
        }

        guard let scenario = scenariosByID[chosen.scenarioID],
              let spot = hand.heroSpots.first(where: { $0.signature == chosen.signature })
        else {
            return nil
        }

        return KeyHandComparison(
            scenarioID: scenario.id,
            scenarioTitle: scenario.title,
            spotSummary: Self.spotSummary(chosen.signature),
            heroActionTitle: spot.action.displayTitle,
            heroActionWeightText: chosen.heroActionWeightBasisPoints
                .map { StrategyNumberText.frequency(basisPoints: $0) },
            rows: scenario.options.map { option in
                KeyHandComparisonRow(
                    id: option.action.stableID,
                    actionTitle: option.action.displayTitle,
                    frequencyText: StrategyNumberText.frequency(
                        basisPoints: option.frequencyBasisPoints
                    ),
                    evText: StrategyNumberText.ev(option.ev),
                    isHeroAction: RangeBaseline.actionKey(for: option.action)
                        == RangeBaseline.actionKey(for: spot.action)
                        && RangeBaseline.actionKey(for: spot.action) != nil
                )
            }
        )
    }

    private static func spotSummary(_ signature: SpotSignature) -> String {
        let position = (try? TablePosition(
            tableSize: TableRules.seatCount,
            heroSeatOffsetFromButton: signature.heroSeatOffsetFromButton
        ))?.label ?? "位置 \(signature.heroSeatOffsetFromButton)"

        let facing = switch signature.facing {
        case .unopened: "无人加注"
        case .singleRaise: "面对加注"
        case .reraise: "面对再加注"
        }

        return "\(position) · \(facing) · \(signature.handClass.description)"
    }
}
