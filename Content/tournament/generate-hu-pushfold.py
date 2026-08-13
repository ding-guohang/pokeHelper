#!/usr/bin/env python3
"""Generate normalized HU push/fold solver content, one JSON file per depth.

Provenance: a full checkout is taken at the locked commit and EVERY file listed
in source-lock.json is SHA-256 verified before the read-only export binary is
built and run. A mismatch fails closed. (fetch-locked-source.py remains the
pinned-URL fetch primitive; building the export bin needs the complete crate —
game_node.rs and valid bin paths — so generation uses a verified checkout.)

Determinism: RAYON_NUM_THREADS=1, a fixed checkpoint schedule, a fixed
`exportedAt`, no wall clock, and single-threaded CFR+ make each depth's output
byte-identical across runs.

Stdlib only. Public entry `run_solver(...)` returns the normalized dict; `main`
writes the full 1–20BB batch atomically.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOCK = Path(__file__).resolve().parent / "source-lock.json"
EXPORT_BIN_SRC = Path(__file__).resolve().parent / "patches" / "main_hu_export.rs"
DEFAULT_CHECKPOINTS = [10_000, 20_000, 40_000, 80_000, 160_000]
DEFAULT_THRESHOLD = 0.001
EXPORTED_AT = "2026-08-13T00:00:00Z"
SMALL_BLIND_CENTI_BB = 50
BIG_BLIND_CENTI_BB = 100
ANTE_DESCRIPTION = "no ante (rake=0), heads-up SB=0.5BB/BB=1BB chipEV"


class SolverError(RuntimeError):
    """Provenance, build, or export failure."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_lock(lock_path=DEFAULT_LOCK) -> dict:
    return json.loads(Path(lock_path).read_text(encoding="utf-8"))


