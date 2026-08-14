#!/usr/bin/env python3
"""Independently validate a normalized HU push/fold batch from JSON alone.

This deliberately imports no solver code. It recomputes the canonical 169 hand
classes, checks basis-point totals, verifies the snapshot hash, the locked
source hashes, assumptions, table/depth coverage, the NashConv threshold, the
fold-EV invariants, and the action vocabulary. Any failure raises
`BatchValidationError` naming the offending depth/table/hand/action and writes
nothing.

Usage: `python3 validate_hu_batch.py <normalized-dir> [--source-lock <path>]`.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

RANKS = "AKQJT98765432"  # high to low
MIN_DEPTH = 1
MAX_DEPTH = 20


class BatchValidationError(RuntimeError):
    """A normalized batch violated a coverage, structure, or provenance rule."""


def canonical_169() -> set:
    classes = set()
    for i in range(13):
        for j in range(13):
            hi, lo = RANKS[min(i, j)], RANKS[max(i, j)]
            if i == j:
                classes.add(hi + hi)
            elif i < j:
                classes.add(hi + lo + "s")
            else:
                classes.add(hi + lo + "o")
    assert len(classes) == 169
    return classes


CANONICAL = canonical_169()


def _canonical_json(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _snapshot_hash(doc: dict) -> str:
    core = {k: v for k, v in doc.items() if k != "snapshotSHA256"}
    return hashlib.sha256(_canonical_json(core).encode("utf-8")).hexdigest()


def _expected_tables(depth: int):
    # Open-Jam exists for every depth; the BB has a fold/call decision only when
    # it has chips behind, i.e. depth >= 2.
    return ("openJam", "call")[:1] if depth < 2 else None


def _validate_table(depth, name, rows, primary_key, fold_ev):
    seen = set()
    for row in rows:
        hand = row.get("handClass")
        if hand not in CANONICAL:
            raise BatchValidationError(f"{depth}BB {name}: non-canonical hand {hand!r}")
        if hand in seen:
            raise BatchValidationError(f"{depth}BB {name}: duplicate hand {hand}")
        seen.add(hand)

        weights = row.get("actionWeightsBasisPoints") or {}
        evs = row.get("actionEVsMilliBB") or {}
        expected_keys = {primary_key, "fold"}
        if set(weights) != expected_keys:
            raise BatchValidationError(
                f"{depth}BB {name} {hand}: frequency keys {set(weights)} != {expected_keys}"
            )
        if set(evs) != set(weights):
            raise BatchValidationError(
                f"{depth}BB {name} {hand}: EV keys {set(evs)} != frequency keys {set(weights)}"
            )
        for action, value in evs.items():
            if value is None or not isinstance(value, int):
                raise BatchValidationError(
                    f"{depth}BB {name} {hand}: {action} EV must be an integer milli-BB, got {value!r}"
                )
        total = weights[primary_key] + weights["fold"]
        if total != 10_000:
            raise BatchValidationError(
                f"{depth}BB {name} {hand}: basis points total {total} != 10000"
            )
        if evs["fold"] != fold_ev:
            raise BatchValidationError(
                f"{depth}BB {name} {hand}: fold EV {evs['fold']} != invariant {fold_ev}"
            )

    missing = CANONICAL - seen
    if missing:
        sample = sorted(missing)[:3]
        raise BatchValidationError(
            f"{depth}BB {name}: missing {len(missing)} hands e.g. {sample}"
        )


def _validate_document(depth: int, doc: dict, source_lock: dict = None):
    if doc.get("effectiveBigBlinds") != depth:
        raise BatchValidationError(
            f"{depth}BB: effectiveBigBlinds {doc.get('effectiveBigBlinds')} != filename depth"
        )
    if doc.get("testOnly"):
        raise BatchValidationError(f"{depth}BB: testOnly output is not a production batch")

    config = doc.get("configuration") or {}
    threshold = config.get("nashConvThresholdBB")
    nash = doc.get("nashConvBB")
    # A NaN would slip past `>` comparisons, so reject non-finite explicitly.
    if not isinstance(nash, (int, float)) or nash != nash or nash == float("inf"):
        raise BatchValidationError(f"{depth}BB: NashConv is not a finite number: {nash!r}")
    if threshold is None or nash > threshold:
        raise BatchValidationError(f"{depth}BB: NashConv {nash} exceeds threshold {threshold}")

    # Assumptions must be exactly the audited game, not just internally consistent.
    if config.get("smallBlindCentiBB") != 50 or config.get("bigBlindCentiBB") != 100:
        raise BatchValidationError(f"{depth}BB: blinds must be SB=50/BB=100 centiBB")
    if config.get("hasAnte") is not False:
        raise BatchValidationError(f"{depth}BB: hasAnte must be false")
    if not (config.get("anteDescription") or "").strip():
        raise BatchValidationError(f"{depth}BB: anteDescription must be non-empty")
    if config.get("equilibrium") != "chipEV":
        raise BatchValidationError(f"{depth}BB: equilibrium must be chipEV, got {config.get('equilibrium')!r}")

    # exploitability is conventionally NashConv/2; the two must not be conflated.
    expl = doc.get("exploitabilityBB")
    if expl is None or abs(expl - nash / 2.0) > 1e-12:
        raise BatchValidationError(f"{depth}BB: exploitabilityBB {expl} != NashConv/2 {nash / 2.0}")

    if _snapshot_hash(doc) != doc.get("snapshotSHA256"):
        raise BatchValidationError(f"{depth}BB: snapshot hash mismatch")

    if source_lock is not None:
        src = doc.get("source") or {}
        if src.get("commit") != source_lock.get("commit"):
            raise BatchValidationError(f"{depth}BB: source commit {src.get('commit')} != lock")
        if src.get("licenseSpdx") != (source_lock.get("license") or {}).get("spdx"):
            raise BatchValidationError(f"{depth}BB: source license != lock")
        locked = {e["path"]: e["sha256"] for e in source_lock["files"]}
        recorded = src.get("lockedHashes") or {}
        for path, sha in locked.items():
            if recorded.get(path) != sha:
                raise BatchValidationError(
                    f"{depth}BB: source hash for {path} does not match the lock"
                )

    tables = doc.get("tables") or {}
    if "openJam" not in tables:
        raise BatchValidationError(f"{depth}BB: missing Open-Jam table")
    _validate_table(depth, "Open-Jam", tables["openJam"], "allIn", -500)

    if depth >= 2:
        if "callJam" not in tables:
            raise BatchValidationError(f"{depth}BB: missing Call-Jam table")
        _validate_table(depth, "Call-Jam", tables["callJam"], "call", -1000)
    elif "callJam" in tables:
        raise BatchValidationError("1BB: must not contain a Call-Jam table")


def validate_batch(directory, source_lock=None) -> dict:
    """Validate a complete 1–20BB batch. Returns an audit dict sorted by depth;
    raises on the first violation and writes nothing."""
    directory = Path(directory)
    if isinstance(source_lock, (str, Path)):
        source_lock = json.loads(Path(source_lock).read_text(encoding="utf-8"))

    depths = list(range(MIN_DEPTH, MAX_DEPTH + 1))
    row_count = 0
    table_count = 0
    max_nash = 0.0
    for depth in depths:
        path = directory / f"hu-chip-ev-noante-{depth:02d}bb.json"
        if not path.is_file():
            raise BatchValidationError(f"missing {depth}BB normalized file")
        doc = json.loads(path.read_text(encoding="utf-8"))
        _validate_document(depth, doc, source_lock)
        tables = doc["tables"]
        table_count += len(tables)
        row_count += sum(len(rows) for rows in tables.values())
        max_nash = max(max_nash, doc["nashConvBB"])

    return {
        "depths": depths,
        "tableCount": table_count,
        "rowCount": row_count,
        "maxNashConvBB": max_nash,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Validate a normalized HU push/fold batch")
    parser.add_argument("directory")
    parser.add_argument("--source-lock", default=None)
    args = parser.parse_args(argv)
    audit = validate_batch(args.directory, args.source_lock)
    print(
        f"{len(audit['depths'])} depths, {audit['tableCount']} tables, "
        f"{audit['rowCount']} rows: PASS (max NashConv {audit['maxNashConvBB']:.3e})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BatchValidationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
