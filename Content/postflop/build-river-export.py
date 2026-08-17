#!/usr/bin/env python3
"""Build a SolverExport JSON for one normalized river spot.

Consumes the exact-unit snapshot from `normalize-river.py` and emits the
SolverExport shape that `strategy-import` accepts (same fields as the push/fold
exports, minus the `tournament` block — this is a cash postflop scenario). The
OOP river root becomes one decision node: `facing=unopened`, `amountToCall=0`,
`configuredBetSizes=[<bet>]`, options Check + Bet(<size>) (both legal under
`BettingDecisionContext.legalActions`), and per-combo range cells carrying the
normalized frequencies and EVs.

Node-level option frequencies/EVs are the range's reach-weighted average (a
faithful summary of the mixed strategy); per-combo detail lives in rangeCells.
No numbers are invented — everything is copied or averaged from the snapshot.
"""

import argparse
import json
from pathlib import Path
import re
import sys

_HERE = Path(__file__).resolve().parent
EXPORTED_AT = "2026-08-17T00:00:00Z"
CURRICULUM_NODE_ID = "river-decision"


class ExportError(RuntimeError):
    pass


def _largest_remainder(fracs, total=10000):
    scaled = [f * total for f in fracs]
    floors = [int(x) for x in scaled]
    rem = total - sum(floors)
    if rem < 0:
        raise ExportError("frequencies exceed 1.0")
    order = sorted(range(len(fracs)), key=lambda i: (scaled[i] - floors[i], -i), reverse=True)
    for i in range(rem):
        floors[order[i]] += 1
    return floors


def _action_key_and_kind(label):
    """Map a solver action label to (rangeCellKey, DecisionAction dict)."""
    if label == "Check":
        return "check", {"kind": "check"}
    m = re.match(r"Bet\((\d+)\)", label)
    if m:
        return "bet", {"kind": "bet", "toCentiBB": int(m.group(1))}
    raise ExportError(f"unsupported OOP root action for river content: {label}")


def build_export(snapshot, commit, content_version):
    actions = snapshot["oopRootActions"]
    keys, kinds, bet_size = [], [], None
    for label in actions:
        key, kind = _action_key_and_kind(label)
        keys.append(key)
        kinds.append(kind)
        if kind["kind"] == "bet":
            bet_size = kind["toCentiBB"]
    if bet_size is None:
        raise ExportError("river root has no bet size to configure")

    cells = snapshot["rangeCells"]
    pot = snapshot["potCentiBB"]
    stack = snapshot["effectiveStackCentiBB"]

    # Range reach-weighted averages for the node-level options.
    total_w = sum(c["weightBasisPoints"] for c in cells)
    if total_w == 0:
        raise ExportError("empty range")
    avg_fracs = []
    avg_evs = []
    for a, label in enumerate(actions):
        wf = sum(c["weightBasisPoints"] * c["actionWeightsBasisPoints"][label] for c in cells)
        avg_fracs.append(wf / (total_w * 10000.0))
        we = sum(c["weightBasisPoints"] * c["actionEVsMilliBB"][label] for c in cells)
        avg_evs.append(int(round(we / total_w)))
    node_bp = _largest_remainder(avg_fracs, 10000)

    node_actions = []
    for a in range(len(actions)):
        node_actions.append({
            "action": kinds[a],
            "frequencyBasisPoints": node_bp[a],
            "ev": {"milliBB": avg_evs[a]},
        })

    range_cells = []
    for c in cells:
        w = {keys[a]: c["actionWeightsBasisPoints"][actions[a]] for a in range(len(actions))}
        e = {keys[a]: {"milliBB": c["actionEVsMilliBB"][actions[a]]} for a in range(len(actions))}
        range_cells.append({"handClass": c["hand"], "actionWeightsBasisPoints": w, "actionEVs": e})

    board = [snapshot["board"][i:i + 2] for i in range(0, len(snapshot["board"]), 2)]
    pack_id = f"content-river-{snapshot['board'].lower()}"
    generated_source = (
        f"postflop-solver@{commit} river OOP root {snapshot['board']}"
        f" · iters={snapshot['iterations']}"
        f" · exploitability={snapshot['exploitabilityMilliBB']:.3f}mBB"
        f" · snapshot={snapshot['snapshotSHA256'][:16]}"
        f" (unverified solver output)"
    )

    node = {
        "id": f"{pack_id}-oop-root",
        "title": f"River OOP 决策 {snapshot['board']}",
        "abilityDimension": "river-decision",
        "curriculumNodeID": CURRICULUM_NODE_ID,
        "heroSeatOffsetFromButton": 1,  # heads-up big blind = out of position
        "facing": "unopened",
        "heroCards": ["As", "Ah"],  # representative in-range combo, not on this board
        "board": board,
        "pot": {"centiBB": pot},
        "amountToCall": {"centiBB": 0},
        "minimumRaiseTo": None,
        "configuredBetSizes": [{"centiBB": bet_size}],
        "facingRaiseTo": None,
        "decisionEffectiveStack": {"centiBB": stack},
        "actions": node_actions,
        "rangeCells": range_cells,
        "explanation": {
            "conclusion": f"{snapshot['board']} 单挑 OOP 翻牌后（河牌）无人下注时的 GTO 开局决策。",
            "rangeReasoning": "频率来自锁定开源 CFR 翻后求解器的均衡平均策略，未经人工审核。",
            "boardReasoning": "公共牌已完整（河牌），决策只依赖成手强度与阻挡牌。",
            "opponentReasoning": "对手为同一均衡下的最优回应，不做针对性剥削。",
            "futurePlan": "河牌为最后一条街，无后续街。",
            "gtoBaseline": "ChipEV 纳什均衡（rake=0，单挑）。",
            "exploitCondition": None,
        },
    }

    return {
        "packID": pack_id,
        "generatedSource": generated_source,
        "exportedAt": EXPORTED_AT,
        "gameType": "NLHE cash",
        "tableSize": 2,
        "effectiveStack": {"centiBB": stack},
        "rakeDescription": "rake=0",
        "allowedBetSizeDescription": f"single {bet_size} centi-BB river bet",
        "tournament": None,
        "curriculum": [{"id": CURRICULUM_NODE_ID, "title": "河牌决策", "prerequisiteNodeIDs": []}],
        "nodes": [node],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build a SolverExport for a normalized river spot")
    parser.add_argument("--normalized", required=True)
    parser.add_argument("--source-lock", default=str(_HERE / "source-lock.json"))
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    snapshot = json.loads(Path(args.normalized).read_text(encoding="utf-8"))
    commit = json.loads(Path(args.source_lock).read_text(encoding="utf-8"))["commit"]
    export = build_export(snapshot, commit, args.content_version)
    Path(args.output).write_text(json.dumps(export, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote SolverExport {export['packID']} ({len(export['nodes'][0]['rangeCells'])} cells) -> {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExportError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
