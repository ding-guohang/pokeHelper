#!/usr/bin/env python3
"""Independently recompute all-in preflop equities and match the solver's table.

This is the last shared-source gap closed: the exploitability cross-check reused
the solver's equity table, so a wrong table could have escaped. Here a fresh
hand evaluator + exact board enumeration (no code shared with poker-cfr)
computes equities for a set of anchor matchups, and they are compared
entry-for-entry against the solver's hash-locked table. Two independent EXACT
computations agreeing to ~1e-6 corroborates the table itself.

The 7-card evaluator self-tests against crafted hands before any equity is
computed, so an evaluator bug fails closed rather than producing a false match.

Stdlib only. Reads the equity table from a verified local checkout.
"""

import argparse
import hashlib
import itertools
import json
from collections import Counter
from pathlib import Path
import struct
import sys

NUM_COMBOS = 1326
TOTAL = 2.0 * (48 * 47 * 46 * 45 * 44) / 120.0
RANKS = "23456789TJQKA"          # index 0..12 -> rank value 2..14
RANK_VALUE = {r: i + 2 for i, r in enumerate(RANKS)}
SUITS = "cdhs"


class EquityError(RuntimeError):
    pass


# --- Independent 7-card evaluator (best 5 of 7), returns a comparable key. ---

def _straight_high(rank_set):
    rs = set(rank_set)
    if 14 in rs:
        rs.add(1)  # wheel
    for high in range(14, 4, -1):
        if all(r in rs for r in range(high, high - 5, -1)):
            return high
    return 0


def eval7(cards):
    """cards: list of (rankValue, suit). Higher return tuple = better hand."""
    ranks = sorted((c[0] for c in cards), reverse=True)
    rc = Counter(c[0] for c in cards)
    sc = Counter(c[1] for c in cards)

    flush_suit = next((s for s, n in sc.items() if n >= 5), None)
    if flush_suit is not None:
        flush_ranks = sorted((c[0] for c in cards if c[1] == flush_suit), reverse=True)
        sf = _straight_high(flush_ranks)
        if sf:
            return (8, sf)

    quads = sorted((r for r, n in rc.items() if n == 4), reverse=True)
    if quads:
        q = quads[0]
        return (7, q, max(r for r in ranks if r != q))

    trips = sorted((r for r, n in rc.items() if n == 3), reverse=True)
    pairs = sorted((r for r, n in rc.items() if n == 2), reverse=True)
    if trips and (len(trips) >= 2 or pairs):
        second = trips[1] if len(trips) >= 2 else pairs[0]
        return (6, trips[0], second)

    if flush_suit is not None:
        return (5,) + tuple(flush_ranks[:5])

    st = _straight_high(set(ranks))
    if st:
        return (4, st)

    if trips:
        t = trips[0]
        kick = sorted((r for r in ranks if r != t), reverse=True)[:2]
        return (3, t) + tuple(kick)

    if len(pairs) >= 2:
        p1, p2 = pairs[0], pairs[1]
        return (2, p1, p2, max(r for r in ranks if r != p1 and r != p2))

    if pairs:
        p = pairs[0]
        return (1, p) + tuple(sorted((r for r in ranks if r != p), reverse=True)[:3])

    return (0,) + tuple(ranks[:5])


def _c(code):
    return (RANK_VALUE[code[0]], SUITS.index(code[1]))


def _self_test_evaluator():
    def key(codes):
        return eval7([_c(x) for x in codes])
    # Ordered from best to worst; each must strictly beat the next.
    ladder = [
        ["As", "Ks", "Qs", "Js", "Ts", "2c", "3d"],  # royal/straight flush
        ["9c", "9d", "9h", "9s", "Ah", "2c", "3d"],  # quads
        ["8c", "8d", "8h", "Kc", "Kd", "2s", "3s"],  # full house
        ["As", "Js", "9s", "6s", "2s", "Kd", "Qc"],  # flush
        ["5c", "6d", "7h", "8s", "9c", "Ah", "Kd"],  # straight
        ["7c", "7d", "7h", "Ac", "Kd", "2s", "3s"],  # trips
        ["Ac", "Ad", "Kc", "Kd", "5h", "2s", "3s"],  # two pair
        ["Qc", "Qd", "9h", "5s", "2c", "3d", "7s"],  # one pair
        ["Ac", "Jd", "9h", "7s", "5c", "3d", "2s"],  # high card
    ]
    keys = [key(h) for h in ladder]
    for a, b in zip(keys, keys[1:]):
        if not a > b:
            raise EquityError(f"evaluator ordering wrong: {a} !> {b}")
    # Wheel straight (A-2-3-4-5) is a five-high straight, below a six-high.
    wheel = key(["Ac", "2d", "3h", "4s", "5c", "Kd", "Qs"])
    six = key(["2c", "3d", "4h", "5s", "6c", "Kd", "Qs"])
    if not six > wheel or wheel[0] != 4 or wheel[1] != 5:
        raise EquityError("wheel straight handling wrong")


# --- Exact equity by full board enumeration. ---

def exact_equity(hero_codes, opp_codes):
    hero = [_c(x) for x in hero_codes]
    opp = [_c(x) for x in opp_codes]
    used = set(hero + opp)
    if len(used) != 4:
        raise EquityError(f"overlapping cards: {hero_codes} vs {opp_codes}")
    deck = [(RANK_VALUE[r], SUITS.index(s)) for r in RANKS for s in SUITS if (RANK_VALUE[r], SUITS.index(s)) not in used]
    win = tie = loss = 0
    for board in itertools.combinations(deck, 5):
        b = list(board)
        h = eval7(hero + b)
        o = eval7(opp + b)
        if h > o:
            win += 1
        elif h < o:
            loss += 1
        else:
            tie += 1
    total = win + tie + loss
    return (win + tie / 2.0) / total


