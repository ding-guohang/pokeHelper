#!/usr/bin/env python3
"""Builds the 6-max 100BB preflop export from range charts.

Range tables are the input; every derived number is computed from them rather
than written by hand. That is deliberate: the previous version declared an open
frequency, listed a range, and let the two disagree by up to 17 percentage
points. Here the frequency is the range's combination weight, and a scenario's
option frequencies are read from the hero hand's own cell, so neither can drift.

Positions use PokerCore's six-handed labels, which are the only thing the app
renders: 0=BTN 1=SB 2=BB 3=UTG 4=HJ 5=CO.
"""

import collections
import json

RANKS = "AKQJT98765432"
TOTAL_COMBOS = 1326

SEAT = {"BTN": 0, "SB": 1, "BB": 2, "UTG": 3, "HJ": 4, "CO": 5}

# Bet tree, in centi-BB. Declared once and used everywhere.
OPEN = 250
OPEN_SB = 300
THREE_BET = 750
FOUR_BET = 1650
BB_POST = 100
SB_POST = 50


def combos(hand):
    if len(hand) == 2 and hand[0] == hand[1]:
        return 6
    return 4 if hand.endswith("s") else 12


def expand(spec):
    """'77+' / 'A2s+' / 'AJo-ATo' / 'KQs' -> list of hand classes."""
    out = []
    for token in spec.replace(" ", "").split(","):
        if not token:
            continue
        if token.endswith("+"):
            base = token[:-1]
            if len(base) == 2 and base[0] == base[1]:
                top = RANKS.index(base[0])
                out += [RANKS[i] * 2 for i in range(top + 1)]
            else:
                hi, kicker, suit = base[0], base[1], base[2]
                start, end = RANKS.index(kicker), RANKS.index(hi) + 1
                out += [f"{hi}{RANKS[i]}{suit}" for i in range(end, start + 1)]
        elif "-" in token:
            a, b = token.split("-")
            if len(a) == 2 and a[0] == a[1]:
                i, j = RANKS.index(a[0]), RANKS.index(b[0])
                out += [RANKS[k] * 2 for k in range(min(i, j), max(i, j) + 1)]
            else:
                hi, suit = a[0], a[2]
                i, j = RANKS.index(a[1]), RANKS.index(b[1])
                out += [f"{hi}{RANKS[k]}{suit}" for k in range(min(i, j), max(i, j) + 1)]
        else:
            out.append(token)
    return out


def build_range(pure, mixed=None):
    """pure: spec string raised 100%. mixed: {spec: weight}."""
    cells = {}
    for hand in expand(pure):
        cells[hand] = 10000
    for spec, weight in (mixed or {}).items():
        for hand in expand(spec):
            cells[hand] = weight
    return cells


def frequency_bp(cells):
    weighted = sum(combos(h) * w for h, w in cells.items())
    return round(weighted / TOTAL_COMBOS)


# --- Raise-first-in ranges -------------------------------------------------
# Written as charts because that is the unit a human can review. The stated
# percentage under each is computed, not asserted.

RFI = {
    "UTG": build_range(
        "66+,A8s+,K9s+,Q9s+,J9s+,T9s,AJo+,KQo",
        {"55-22": 5000, "A7s-A2s": 5000, "K8s": 4000, "Q8s": 3000,
         "J8s": 3000, "T8s": 3000, "98s": 5000, "87s": 3000,
         "ATo": 4000, "KJo": 3000},
    ),
    "HJ": build_range(
        "44+,A2s+,K8s+,Q9s+,J9s+,T9s,98s,ATo+,KQo",
        {"33-22": 6000, "K7s-K5s": 5000, "Q8s": 6000, "J8s": 5000,
         "T8s": 5000, "87s": 5000, "76s": 3000,
         "A9o": 5000, "KJo": 6000, "QJo": 4000},
    ),
    "CO": build_range(
        "22+,A2s+,K7s+,Q8s+,J8s+,T8s+,98s,87s,ATo+,KJo+,QJo",
        {"K6s-K2s": 5000, "Q7s-Q5s": 5000, "J7s": 5000, "T7s": 4000,
         "97s": 5000, "86s": 4000, "76s": 6000, "65s": 5000,
         "A9o": 6000, "KTo": 5000, "QTo": 4000, "JTo": 5000},
    ),
    "BTN": build_range(
        "22+,A2s+,K2s+,Q4s+,J6s+,T6s+,96s+,86s+,75s+,65s,54s,"
        "A2o+,K7o+,Q9o+,J9o+,T9o",
        {"Q2s-Q3s": 5000, "J5s": 4000, "T5s": 3000, "95s": 4000,
         "85s": 4000, "64s": 4000, "53s": 3000,
         "K5o-K6o": 4000, "Q8o": 4000, "J8o": 4000, "T8o": 4000,
         "98o": 6000, "87o": 4000, "76o": 3000},
    ),
    "SB": build_range(
        "22+,A2s+,K2s+,Q4s+,J6s+,T6s+,96s+,86s+,75s+,"
        "A2o+,K8o+,Q9o+,J9o+",
        {"95s": 9000, "85s": 8000, "64s": 7000, "53s": 5000,
         "T9o": 8000, "98o": 7000, "87o": 6000},
    ),
}

