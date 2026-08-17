#!/usr/bin/env python3
"""Run the full river content pipeline over a batch of boards.

For each board in the batch spec: solve with the locked solver, INDEPENDENTLY
verify exploitability (best-response Δ must match the solver and stay under the
threshold — the batch fails closed otherwise), normalize to exact units, build a
SolverExport, and import an `unverifiedDraft` pack. Writes packs + `.sha256`
sidecars and a batch report atomically-ish per board.

Every board must pass the independent check; a solver whose self-report can't be
reproduced from scratch never becomes content.
"""

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gen = _load("generate_river", HERE / "generate-river.py")
ver = _load("verify_river", HERE / "verify-river-exploitability.py")
nrm = _load("normalize_river", HERE / "normalize-river.py")
exp = _load("build_river_export", HERE / "build-river-export.py")


def board_to_streets(board: str):
    return board[0:6], board[6:8], board[8:10]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run the river content pipeline over a board batch")
    parser.add_argument("--batch", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--strategy-import", required=True)
    parser.add_argument("--source-lock", default=str(HERE / "source-lock.json"))
    parser.add_argument("--dest", required=True, help="destination dir for packs")
    parser.add_argument("--max-exploit-fraction", type=float, default=0.01)
    parser.add_argument("--tolerance-fraction", type=float, default=0.002)
    parser.add_argument("--cache-dir", default=None)
    args = parser.parse_args(argv)

    batch = json.loads(Path(args.batch).read_text(encoding="utf-8"))
    lock = json.loads(Path(args.source_lock).read_text(encoding="utf-8"))
    cache_dir = Path(args.cache_dir) if args.cache_dir else Path(tempfile.gettempdir()) / "pokerhelper-postflop-cache"

    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)
    report = []

    for entry in batch["boards"]:
        board = entry["board"]
        flop, turn, river = board_to_streets(board)
        spot = {
            "oopRange": batch["oopRange"], "ipRange": batch["ipRange"],
            "flop": flop, "turn": turn, "river": river,
            "startingPotChips": batch["startingPotChips"],
            "effectiveStackChips": batch["effectiveStackChips"],
            "betSizes": batch["betSizes"], "raiseSizes": batch["raiseSizes"],
            "maxIterations": batch["maxIterations"],
            "targetExploitabilityFraction": batch["targetExploitabilityFraction"],
        }

        tree = gen.solve_river(spot, lock=lock, cache_dir=cache_dir)
        with tempfile.NamedTemporaryFile("w", suffix=".tree.json", delete=False) as tf:
            json.dump(tree, tf)
            tree_path = tf.name

        check = ver.run(Path(tree_path), args.max_exploit_fraction, args.tolerance_fraction)
        if not check["matches"] or not check["withinThreshold"]:
            raise SystemExit(
                f"FAIL {entry['id']}: independent check failed "
                f"(solver {check['solverExploitability']:.4f}, independent "
                f"{check['independentExploitability']:.4f}, Δ {check['delta']:.4f})"
            )

        snapshot = nrm.normalize(tree)
        export = exp.build_export(snapshot, lock["commit"], args.content_version)
        with tempfile.NamedTemporaryFile("w", suffix=".export.json", delete=False) as ef:
            json.dump(export, ef, ensure_ascii=False)
            export_path = ef.name

        pack_path = dest / f"{entry['id']}.json"
        result = subprocess.run(
            [args.strategy_import, "--export", export_path,
             "--content-version", args.content_version,
             "--review-status", "unverifiedDraft", "--origin", "solver",
             "--output", str(pack_path)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise SystemExit(f"FAIL {entry['id']}: strategy-import: {result.stderr.strip()}")

        import hashlib
        digest = hashlib.sha256(pack_path.read_bytes()).hexdigest()
        (pack_path.with_suffix(".sha256")).write_text(digest + "\n", encoding="utf-8")

        report.append({
            "id": entry["id"], "board": board,
            "solverExploitabilityChips": check["solverExploitability"],
            "independentExploitabilityChips": check["independentExploitability"],
            "deltaChips": check["delta"],
            "oopCells": len(snapshot["rangeCells"]),
            "packSHA256": digest,
        })
        print(f"OK {entry['id']}: expl {check['solverExploitability']:.4f} chips "
              f"(indep Δ {check['delta']:.4f}), {len(snapshot['rangeCells'])} cells")

    (dest / "batch-report.json").write_text(
        json.dumps({"batchId": batch["batchId"], "contentVersion": args.content_version,
                    "line": batch["line"], "boards": report}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    print(f"batch complete: {len(report)} river packs -> {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
