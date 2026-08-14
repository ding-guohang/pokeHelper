#!/usr/bin/env python3
"""Solve a river spot with the locked b-inary/postflop-solver and emit its raw
OOP root-node output as JSON.

Provenance discipline mirrors the HU push/fold generator: a full checkout is
taken at the locked commit and EVERY file listed in source-lock.json is
re-verified on EVERY call (no marker fast-path); the export driver is added to a
COPY of the pristine checkout so the locked source is never mutated; and the
Rust toolchain is checked to match the lock exactly before building.

The driver is built without the `bincode` feature and with the
`dangerous_implicit_autorefs` lint allowed (see source-lock.json buildRecipe);
neither touches locked source.

This tool only produces the solver's raw numbers (chips / probabilities) plus
the measured exploitability. Conversion to exact centi-BB / milli-BB / basis
points, and any review/promotion, happen in later stages.
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

HERE = Path(__file__).resolve().parent
DRIVER = HERE / "solver-bin" / "river_solve.rs"


class SolverError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _cargo_env() -> dict:
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.cargo' / 'bin'}:{env.get('PATH', '')}"
    return env


def verify_toolchain(lock: dict) -> None:
    """Require the exact locked rustc; a different compiler can change codegen
    and is exactly what the lock exists to pin."""
    want = lock["rustVersion"]
    out = subprocess.run(["rustc", "--version"], capture_output=True, text=True, env=_cargo_env())
    if out.returncode != 0:
        raise SolverError("rustc not found on PATH")
    # "rustc 1.97.1 (….)" -> "1.97.1"
    got = out.stdout.split()[1] if len(out.stdout.split()) > 1 else ""
    if got != want:
        raise SolverError(f"rustc {got} != locked {want}")


def ensure_source(lock: dict, cache_dir: Path) -> Path:
    """Return a verified pristine checkout at the locked commit, cloning once but
    re-verifying every locked hash on every call. Fails closed on any drift."""
    commit = lock["commit"]
    repository = lock["repository"]
    crate = cache_dir / f"postflop-solver-{commit}"

    need_clone = True
    if (crate / ".git").is_dir():
        head = subprocess.run(["git", "-C", str(crate), "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip()
        need_clone = head != commit
    if need_clone:
        if crate.exists():
            shutil.rmtree(crate)
        cache_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--quiet", f"https://github.com/{repository}", str(crate)], check=True)
        subprocess.run(["git", "-C", str(crate), "checkout", "--quiet", commit], check=True)

    head = subprocess.run(["git", "-C", str(crate), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    if head != commit:
        raise SolverError(f"checkout HEAD {head} != locked commit {commit}")

    # Re-verify every locked input on every call — the cache is never trusted.
    for rel, digest in lock["files"].items():
        path = crate / rel
        if not path.is_file():
            raise SolverError(f"locked input missing from checkout: {rel}")
        actual = _sha256(path)
        if actual != digest:
            raise SolverError(f"locked input {rel} hash {actual} != {digest}")
    # LICENSE is also covered above via lock["files"]; assert the spdx record too.
    if lock["license"]["sha256"] != _sha256(crate / lock["license"]["path"]):
        raise SolverError("LICENSE hash != lock")
    return crate


def build_driver(crate: Path, cache_dir: Path, lock: dict) -> Path:
    """Copy the pristine crate to a build dir, add ONLY the driver bin, and build
    it per the locked recipe. The pristine checkout is never modified."""
    build = cache_dir / f"{crate.name}-build"
    if build.exists():
        shutil.rmtree(build)
    shutil.copytree(crate, build)
    (build / "src" / "bin").mkdir(parents=True, exist_ok=True)
    shutil.copy2(DRIVER, build / "src" / "bin" / "river_solve.rs")

    env = _cargo_env()
    env["RUSTFLAGS"] = lock["buildRecipe"]["rustflags"]
    subprocess.run(["cargo", *lock["buildRecipe"]["cargoArgs"]], cwd=build, check=True, env=env)
    binary = build / "target" / "release" / "river_solve"
    if not binary.is_file():
        raise SolverError("driver binary not produced")
    return binary


_BINARY_CACHE: dict = {}


def _driver_binary(lock: dict, cache_dir: Path) -> Path:
    key = str(cache_dir)
    if key not in _BINARY_CACHE:
        verify_toolchain(lock)
        crate = ensure_source(lock, cache_dir)  # re-verifies all locked hashes
        _BINARY_CACHE[key] = build_driver(crate, cache_dir, lock)
    return _BINARY_CACHE[key]


def solve_river(spot: dict, *, lock: dict, cache_dir: Path) -> dict:
    """Solve one river spot and return the driver's parsed JSON output."""
    binary = _driver_binary(lock, cache_dir)
    args = [
        str(binary),
        "--oop-range", spot["oopRange"],
        "--ip-range", spot["ipRange"],
        "--flop", spot["flop"],
        "--turn", spot["turn"],
        "--river", spot["river"],
        "--starting-pot-chips", str(spot["startingPotChips"]),
        "--effective-stack-chips", str(spot["effectiveStackChips"]),
        "--oop-bet-sizes", spot["oopBetSizes"],
        "--ip-bet-sizes", spot["ipBetSizes"],
        "--max-iterations", str(spot["maxIterations"]),
        "--target-exploitability-fraction", str(spot["targetExploitabilityFraction"]),
    ]
    out = subprocess.run(args, capture_output=True, text=True, env=_cargo_env())
    if out.returncode != 0:
        raise SolverError(f"river_solve failed: {out.stderr.strip()}")
    return json.loads(out.stdout)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Solve a river spot with the locked postflop solver")
    parser.add_argument("--source-lock", default=str(HERE / "source-lock.json"))
    parser.add_argument("--spot", required=True, help="path to a river spot spec JSON")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cache-dir", default=None)
    args = parser.parse_args(argv)

    lock = json.loads(Path(args.source_lock).read_text(encoding="utf-8"))
    spot = json.loads(Path(args.spot).read_text(encoding="utf-8"))
    cache_dir = Path(args.cache_dir) if args.cache_dir else Path(tempfile.gettempdir()) / "pokerhelper-postflop-cache"

    result = solve_river(spot, lock=lock, cache_dir=cache_dir)
    Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"solved {result['board']}: exploitability {result['exploitabilityChips']:.4f} chips, "
          f"{len(result['oopHands'])} OOP hands -> {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SolverError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