# --- CO facing a BTN 3bet --------------------------------------------------
VS_3BET = {}
for hand in expand("AA-QQ"):
    VS_3BET[hand] = {"raise": 10000}
for hand in expand("JJ-TT"):
    VS_3BET[hand] = {"call": 7000, "raise": 3000}
VS_3BET["AKs"] = {"raise": 10000}
VS_3BET["AKo"] = {"call": 4000, "raise": 6000}
VS_3BET["AQs"] = {"call": 8000, "raise": 2000}
VS_3BET["AQo"] = {"call": 4000, "fold": 6000}
VS_3BET["A5s"] = {"call": 2000, "raise": 5000, "fold": 3000}
VS_3BET["KQs"] = {"call": 7000, "fold": 3000}
for hand in expand("99-77"):
    VS_3BET[hand] = {"call": 6000, "fold": 4000}
VS_3BET["JTs"] = {"call": 5000, "fold": 5000}
VS_3BET["AJs"] = {"call": 6000, "fold": 4000}
VS_3BET["ATs"] = {"call": 5000, "fold": 5000}
for hand, weights in VS_3BET.items():
    total = sum(weights.values())
    if total < 10000:
        weights["fold"] = weights.get("fold", 0) + 10000 - total

# Every hand facing a 3bet must be one CO actually opened.
missing = [h for h in VS_3BET if RFI["CO"].get(h, 0) == 0]
assert not missing, f"vs-3bet references hands CO never opens: {missing}"


def explanation(conclusion, rng, opp, plan, gto, exploit=None):
    return collections.OrderedDict(
        conclusion=conclusion,
        rangeReasoning=rng,
        boardReasoning="翻前无公共牌，决策只依赖位置、范围与筹码深度。",
        opponentReasoning=opp,
        futurePlan=plan,
        gtoBaseline=gto,
        exploitCondition=exploit,
    )


def range_cells(cells, actions):
    """Range table rows, one per hand, sorted for stable output."""
    rows = []
    for hand in sorted(cells, key=lambda h: (len(h), h)):
        value = cells[hand]
        weights = value if isinstance(value, dict) else {
            actions[0]: value, "fold": 10000 - value
        }
        rows.append(collections.OrderedDict(
            handClass=hand,
            actionWeightsBasisPoints=collections.OrderedDict(
                sorted((k, v) for k, v in weights.items() if v > 0)
            ),
        ))
    return rows


def rfi_node(position, hero_cards, hero_hand, ev_raise):
    cells = RFI[position]
    weight = cells[hero_hand]
    is_sb = position == "SB"
    size = OPEN_SB if is_sb else OPEN
    # A mixed hand is mixed because the two lines are worth the same. Giving it
    # a wide EV gap would mark one of them an error while the chart calls both
    # correct.
    ev = ev_raise if weight == 10000 else 2

    return collections.OrderedDict(
        id=f"rfi-{position.lower()}",
        title=f"{position} 位翻前开池",
        abilityDimension="preflop-range",
        curriculumNodeID="preflop-rfi",
        heroSeatOffsetFromButton=SEAT[position],
        heroCards=hero_cards,
        board=[],
        pot={"centiBB": SB_POST + BB_POST},
        amountToCall={"centiBB": SB_POST if is_sb else BB_POST},
        minimumRaiseTo={"centiBB": BB_POST * 2},
        configuredBetSizes=[{"centiBB": size}],
        actions=[
            collections.OrderedDict(
                action={"kind": "raise", "toCentiBB": size},
                frequencyBasisPoints=weight,
                ev={"milliBB": ev},
            ),
            collections.OrderedDict(
                action={"kind": "fold"},
                frequencyBasisPoints=10000 - weight,
                ev={"milliBB": 0},
            ),
        ],
        rangeCells=range_cells(cells, ["raise"]),
        explanation=explanation(
            f"{position} 位以 {size / 100:g}BB 开池，"
            f"整段开池频率约 {frequency_bp(cells) / 100:.1f}%。",
            "范围随位置靠后放宽；边缘手牌以混合频率开池。"
            + ("本内容不建模跛入，对应移除跛入后重解的加注范围。" if is_sb else ""),
            "假设对手采用标准防守频率，不做针对性剥削。",
            "被 3bet 后按对应的应对范围继续。",
            "基线为位置化开池范围，弃牌与开池的两向混合。",
        ),
    )