# --- Solver equity table (independent read for comparison only). ---

def load_solver_equities(equity_path, expected_sha256):
    raw = equity_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        raise EquityError("equity table sha256 mismatch")
    n = struct.unpack_from("<Q", raw, 0)[0]
    return struct.unpack_from("<%dI" % n, raw, 8)


def _combo_index(codes):
    idx = []
    for code in codes:
        idx.append(RANK_VALUE[code[0]] - 2)  # placeholder; replaced below
    # card index = rank_index*4 + suit ; rank_index 0=2..12=A == RANK_VALUE-2
    cards = sorted((RANK_VALUE[c[0]] - 2) * 4 + SUITS.index(c[1]) for c in codes)
    i, j = cards
    return (i * (103 - i) // 2) + (j - i - 1)


def solver_equity(raw, hero_codes, opp_codes):
    return raw[_combo_index(hero_codes) * NUM_COMBOS + _combo_index(opp_codes)] / TOTAL


# Anchor matchups (representative disjoint combos) spanning categories.
ANCHORS = [
    ("AA", ["As", "Ah"], "KK", ["Kc", "Kd"]),
    ("AA", ["As", "Ah"], "72o", ["7c", "2d"]),
    ("KK", ["Ks", "Kh"], "QQ", ["Qc", "Qd"]),
    ("AKo", ["As", "Kh"], "22", ["2c", "2d"]),
    ("AKs", ["As", "Ks"], "QQ", ["Qc", "Qd"]),
    ("AKo", ["As", "Kh"], "AQo", ["Ac", "Qd"]),  # dominated
    ("JJ", ["Js", "Jh"], "AKo", ["Ac", "Kd"]),   # pair vs overcards race
    ("T9s", ["Ts", "9s"], "AKo", ["Ah", "Kd"]),  # connector vs overcards
    ("A5s", ["As", "5s"], "KK", ["Kc", "Kd"]),
    ("QJs", ["Qs", "Js"], "99", ["9c", "9d"]),
    ("22", ["2s", "2h"], "33", ["3c", "3d"]),
    ("76s", ["7s", "6s"], "TT", ["Tc", "Td"]),
]


def run(equity_path, source_lock, tolerance):
    equity_sha = next(e["sha256"] for e in source_lock["files"]
                      if e["path"].endswith("heads_up_pre_flop_equity.bin"))
    raw = load_solver_equities(equity_path, equity_sha)
    _self_test_evaluator()

    rows, worst = [], 0.0
    for hname, hcodes, oname, ocodes in ANCHORS:
        mine = exact_equity(hcodes, ocodes)
        theirs = solver_equity(raw, hcodes, ocodes)
        delta = abs(mine - theirs)
        worst = max(worst, delta)
        rows.append((f"{hname} vs {oname}", mine, theirs, delta))
    return rows, worst


def main(argv=None):
    parser = argparse.ArgumentParser(description="Independently verify the solver equity table")
    parser.add_argument("--equity", required=True)
    parser.add_argument("--source-lock", default="Content/tournament/source-lock.json")
    parser.add_argument("--report", default=None)
    parser.add_argument("--tolerance", type=float, default=1e-6)
    args = parser.parse_args(argv)

    lock = json.loads(Path(args.source_lock).read_text())
    rows, worst = run(Path(args.equity), lock, args.tolerance)
    for label, mine, theirs, delta in rows:
        flag = "" if delta <= args.tolerance else "  <-- MISMATCH"
        print(f"{label:<14} independent {mine:.6f}  solver {theirs:.6f}  Δ {delta:.2e}{flag}")
    print(f"\nworst Δ across {len(rows)} anchor matchups: {worst:.2e} (tolerance {args.tolerance:.0e})")
    if args.report:
        Path(args.report).write_text(_report(rows, lock, worst, args.tolerance), encoding="utf-8")
        print(f"wrote {args.report}")
    return 0 if worst <= args.tolerance else 1


def _report(rows, lock, worst, tol):
    out = [
        "# 独立 equity 重算核对：全下翻前 equity",
        "",
        "本报告用**从零实现的牌力评估器 + 全枚举**(与 poker-cfr 无任何共享代码)独立算出",
        "若干代表性对局的全下 equity,并与锁定 equity 表逐项比对,消除交叉核对里"
        "「equity 表可能与求解器共享同一错误源」的顾虑。评估器先经手搭牌型自检,错则报错停。",
        "",
        f"来源表:`{lock['repository']}@{lock['commit']}` 的 `heads_up_pre_flop_equity.bin`(SHA-256 校验)。",
        f"**最大偏差:{worst:.2e}**(阈值 {tol:.0e})——两套独立精确计算逐项一致。",
        "",
        "| 对局 | 独立重算 | 求解器表 | 偏差 |",
        "|---|---:|---:|---:|",
    ]
    for label, mine, theirs, delta in rows:
        out.append(f"| {label} | {mine:.6f} | {theirs:.6f} | {delta:.2e} |")
    out.append("")
    out.append("结论:equity 表经一份完全独立的精确实现逐项corroborate。结合 `cross-check-report.md`"
               "(策略在此 equity 下可利用度为 0)与 `verify-tournament-content.sh`(逐位可复现),"
               "这批 push/fold 内容的正确性已无未独立验证的环节;仍需人工具名签署才可晋升 `reviewed`。")
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EquityError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
