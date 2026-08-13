#!/usr/bin/env python3
"""Build the golden manifest binding locked source, normalized inputs, exports,
and packs to their SHA-256 hashes plus convergence and coverage.

Deterministic: sorted keys, sorted depth array, no wall clock. The reproducibility
gate re-runs the pipeline and byte-compares against the tracked manifest.
"""

import argparse
import hashlib
import json
from pathlib import Path


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_manifest(root: Path, content_version: str) -> dict:
    root = Path(root)
    lock = json.loads((root / "Content/tournament/source-lock.json").read_text(encoding="utf-8"))
    normalized_dir = root / "Content/tournament-normalized"
    exports_dir = root / "Content/exports"
    packs_dir = root / "Content/packs"

    depths = []
    for depth in range(1, 21):
        name = f"hu-chip-ev-noante-{depth:02d}bb.json"
        export_name = f"tourn-hu-chip-ev-noante-{depth:02d}bb.json"
        normalized = json.loads((normalized_dir / name).read_text(encoding="utf-8"))
        tables = normalized["tables"]
        depths.append({
            "depth": depth,
            "iterations": normalized["iterations"],
            "nashConvBB": normalized["nashConvBB"],
            "exploitabilityBB": normalized["exploitabilityBB"],
            "openJamRows": len(tables["openJam"]),
            "callJamRows": len(tables.get("callJam", [])),
            "normalizedSHA256": _sha256(normalized_dir / name),
            "exportSHA256": _sha256(exports_dir / export_name),
            "packSHA256": _sha256(packs_dir / export_name),
        })

    return {
        "contentVersion": content_version,
        "source": {
            "repository": lock["repository"],
            "commit": lock["commit"],
            "licenseSpdx": lock["license"]["spdx"],
            "lockedHashes": {e["path"]: e["sha256"] for e in lock["files"]},
        },
        "coverage": {
            "depths": [d["depth"] for d in depths],
            "tableCount": sum(1 + (1 if d["callJamRows"] else 0) for d in depths),
            "rowCount": sum(d["openJamRows"] + d["callJamRows"] for d in depths),
            "maxNashConvBB": max(d["nashConvBB"] for d in depths),
        },
        "depths": depths,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Build the tournament golden manifest")
    parser.add_argument("--root", default=".")
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    manifest = build_manifest(Path(args.root).resolve(), args.content_version)
    Path(args.output).write_text(
        json.dumps(manifest, sort_keys=True, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote golden manifest for {len(manifest['depths'])} depths")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
