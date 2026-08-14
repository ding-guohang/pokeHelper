#!/usr/bin/env python3
"""Convert a validated normalized HU push/fold batch into SolverExport JSON.

One immutable export per exact integer depth (1–20BB). Open-Jam exists for every
depth; Call-Jam only for depth >= 2 (at 1BB the BB has no chips behind). The
external `allIn` action maps to the range key `raise` (bet/raise/all-in are one
range entry). The batch is validated first; on any failure nothing is written.
"""

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

_HERE = Path(__file__).resolve().parent
_VALIDATOR_PATH = _HERE / "tournament" / "validate_hu_batch.py"
_SPEC = importlib.util.spec_from_file_location("validate_hu_batch", _VALIDATOR_PATH)
_VALIDATOR = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_VALIDATOR)
validate_batch = _VALIDATOR.validate_batch
BatchValidationError = _VALIDATOR.BatchValidationError

EXPORTED_AT = "2026-08-13T00:00:00Z"
CURRICULUM_NODE_ID = "tournament-hu-push-fold"


def _row_lookup(rows):
    return {row["handClass"]: row for row in rows}


def _bb(centi):
    return {"centiBB": centi}


def _ev(milli):
    return {"milliBB": milli}


def _range_cells(rows, primary_key, range_key):
    cells = []
    for row in rows:
        weights = row["actionWeightsBasisPoints"]
        evs = row["actionEVsMilliBB"]
        cells.append({
            "handClass": row["handClass"],
            "actionWeightsBasisPoints": {range_key: weights[primary_key], "fold": weights["fold"]},
            "actionEVs": {range_key: _ev(evs[primary_key]), "fold": _ev(evs["fold"])},
        })
    return cells


def _explanation(depth, position, primary_desc):
    return {
        "conclusion": f"{depth}BB 单挑 {position} 的 ChipEV 纳什 push/fold 均衡策略。",
        "rangeReasoning": "频率来自锁定开源 CFR+ 求解器的均衡平均策略，未经人工审核。",
        "boardReasoning": "翻前无公共牌；决策只依赖手牌、位置与有效深度。",
        "opponentReasoning": "对手为同一均衡下的最优回应，不做针对性剥削。",
        "futurePlan": f"这是{primary_desc}或弃牌的一次性全下决策，无后续街。",
        "gtoBaseline": "ChipEV 纳什均衡（无 ICM、无 ante、rake=0）。",
        "exploitCondition": None,
    }


def _open_jam_node(pack_id, depth, rows):
    centi = depth * 100
    call_amount = 50
    effective = centi - 50
    aa = _row_lookup(rows)["AA"]
    weights, evs = aa["actionWeightsBasisPoints"], aa["actionEVsMilliBB"]
    # When the shove exceeds the call, jamming is an all-in raise (range key
    # `raise`). At 1BB the SB has exactly the call behind, so "jam" is an all-in
    # call — the only legal aggressive action — and the range key is `call`.
    if effective > call_amount:
        aggressive = {"kind": "allIn", "toCentiBB": effective}
        range_key = "raise"
    else:
        aggressive = {"kind": "call", "toCentiBB": call_amount}
        range_key = "call"
    return {
        "id": f"{pack_id}-open-jam",
        "title": f"{depth}BB 单挑开局 Push/Fold（小盲）",
        "abilityDimension": "tournament-push-fold",
        "curriculumNodeID": CURRICULUM_NODE_ID,
        "heroSeatOffsetFromButton": 0,
        "facing": "unopened",
        "heroCards": ["As", "Ah"],
        "board": [],
        "pot": _bb(150),
        "amountToCall": _bb(call_amount),
        "minimumRaiseTo": None,
        "configuredBetSizes": [],
        "facingRaiseTo": None,
        "decisionEffectiveStack": _bb(effective),
        "actions": [
            {"action": {"kind": "fold"}, "frequencyBasisPoints": weights["fold"], "ev": _ev(evs["fold"])},
            {"action": aggressive, "frequencyBasisPoints": weights["allIn"], "ev": _ev(evs["allIn"])},
        ],
        "rangeCells": _range_cells(rows, "allIn", range_key),
        "explanation": _explanation(depth, "小盲开局", "全下"),
    }