def ensure_source(lock: dict, cache_dir: Path) -> Path:
    """Return a verified checkout at the locked commit, cloning once and
    verifying every locked hash. Fails closed on any mismatch."""
    commit = lock["commit"]
    repository = lock["repository"]
    crate = cache_dir / f"poker-cfr-{commit}"
    marker = crate / ".verified"
    if marker.exists() and marker.read_text(encoding="utf-8").strip() == commit:
        return crate

    if crate.exists():
        shutil.rmtree(crate)
    cache_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "clone", "--quiet", f"https://github.com/{repository}", str(crate)],
        check=True,
    )
    subprocess.run(["git", "-C", str(crate), "checkout", "--quiet", commit], check=True)
    head = subprocess.run(
        ["git", "-C", str(crate), "rev-parse", "HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    if head != commit:
        shutil.rmtree(crate)
        raise SolverError(f"checkout HEAD {head} != locked commit {commit}")

    for entry in [lock["license"], *lock["files"]]:
        path = crate / entry["path"]
        if not path.is_file():
            shutil.rmtree(crate)
            raise SolverError(f"locked input missing from checkout: {entry['path']}")
        actual = _sha256(path.read_bytes())
        if actual != entry["sha256"]:
            shutil.rmtree(crate)
            raise SolverError(
                f"sha256 mismatch for {entry['path']}: {actual} != {entry['sha256']}"
            )
    marker.write_text(commit, encoding="utf-8")
    return crate


def build_solver(crate: Path) -> Path:
    """Drop the read-only export bin into the verified crate and build it.

    Only additive: a new source file and a Cargo `[[bin]]` stanza; no locked
    source is modified."""
    shutil.copyfile(EXPORT_BIN_SRC, crate / "src" / "main_hu_export.rs")
    cargo = crate / "Cargo.toml"
    text = cargo.read_text(encoding="utf-8")
    if 'name = "hu_export"' not in text:
        text += '\n[[bin]]\nname = "hu_export"\npath = "src/main_hu_export.rs"\n'
        cargo.write_text(text, encoding="utf-8")
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.cargo' / 'bin'}:{env.get('PATH', '')}"
    subprocess.run(
        ["cargo", "build", "--release", "--bin", "hu_export"],
        cwd=crate, check=True, env=env,
    )
    return crate / "target" / "release" / "hu_export"


_BINARY_CACHE: dict = {}


def _solver_binary(lock: dict, cache_dir: Path) -> Path:
    key = str(cache_dir)
    if key not in _BINARY_CACHE:
        crate = ensure_source(lock, cache_dir)
        _BINARY_CACHE[key] = build_solver(crate)
    return _BINARY_CACHE[key]


def _parse_table_row(line: str, primary_key: str) -> dict:
    parts = line.split()
    hand_class, primary_bps, fold_bps, primary_ev, fold_ev = parts
    return {
        "handClass": hand_class,
        "actionWeightsBasisPoints": {primary_key: int(primary_bps), "fold": int(fold_bps)},
        "actionEVsMilliBB": {primary_key: int(primary_ev), "fold": int(fold_ev)},
    }


def _parse_solver_output(text: str) -> dict:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    header = {}
    tables = {}
    section = None
    for line in lines:
        if line.startswith("DEPTH "):
            header["effectiveBigBlinds"] = int(line.split()[1])
        elif line.startswith("ITER "):
            header["iterations"] = int(line.split()[1])
        elif line.startswith("NASHCONV "):
            header["nashConvBB"] = float(line.split()[1])
        elif line.startswith("TESTONLY "):
            header["testOnly"] = line.split()[1] == "1"
        elif line == "OPENJAM":
            section = ("openJam", "allIn")
            tables["openJam"] = []
        elif line == "CALLJAM":
            section = ("callJam", "call")
            tables["callJam"] = []
        elif line == "END":
            section = None
        elif section is not None:
            name, primary_key = section
            tables[name].append(_parse_table_row(line, primary_key))
    header["tables"] = tables
    return header


def _canonical_json(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def snapshot_hash(doc: dict) -> str:
    """SHA-256 over everything but the hash field, binding frequencies, action
    EVs, NashConv, and configuration together."""
    core = {k: v for k, v in doc.items() if k != "snapshotSHA256"}
    return _sha256(_canonical_json(core).encode("utf-8"))


def _configuration(lock: dict, checkpoints, threshold) -> dict:
    return {
        "smallBlindCentiBB": SMALL_BLIND_CENTI_BB,
        "bigBlindCentiBB": BIG_BLIND_CENTI_BB,
        "hasAnte": False,
        "anteDescription": ANTE_DESCRIPTION,
        "equilibrium": "chipEV",
        "rustVersion": lock.get("rustVersion"),
        "checkpoints": list(checkpoints),
        "nashConvThresholdBB": threshold,
        "rayonThreads": 1,
    }


def _source_provenance(lock: dict) -> dict:
    return {
        "repository": lock["repository"],
        "commit": lock["commit"],
        "licenseSpdx": lock["license"]["spdx"],
        "lockedHashes": {entry["path"]: entry["sha256"] for entry in lock["files"]},
    }


def run_solver(
    depth: int,
    checkpoints=DEFAULT_CHECKPOINTS,
    output=None,
    threshold=DEFAULT_THRESHOLD,
    test_only=False,
    lock=None,
    cache_dir=None,
) -> dict:
    """Solve one depth and return its normalized document, optionally writing it."""
    lock = lock or load_lock()
    cache_dir = Path(cache_dir) if cache_dir else Path(tempfile.gettempdir()) / "pokerhelper-solver-cache"
    binary = _solver_binary(lock, cache_dir)

    env = dict(os.environ)
    env["RAYON_NUM_THREADS"] = "1"
    command = [
        str(binary),
        "--depth", str(depth),
        "--checkpoints", ",".join(str(c) for c in checkpoints),
        "--threshold", repr(threshold),
    ]
    if test_only:
        command.append("--test-only")
    # The upstream equity table is loaded via a path relative to the crate root
    # (`static/heads_up_pre_flop_equity.bin`), so run from there.
    crate_dir = Path(binary).parents[2]
    result = subprocess.run(
        command, check=True, capture_output=True, text=True, env=env, cwd=crate_dir
    )

    parsed = _parse_solver_output(result.stdout)
    if parsed.get("effectiveBigBlinds") != depth:
        raise SolverError(f"solver returned depth {parsed.get('effectiveBigBlinds')} for {depth}")

    doc = {
        "effectiveBigBlinds": parsed["effectiveBigBlinds"],
        "source": _source_provenance(lock),
        "configuration": _configuration(lock, checkpoints, threshold),
        "iterations": parsed["iterations"],
        "nashConvBB": parsed["nashConvBB"],
        "exploitabilityBB": parsed["nashConvBB"] / 2.0,
        "testOnly": parsed["testOnly"],
        "exportedAt": EXPORTED_AT,
        "tables": parsed["tables"],
    }
    doc["snapshotSHA256"] = snapshot_hash(doc)

    if output is not None:
        output = Path(output)
        output.mkdir(parents=True, exist_ok=True)
        _write_json(output / f"hu-chip-ev-noante-{depth:02d}bb.json", doc)
    return doc


def _write_json(path: Path, doc: dict) -> None:
    text = json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")


def _parse_depths(spec: str):
    if "-" in spec and "," not in spec:
        lo, hi = spec.split("-")
        return list(range(int(lo), int(hi) + 1))
    return [int(x) for x in spec.split(",")]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Generate HU push/fold normalized content")
    parser.add_argument("--source-lock", default=str(DEFAULT_LOCK))
    parser.add_argument("--depths", default="1-20")
    parser.add_argument("--checkpoints", default=",".join(str(c) for c in DEFAULT_CHECKPOINTS))
    parser.add_argument("--nash-conv-threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cache-dir", default=None)
    parser.add_argument("--test-only", action="store_true")
    args = parser.parse_args(argv)

    lock = load_lock(args.source_lock)
    checkpoints = [int(c) for c in args.checkpoints.split(",")]
    depths = _parse_depths(args.depths)

    # Build every document in memory first; only publish the batch if all succeed.
    docs = {}
    for depth in depths:
        docs[depth] = run_solver(
            depth,
            checkpoints=checkpoints,
            threshold=args.nash_conv_threshold,
            test_only=args.test_only,
            lock=lock,
            cache_dir=args.cache_dir,
        )
        print(f"depth {depth:>2}bb: iterations={docs[depth]['iterations']} "
              f"nashConvBB={docs[depth]['nashConvBB']:.3e}", file=sys.stderr)

    output = Path(args.output)
    staging = Path(tempfile.mkdtemp(prefix="hu-normalized-"))
    try:
        for depth, doc in docs.items():
            _write_json(staging / f"hu-chip-ev-noante-{depth:02d}bb.json", doc)
        if output.exists():
            shutil.rmtree(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(output))
    finally:
        if Path(staging).exists():
            shutil.rmtree(staging, ignore_errors=True)
    print(f"wrote {len(docs)} normalized files to {output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