CO_OPEN_INVESTED = OPEN
POT_AT_VS3BET = SB_POST + BB_POST + OPEN + THREE_BET

hero_vs3bet = "AQs"
vs3bet_weights = VS_3BET[hero_vs3bet]

nodes = [
    # Three pure hands and two mixed ones. A catalogue where every question has
    # one obviously correct answer never teaches that several near-EV actions
    # can all be right, which learning-rules.md calls out explicitly.
    rfi_node("UTG", ["Ad", "Kc"], "AKo", 190),
    rfi_node("HJ", ["Ad", "Tc"], "ATo", 40),
    rfi_node("CO", ["Ah", "5h"], "A5s", 150),
    rfi_node("BTN", ["9d", "8c"], "98o", 30),
    rfi_node("SB", ["Ad", "7c"], "A7o", 90),
    collections.OrderedDict(
        id="vs3bet-co-vs-btn",
        title="CO 开池面对 BTN 3bet",
        abilityDimension="preflop-range",
        curriculumNodeID="preflop-vs-3bet",
        heroSeatOffsetFromButton=SEAT["CO"],
        heroCards=["Ah", "Qh"],
        board=[],
        pot={"centiBB": POT_AT_VS3BET},
        amountToCall={"centiBB": THREE_BET - CO_OPEN_INVESTED},
        minimumRaiseTo={"centiBB": THREE_BET * 2 - CO_OPEN_INVESTED},
        configuredBetSizes=[{"centiBB": FOUR_BET}],
        actions=[
            collections.OrderedDict(
                action={"kind": "call", "toCentiBB": THREE_BET - CO_OPEN_INVESTED},
                frequencyBasisPoints=vs3bet_weights.get("call", 0),
                ev={"milliBB": 110},
            ),
            collections.OrderedDict(
                action={"kind": "raise", "toCentiBB": FOUR_BET},
                frequencyBasisPoints=vs3bet_weights.get("raise", 0),
                ev={"milliBB": 60},
            ),
            collections.OrderedDict(
                action={"kind": "fold"},
                frequencyBasisPoints=vs3bet_weights.get("fold", 0),
                ev={"milliBB": 0},
            ),
        ],
        rangeCells=range_cells(VS_3BET, ["call"]),
        explanation=explanation(
            f"面对 BTN 3bet 到 {THREE_BET / 100:g}BB，以跟注为主、少量 4bet。",
            "跟注范围保留摊牌价值好的牌，4bet 取最强牌与少量阻断牌；"
            "范围中的每一手都在 CO 的开池范围内。",
            "假设 BTN 用标准 3bet 范围，不针对性调整。",
            "跟注后进入无位置的锅，按翻牌节点继续。",
            "基线为跟注、4bet 与弃牌的三向混合。",
        ),
    ),
]

export = collections.OrderedDict(
    packID="cash-6max-100bb-core",
    generatedSource=(
        "claude-authored preflop charts; every frequency derived from the "
        "range tables rather than stated independently"
    ),
    exportedAt="2026-08-10T00:00:00Z",
    gameType="NLHE cash",
    tableSize=6,
    effectiveStack={"centiBB": 10000},
    rakeDescription="5% capped at 3BB",
    allowedBetSizeDescription=(
        f"{OPEN / 100:g}BB open ({OPEN_SB / 100:g}BB from SB), "
        f"{THREE_BET / 100:g}BB 3bet, {FOUR_BET / 100:g}BB 4bet"
    ),
    curriculum=[
        collections.OrderedDict(
            id="preflop-rfi", title="翻前开池", prerequisiteNodeIDs=[]),
        collections.OrderedDict(
            id="preflop-vs-3bet", title="面对 3bet",
            prerequisiteNodeIDs=["preflop-rfi"]),
    ],
    nodes=nodes,
)

for node in nodes:
    total = sum(a["frequencyBasisPoints"] for a in node["actions"])
    assert total == 10000, (node["id"], total)

with open("Content/exports/core-6max-100bb.json", "w") as handle:
    json.dump(export, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

for position, cells in RFI.items():
    print(f"{position:4} RFI {frequency_bp(cells) / 100:5.2f}%  "
          f"({len(cells)} 个手牌类别)")
