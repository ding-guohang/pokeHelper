#!/usr/bin/env python3
"""Promote unverified HU push/fold packs to `reviewed` after a named human sign-off.

This is the deliberate, evidence-gated counterpart to import-tournament-packs.py.
It refuses to promote unless a completed review record names a reviewer, a review
timestamp, an explicit approval, and the three objective evidence checks
(independent equity recompute, exploitability cross-check, byte-reproducibility).
It then re-imports the SAME exports as `reviewed` with a NEW content version and
`origin=solver` (human review raises confidence but does not change where the
numbers came from), and runs a golden regression: the reviewed packs' strategy
(range cells, options, explanations) must be byte-identical to the unverified
baseline — promotion re-labels content, it must never alter a single frequency
or EV.

Stdlib only. Produces reviewed packs + checksums + a promotion record; writes
nothing on any failure.
"""

import argparse
import hashlib
import json
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

EXPORT_GLOB = "tourn-hu-chip-ev-noante-*.json"
EQUITY_DELTA_MAX = 1e-6
EXPLOITABILITY_MAX_BB = 0.02


class PromotionError(RuntimeError):
    pass


def validate_review_record(record: dict):
    """Return (reviewer, reviewed_at) or raise listing every missing item."""
    missing = []
    reviewer = (record.get("reviewer") or "").strip()
    if not reviewer:
        missing.append("reviewer (具名审核人)")
    reviewed_at = (record.get("reviewedAt") or "").strip()
    if not reviewed_at:
        missing.append("reviewedAt (ISO8601 审核时间)")
    else:
        try:
            datetime.fromisoformat(reviewed_at.replace("Z", "+00:00"))
        except ValueError:
            missing.append("reviewedAt must be ISO8601")
    if record.get("decision") != "approved":
        missing.append("decision == 'approved'")

    evidence = record.get("evidence") or {}
    eq = evidence.get("equityMaxDelta")
    if eq is None or eq > EQUITY_DELTA_MAX:
        missing.append(f"evidence.equityMaxDelta <= {EQUITY_DELTA_MAX} (独立 equity 重算)")
    ex = evidence.get("exploitabilityMaxBB")
    if ex is None or ex > EXPLOITABILITY_MAX_BB:
        missing.append(f"evidence.exploitabilityMaxBB <= {EXPLOITABILITY_MAX_BB} (可利用度交叉核对)")
    if not evidence.get("reproducible"):
        missing.append("evidence.reproducible == true (逐位可复现)")

    if missing:
        raise PromotionError("review record incomplete: " + "; ".join(missing))
    return reviewer, reviewed_at


def _strategy_only(pack_path: Path) -> str:
    """Canonical serialization of a pack with its manifest removed, so a diff
    reflects only strategy content (range cells, options, explanations)."""
    pack = json.loads(pack_path.read_text(encoding="utf-8"))
    pack.pop("manifest", None)
    return json.dumps(pack, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def promote(exports_dir, baseline_dir, destination, content_version, review_record, strategy_import):
    reviewer, reviewed_at = validate_review_record(review_record)
    exports_dir, baseline_dir, destination = Path(exports_dir), Path(baseline_dir), Path(destination)
    exports = sorted(exports_dir.glob(EXPORT_GLOB))
    if not exports:
        raise PromotionError(f"no exports matching {EXPORT_GLOB} in {exports_dir}")

    staging = Path(tempfile.mkdtemp(prefix="tourn-reviewed-"))
    try:
        for export in exports:
            pack = staging / export.name
            subprocess.run([
                str(strategy_import),
                "--export", str(export),
                "--content-version", content_version,
                "--review-status", "reviewed",
                "--origin", "solver",
                "--reviewed-by", reviewer,
                "--reviewed-at", reviewed_at,
                "--output", str(pack),
            ], check=True, capture_output=True, text=True)

        # Golden regression: reviewed content must equal the unverified baseline
        # in everything but the manifest.
        published = []
        for export in exports:
            reviewed_pack = staging / export.name
            baseline_pack = baseline_dir / export.name
            if not baseline_pack.is_file():
                raise PromotionError(f"no baseline pack to compare: {baseline_pack.name}")
            if _strategy_only(reviewed_pack) != _strategy_only(baseline_pack):
                raise PromotionError(
                    f"promotion changed strategy content in {export.name}; review may only re-label, not edit"
                )
            manifest = json.loads(reviewed_pack.read_text(encoding="utf-8"))["manifest"]
            if manifest.get("reviewStatus") != "reviewed" or not manifest.get("reviewedBy"):
                raise PromotionError(f"{export.name} did not come out reviewed with a reviewer")
            (reviewed_pack.with_suffix(".sha256")).write_text(_sha256(reviewed_pack) + "\n", encoding="utf-8")
            published.append(export.name)

        record = {
            "reviewer": reviewer,
            "reviewedAt": reviewed_at,
            "contentVersion": content_version,
            "origin": "solver",
            "reviewStatus": "reviewed",
            "packs": sorted(published),
            "evidence": review_record.get("evidence"),
        }
        (staging / "promotion-record.json").write_text(
            json.dumps(record, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(destination))
        return sorted(published)
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Promote reviewed tournament packs")
    parser.add_argument("--exports", required=True)
    parser.add_argument("--baseline", required=True, help="unverifiedDraft packs to golden-check against")
    parser.add_argument("--destination", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--review-record", required=True, help="JSON: reviewer, reviewedAt, decision, evidence")
    parser.add_argument("--strategy-import", required=True)
    args = parser.parse_args(argv)

    record = json.loads(Path(args.review_record).read_text(encoding="utf-8"))
    names = promote(args.exports, args.baseline, args.destination, args.content_version, record, args.strategy_import)
    print(f"promoted {len(names)} packs to reviewed at {args.destination}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PromotionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
