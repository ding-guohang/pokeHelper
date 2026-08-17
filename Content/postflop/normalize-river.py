#!/usr/bin/env python3
"""Normalize a solved river spot into an immutable, exact-unit snapshot.

Input: the full-tree JSON from `generate-river.py`. Output: the OOP root-node
decision expressed in the project's exact units — per-hand action frequencies as
basis points that sum to EXACTLY 10,000 (largest-remainder rounding), per-action
EVs as integer milli-BB — plus a content hash. This is the postflop analogue of
the push/fold normalized batch and is what the downstream SolverExport is built
from.

Unit convention: the solver's chip unit is taken to be centi-BB, so a spot is
defined in BB terms (pot/stack in centi-BB) and EV chips convert to milli-BB by
x10. Floats are used only as solver inputs; everything stored here is integer.

No strategy truth is invented: every number is a deterministic transform of the
solver output, and the frequencies/EVs are copied per hand.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys


class NormalizeError(RuntimeError):
    pass


def largest_remainder(fracs, total=10000):
    """Round a list of fractions (summing to ~1) to integers summing exactly to
    `total`, giving the leftover units to the largest remainders. Deterministic."""
    if not fracs:
        return []
    scaled = [f * total for f in fracs]
    floors = [int(x) for x in scaled]
    remainder = total - sum(floors)
    if remainder < 0:
        raise NormalizeError("frequencies exceed 1.0 beyond rounding")
    # Distribute the leftover to the largest fractional parts; ties break by
    # lower index for determinism.
    order = sorted(range(len(fracs)), key=lambda i: (scaled[i] - floors[i], -i), reverse=True)
    for i in range(remainder):
        floors[order[i]] += 1
    return floors


def _root_node(doc):
    for n in doc["nodes"]:
        if n["path"] == [] and n["type"] == "decision":
            return n
    raise NormalizeError("no OOP root decision node")


def normalize(doc):
    root = _root_node(doc)
    if root["player"] != 0:
        raise NormalizeError("root node is not the OOP decision")
    actions = root["actions"]  # e.g. ["Check", "Bet(100)"]
    strat = root["strategy"]   # [action][hand]
    hands = doc["players"]["oop"]["hands"]
    n_actions = len(actions)
    n_hands = len(hands)
    if len(strat) != n_actions or any(len(a) != n_hands for a in strat):
        raise NormalizeError("strategy shape mismatch")

    ev_chips = doc["oopRootActionEVsChips"]  # [action][hand], chips (= centi-BB)
    if len(ev_chips) != n_actions or any(len(a) != n_hands for a in ev_chips):
        raise NormalizeError("root EV shape mismatch")

    cells = []
    for j, hand in enumerate(hands):
        fracs = [strat[a][j] for a in range(n_actions)]
        s = sum(fracs)
        if s <= 0:
            # Hand never reaches this node under its own weight; skip it.
            continue
        norm = [f / s for f in fracs]
        bp = largest_remainder(norm, 10000)
        if sum(bp) != 10000:
            raise NormalizeError(f"basis points for {hand['hand']} sum to {sum(bp)}")
        weight_bp = largest_remainder([hand["weight"]], 10000)[0] if hand["weight"] < 1.0 else 10000
        # chips are centi-BB; milli-BB = round(chips * 10).
        evs_milli = {actions[a]: int(round(ev_chips[a][j] * 10.0)) for a in range(n_actions)}
        cells.append({
            "hand": hand["hand"],
            "weightBasisPoints": weight_bp,
            "actionWeightsBasisPoints": {actions[a]: bp[a] for a in range(n_actions)},
            "actionEVsMilliBB": evs_milli,
        })

    out = {
        "solver": doc["solver"],
        "street": "river",
        "board": doc["board"],
        "oopRange": doc["oopRange"],
        "ipRange": doc["ipRange"],
        "potCentiBB": doc["startingPotChips"],
        "effectiveStackCentiBB": doc["effectiveStackChips"],
        "iterations": doc["iterations"],
        "exploitabilityMilliBB": round(doc["exploitabilityChips"] * 10.0, 6),
        "oopRootActions": actions,
        "rangeCells": cells,
    }
    out["snapshotSHA256"] = _snapshot_hash(out)
    return out


def _snapshot_hash(doc):
    payload = {k: v for k, v in doc.items() if k != "snapshotSHA256"}
    blob = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Normalize a solved river spot to exact units")
    parser.add_argument("--tree", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    doc = json.loads(Path(args.tree).read_text(encoding="utf-8"))
    result = normalize(doc)
    Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print(f"normalized {result['board']}: {len(result['rangeCells'])} OOP cells, "
          f"actions {result['oopRootActions']} -> {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except NormalizeError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
