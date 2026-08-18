#!/usr/bin/env python3
"""Run the from-flop (Batch B) river pipeline over a batch of betting-line spots.

For each spot: solve FROM THE FLOP, navigate the betting line to the river node,
INDEPENDENTLY verify the river subtree is best-response given its extracted
(narrowed) ranges (fails closed unless within threshold), normalize, export, and
import an `unverifiedDraft` pack. Writes packs + `.sha256` + a batch report.

Partial-independence: the earlier-street convergence is the solver's self-report
(full-game exploitability), disclosed on the content. Each spot is a heavy flop
solve (~minutes).
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


genflop = _load("generate_river_from_flop", HERE / "generate-river-from-flop.py")
ver = _load("verify_river", HERE / "verify-river-exploitability.py")
nrm = _load("normalize_river", HERE / "normalize-river.py")
exp = _load("build_river_export", HERE / "build-river-export.py")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run the from-flop river pipeline over a batch")
    parser.add_argument("--batch", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--strategy-import", required=True)
    parser.add_argument("--source-lock", default=str(HERE / "source-lock.json"))
    parser.add_argument("--dest", required=True)
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

    for entry in batch["spots"]:
        spot = {
            "oopRange": batch["oopRange"], "ipRange": batch["ipRange"],
            "flop": entry["flop"], "line": entry["line"],
            "startingPotChips": batch["startingPotChips"],
            "effectiveStackChips": batch["effectiveStackChips"],
            "betSizes": batch["betSizes"], "raiseSizes": batch["raiseSizes"],
            "maxIterations": batch["maxIterations"],
            "targetExploitabilityFraction": batch["targetExploitabilityFraction"],
        }

        tree = genflop.solve_from_flop(spot, lock=lock, cache_dir=cache_dir)
        with tempfile.NamedTemporaryFile("w", suffix=".tree.json", delete=False) as tf:
            json.dump(tree, tf)
            tree_path = tf.name

        check = ver.run(Path(tree_path), args.max_exploit_fraction, args.tolerance_fraction)
        if not check["withinThreshold"]:
            raise SystemExit(
                f"FAIL {entry['id']}: independent river-subtree exploitability "
                f"{check['independentExploitability']:.4f} exceeds threshold {check['threshold']:.4f}"
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

        digest = hashlib.sha256(pack_path.read_bytes()).hexdigest()
        (pack_path.with_suffix(".sha256")).write_text(digest + "\n", encoding="utf-8")

        report.append({
            "id": entry["id"], "board": tree["board"], "line": entry["line"],
            "riverPotChips": tree["riverPotChips"],
            "fullGameExploitabilityChips": tree["fullGameExploitabilityChips"],
            "independentRiverSubtreeExploitabilityChips": check["independentExploitability"],
            "reachingCells": len(snapshot["rangeCells"]),
            "packSHA256": digest,
        })
        print(f"OK {entry['id']} {tree['board']}: river-subtree indep "
              f"{check['independentExploitability']:.3f} chips ({len(snapshot['rangeCells'])} reaching cells)")

    (dest / "batch-report.json").write_text(
        json.dumps({"batchId": batch["batchId"], "contentVersion": args.content_version,
                    "trustModel": "partial-independence (river subtree BR given ranges; earlier streets solver-self-reported + byte-reproducible)",
                    "spots": report}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    print(f"batch complete: {len(report)} betting-line river packs -> {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
