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
    # Batch A (river-start): the acting player is OOP (0). Batch B (from-flop):
    # the extracted river node's player is `nodePlayer`.
    node_player = doc.get("nodePlayer", 0)
    root = _root_node(doc)
    if root["player"] != node_player:
        raise NormalizeError("root node player does not match nodePlayer")
    actions = root["actions"]  # e.g. ["Check", "Bet(100)"]
    strat = root["strategy"]   # [action][hand]
    hands = doc["players"]["oop" if node_player == 0 else "ip"]["hands"]
    n_actions = len(actions)
    n_hands = len(hands)
    if len(strat) != n_actions or any(len(a) != n_hands for a in strat):
        raise NormalizeError("strategy shape mismatch")

    # Batch A carries oopRootActionEVsChips; Batch B carries nodeActionEVsChips.
    ev_chips = doc.get("oopRootActionEVsChips") or doc["nodeActionEVsChips"]
    if len(ev_chips) != n_actions or any(len(a) != n_hands for a in ev_chips):
        raise NormalizeError("root EV shape mismatch")

    cells = []
    for j, hand in enumerate(hands):
        fracs = [strat[a][j] for a in range(n_actions)]
        s = sum(fracs)
        if s <= 0:
            # Hand never reaches this node under its own weight; skip it.
            continue
        # The combo's reach weight in the range (fractional for narrowed Batch B
        # ranges); a plain round, not the distribution rounder.
        weight_bp = max(0, min(10000, int(round(hand["weight"] * 10000))))
        if weight_bp == 0:
            # Combo effectively never reaches this node after the betting line;
            # excluding it keeps the trainer from dealing spots that don't occur.
            continue
        norm = [f / s for f in fracs]
        bp = largest_remainder(norm, 10000)
        if sum(bp) != 10000:
            raise NormalizeError(f"basis points for {hand['hand']} sum to {sum(bp)}")
        # chips are centi-BB; milli-BB = round(chips * 10).
        evs_milli = {actions[a]: int(round(ev_chips[a][j] * 10.0)) for a in range(n_actions)}
        cells.append({
            "hand": hand["hand"],
            "weightBasisPoints": weight_bp,
            "actionWeightsBasisPoints": {actions[a]: bp[a] for a in range(n_actions)},
            "actionEVsMilliBB": evs_milli,
        })

    # Base fields, identical for both modes. The river-start (Batch A) snapshot
    # keeps EXACTLY its original key set so its committed packs stay byte-
    # reproducible; from-flop (Batch B) adds its own fields.
    out = {
        "solver": doc["solver"],
        "street": "river",
        "board": doc["board"],
        "oopRange": doc["oopRange"],
        "ipRange": doc["ipRange"],
        "potCentiBB": doc.get("riverPotChips", doc["startingPotChips"]),
        "effectiveStackCentiBB": doc["effectiveStackChips"],
        "iterations": doc["iterations"],
        "oopRootActions": actions,
        "rangeCells": cells,
    }
    if doc.get("mode") == "from-flop":
        out["mode"] = "from-flop"
        out["nodePlayer"] = node_player
        if "line" in doc:
            out["line"] = doc["line"]
        if "fullGameExploitabilityChips" in doc:
            out["fullGameExploitabilityMilliBB"] = round(doc["fullGameExploitabilityChips"] * 10.0, 6)
    else:
        out["exploitabilityMilliBB"] = round(doc["exploitabilityChips"] * 10.0, 6)
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