def _call_jam_node(pack_id, depth, rows):
    centi = depth * 100
    aa = _row_lookup(rows)["AA"]
    weights, evs = aa["actionWeightsBasisPoints"], aa["actionEVsMilliBB"]
    return {
        "id": f"{pack_id}-call-jam",
        "title": f"{depth}BB 单挑面对全下（大盲）",
        "abilityDimension": "tournament-push-fold",
        "curriculumNodeID": CURRICULUM_NODE_ID,
        "heroSeatOffsetFromButton": 1,
        "facing": "singleRaise",
        "heroCards": ["As", "Ah"],
        "board": [],
        "pot": _bb(centi + 100),
        "amountToCall": _bb(centi - 100),
        "minimumRaiseTo": None,
        "configuredBetSizes": [],
        "facingRaiseTo": _bb(centi),
        "decisionEffectiveStack": _bb(centi - 100),
        "actions": [
            {"action": {"kind": "fold"}, "frequencyBasisPoints": weights["fold"], "ev": _ev(evs["fold"])},
            {"action": {"kind": "call", "toCentiBB": centi - 100},
             "frequencyBasisPoints": weights["call"], "ev": _ev(evs["call"])},
        ],
        "rangeCells": _range_cells(rows, "call", "call"),
        "explanation": _explanation(depth, "大盲防守", "跟注"),
    }


def build_export_doc(depth, normalized, content_version):
    pack_id = f"content-tourn-hu-pushfold-chip-ev-noante-{depth:02d}bb"
    commit = (normalized.get("source") or {}).get("commit", "unknown")
    centi = depth * 100
    nodes = [_open_jam_node(pack_id, depth, normalized["tables"]["openJam"])]
    if depth >= 2:
        nodes.append(_call_jam_node(pack_id, depth, normalized["tables"]["callJam"]))
    # Bind the generating run's identity into the disclosed source: solver commit,
    # depth, iterations, NashConv, and the normalized snapshot hash (which itself
    # covers the frequencies, EVs, and configuration).
    generated_source = (
        f"poker-cfr@{commit} HU chipEV push/fold {depth}BB"
        f" · iters={normalized['iterations']}"
        f" · NashConv={normalized['nashConvBB']:.3e}"
        f" · snapshot={normalized['snapshotSHA256'][:16]}"
        f" (unverified solver output)"
    )
    return {
        "packID": pack_id,
        "generatedSource": generated_source,
        "exportedAt": EXPORTED_AT,
        "gameType": "NLHE tournament",
        "tableSize": 2,
        "effectiveStack": _bb(centi),
        "rakeDescription": "rake=0",
        "allowedBetSizeDescription": "jam-or-fold only",
        "tournament": {
            "effectiveBigBlinds": depth,
            "smallBlindCentiBB": 50,
            "bigBlindCentiBB": 100,
            "hasAnte": False,
            "anteDescription": "no ante (heads-up SB=0.5BB/BB=1BB, rake=0, chipEV)",
            "equilibrium": "chipEV",
        },
        "curriculum": [{
            "id": CURRICULUM_NODE_ID,
            "title": "单挑 Push/Fold",
            "prerequisiteNodeIDs": [],
        }],
        "nodes": nodes,
    }


def _write_json(path, doc):
    path.write_text(
        json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def build_exports(input_dir, output_dir, content_version):
    """Validate the normalized batch, then write 20 SolverExport files
    atomically. Returns the sorted list of written paths; writes nothing on
    validation failure."""
    input_dir = Path(input_dir)
    validate_batch(input_dir)  # raises BatchValidationError on any defect

    docs = {}
    for depth in range(1, 21):
        normalized = json.loads(
            (input_dir / f"hu-chip-ev-noante-{depth:02d}bb.json").read_text(encoding="utf-8")
        )
        docs[depth] = build_export_doc(depth, normalized, content_version)

    output_dir = Path(output_dir)
    staging = Path(tempfile.mkdtemp(prefix="tourn-exports-"))
    written = []
    try:
        for depth, doc in docs.items():
            name = f"tourn-hu-chip-ev-noante-{depth:02d}bb.json"
            _write_json(staging / name, doc)
            written.append(name)
        if output_dir.exists():
            for name in written:
                target = output_dir / name
                if target.exists():
                    target.unlink()
        output_dir.mkdir(parents=True, exist_ok=True)
        for name in written:
            shutil.move(str(staging / name), str(output_dir / name))
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return sorted(output_dir / n for n in written)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build tournament SolverExport files")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--content-version", required=True)
    args = parser.parse_args(argv)
    paths = build_exports(args.input, args.output, args.content_version)
    print(f"wrote {len(paths)} exports to {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BatchValidationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
