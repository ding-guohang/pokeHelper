#!/usr/bin/env python3
"""Solve a spot FROM THE FLOP with the locked solver and emit the river decision
node reached by a betting line.

Reuses the hardened source machinery from generate-river.py (verify the exact
rustc, re-verify EVERY locked hash on every call, build in a COPY of the pristine
checkout) and only swaps in the `river_from_flop` driver bin. The output is the
narrowed-range river node (see river_from_flop.rs) that the from-flop pipeline
normalizes/exports.

Note: a flop solve is heavy (minutes, ~GB). RAYON_NUM_THREADS=1 is inherited from
generate-river's env for byte-reproducibility.
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import importlib.util

HERE = Path(__file__).resolve().parent
DRIVER = HERE / "solver-bin" / "river_from_flop.rs"

_spec = importlib.util.spec_from_file_location("generate_river", HERE / "generate-river.py")
_gr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gr)
SolverError = _gr.SolverError


def build_driver(crate: Path, cache_dir: Path, lock: dict) -> Path:
    """Copy the pristine crate to a build dir, add ONLY the from-flop driver bin,
    and build it per the locked recipe. The pristine checkout is never modified."""
    build = cache_dir / f"{crate.name}-build"
    if build.exists():
        shutil.rmtree(build)
    shutil.copytree(crate, build)
    (build / "src" / "bin").mkdir(parents=True, exist_ok=True)
    shutil.copy2(DRIVER, build / "src" / "bin" / "river_from_flop.rs")

    env = _gr._cargo_env()
    env["RUSTFLAGS"] = lock["buildRecipe"]["rustflags"]
    args = ["build", "--release", "--no-default-features", "--features", "rayon", "--bin", "river_from_flop"]
    subprocess.run(["cargo", *args], cwd=build, check=True, env=env)
    binary = build / "target" / "release" / "river_from_flop"
    if not binary.is_file():
        raise SolverError("river_from_flop binary not produced")
    return binary


_BINARY_CACHE: dict = {}


def _driver_binary(lock: dict, cache_dir: Path) -> Path:
    key = str(cache_dir)
    if key not in _BINARY_CACHE:
        _gr.verify_toolchain(lock)
        crate = _gr.ensure_source(lock, cache_dir)  # re-verifies all locked hashes
        _BINARY_CACHE[key] = build_driver(crate, cache_dir, lock)
    return _BINARY_CACHE[key]


def solve_from_flop(spot: dict, *, lock: dict, cache_dir: Path) -> dict:
    binary = _driver_binary(lock, cache_dir)
    args = [
        str(binary),
        "--oop-range", spot["oopRange"],
        "--ip-range", spot["ipRange"],
        "--flop", spot["flop"],
        "--starting-pot-chips", str(spot["startingPotChips"]),
        "--effective-stack-chips", str(spot["effectiveStackChips"]),
        "--bet-sizes", spot["betSizes"],
        "--raise-sizes", spot["raiseSizes"],
        "--max-iterations", str(spot["maxIterations"]),
        "--target-exploitability-fraction", str(spot["targetExploitabilityFraction"]),
        "--line", spot["line"],
    ]
    out = subprocess.run(args, capture_output=True, text=True, env=_gr._cargo_env())
    if out.returncode != 0:
        raise SolverError(f"river_from_flop failed: {out.stderr.strip()}")
    return json.loads(out.stdout)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Solve from the flop and emit a river node")
    parser.add_argument("--source-lock", default=str(HERE / "source-lock.json"))
    parser.add_argument("--spot", required=True, help="path to a from-flop river spot spec JSON")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cache-dir", default=None)
    args = parser.parse_args(argv)

    lock = json.loads(Path(args.source_lock).read_text(encoding="utf-8"))
    spot = json.loads(Path(args.spot).read_text(encoding="utf-8"))
    cache_dir = Path(args.cache_dir) if args.cache_dir else Path(tempfile.gettempdir()) / "pokerhelper-postflop-cache"

    result = solve_from_flop(spot, lock=lock, cache_dir=cache_dir)
    Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"solved-from-flop {result['board']} (line {result['line']}): "
          f"river pot {result['riverPotChips']}, full-game exploitability "
          f"{result['fullGameExploitabilityChips']:.4f} chips -> {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SolverError as error:
        print(f"FAIL: {error}", file=__import__("sys").stderr)
        raise SystemExit(1)
