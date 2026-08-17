#!/usr/bin/env python3
"""Promote the unverifiedDraft river packs to `reviewed` after a named human sign-off.

Hardened, mirroring the push/fold promotion:

- reviewed content is produced by RE-LABELING the committed unverifiedDraft packs
  in place — only the manifest changes — so the strategy is byte-identical to the
  baseline by construction and re-asserted.
- Evidence is MEASURED here, not trusted: the byte-reproducibility + independent
  best-response gate (verify-postflop-river.sh) is actually run and must pass.
- The baseline is verified to equal the committed golden batch (pack SHA-256 vs
  batch-report.json), and the new content version must differ from the baseline's.
- Fails closed, writing nothing, on any gap. Stdlib only.
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

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
GATE = ROOT / "scripts" / "verify-postflop-river.sh"


class PromotionError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_review_record(record: dict):
    """Structural sign-off only: reviewer, ISO8601 time, explicit approval."""
    missing = []
    reviewer = (record.get("reviewer") or "").strip()
    if not reviewer:
        missing.append("reviewer (具名审核人)")
    reviewed_at = (record.get("reviewedAt") or "").strip()
    if not reviewed_at:
        missing.append("reviewedAt (ISO8601)")
    else:
        try:
            datetime.fromisoformat(reviewed_at.replace("Z", "+00:00"))
        except ValueError:
            missing.append("reviewedAt must be ISO8601")
    if record.get("decision") != "approved":
        missing.append("decision == 'approved'")
    if missing:
        raise PromotionError("review record incomplete: " + "; ".join(missing))
    return reviewer, reviewed_at


def default_evidence_runner() -> dict:
    """Actually run the byte-reproducibility + independent best-response gate."""
    result = subprocess.run(["bash", str(GATE)], capture_output=True, text=True)
    if result.returncode != 0:
        raise PromotionError(
            "evidence gate (verify-postflop-river.sh) failed:\n" + result.stdout[-2000:] + result.stderr[-2000:]
        )
    return {"gate": "verify-postflop-river.sh", "passed": True}


def _verify_baseline_is_golden(baseline_dir: Path, report: dict):
    for board in report["boards"]:
        pack = baseline_dir / f"{board['id']}.json"
        if not pack.is_file():
            raise PromotionError(f"baseline missing {pack.name}")
        if _sha256(pack) != board["packSHA256"]:
            raise PromotionError(f"baseline {pack.name} does not match the committed batch report (sha256)")


def _strategy_only(pack: dict) -> str:
    p = dict(pack)
    p.pop("manifest", None)
    return json.dumps(p, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def promote(baseline_dir, destination, content_version, review_record, *,
            evidence_runner=default_evidence_runner):
    reviewer, reviewed_at = validate_review_record(review_record)
    baseline_dir, destination = Path(baseline_dir), Path(destination)

    report = json.loads((baseline_dir / "batch-report.json").read_text(encoding="utf-8"))
    _verify_baseline_is_golden(baseline_dir, report)

    ids = [b["id"] for b in report["boards"]]
    baseline_version = json.loads((baseline_dir / f"{ids[0]}.json").read_text())["manifest"]["contentVersion"]
    if content_version == baseline_version:
        raise PromotionError(f"new content version must differ from baseline {baseline_version!r}")

    measured = evidence_runner()  # runs the gate; raises on failure

    staging = Path(tempfile.mkdtemp(prefix="river-reviewed-"))
    try:
        published, pack_hashes = [], {}
        for board_id in ids:
            name = f"{board_id}.json"
            baseline_pack = json.loads((baseline_dir / name).read_text(encoding="utf-8"))
            reviewed_pack = json.loads(json.dumps(baseline_pack))  # deep copy
            manifest = reviewed_pack["manifest"]
            manifest["reviewStatus"] = "reviewed"
            manifest["reviewedBy"] = reviewer
            manifest["reviewedAt"] = reviewed_at
            manifest["contentVersion"] = content_version
            if _strategy_only(reviewed_pack) != _strategy_only(baseline_pack):
                raise PromotionError(f"{name}: promotion altered strategy content")
            out = staging / name
            out.write_text(json.dumps(reviewed_pack, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            (out.with_suffix(".sha256")).write_text(_sha256(out) + "\n", encoding="utf-8")
            published.append(name)
            pack_hashes[name] = {"baseline": _sha256(baseline_dir / name), "reviewed": _sha256(out)}

        record = {
            "reviewer": reviewer,
            "reviewedAt": reviewed_at,
            "contentVersion": content_version,
            "baselineContentVersion": baseline_version,
            "origin": "solver",
            "reviewStatus": "reviewed",
            "measuredEvidence": measured,
            "evidenceArtifacts": {"batchReportSHA256": _sha256(baseline_dir / "batch-report.json")},
            "packs": pack_hashes,
        }
        (staging / "promotion-record.json").write_text(
            json.dumps(record, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(destination))
        return sorted(published)
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Promote reviewed river packs after a named sign-off")
    parser.add_argument("--baseline", required=True, help="committed unverifiedDraft river packs dir")
    parser.add_argument("--destination", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--review-record", required=True)
    args = parser.parse_args(argv)

    record = json.loads(Path(args.review_record).read_text(encoding="utf-8"))
    names = promote(args.baseline, args.destination, args.content_version, record)
    print(f"promoted {len(names)} river packs to reviewed at {args.destination}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PromotionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
