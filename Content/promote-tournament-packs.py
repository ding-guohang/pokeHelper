#!/usr/bin/env python3
"""Promote unverified HU push/fold packs to `reviewed` after a named human sign-off.

Hardened design (review 2026-08-14):

- reviewed content is produced by re-labeling the golden `unverifiedDraft`
  baseline in place — only the manifest changes — so no tool ever mints reviewed
  tournament content from raw exports (strategy-import refuses it), and the
  golden regression is exact by construction and re-asserted.
- Evidence is MEASURED here, not trusted from the review JSON: the independent
  equity recompute and exploitability cross-check are actually run against the
  current content, their worst-case values are read back, non-finite values are
  rejected, and both must meet the thresholds.
- The baseline is verified to be the committed golden batch (pack SHA-256 vs
  golden-manifest), the batch must be exactly 1–20BB, and the new content
  version must differ from the baseline's. The promotion record binds the
  baseline pack hashes, the evidence artifact hashes, and the measured values.

Fails closed, writing nothing, on any gap. Stdlib only.
"""

import argparse
import hashlib
import importlib.util
import json
from datetime import datetime
from pathlib import Path
import shutil
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TOURN = HERE / "tournament"
DEPTHS = range(1, 21)
EQUITY_DELTA_MAX = 1e-6
EXPLOITABILITY_MAX_BB = 0.02


class PromotionError(RuntimeError):
    pass


def _load(module_name, path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _finite(x) -> bool:
    return isinstance(x, (int, float)) and x == x and x not in (float("inf"), float("-inf"))


def pack_name(depth: int) -> str:
    return f"tourn-hu-chip-ev-noante-{depth:02d}bb.json"


def validate_review_record(record: dict):
    """Structural sign-off only: reviewer, ISO8601 time, explicit approval.
    Evidence is measured separately, not taken from the record."""
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


def default_evidence_runner(normalized_dir: Path, equity_path: Path, source_lock: dict) -> dict:
    """Actually run the independent checks and return their measured worst-case
    values (never trusts self-reported numbers)."""
    equities = _load("verify_equities", TOURN / "verify-equities.py")
    crosscheck = _load("cross_check", TOURN / "cross-check-exploitability.py")
    _rows, equity_worst = equities.run(Path(equity_path), source_lock, EQUITY_DELTA_MAX)
    xc_rows = crosscheck.run(Path(normalized_dir), Path(equity_path), source_lock)
    exploit_worst = max(r["totalExploitabilityBB"] for r in xc_rows)
    return {"equityMaxDelta": equity_worst, "exploitabilityMaxBB": exploit_worst}


def _check_evidence(measured: dict):
    eq = measured.get("equityMaxDelta")
    ex = measured.get("exploitabilityMaxBB")
    if not _finite(eq) or eq > EQUITY_DELTA_MAX:
        raise PromotionError(f"independent equity recompute failed: max delta {eq!r} > {EQUITY_DELTA_MAX}")
    if not _finite(ex) or ex > EXPLOITABILITY_MAX_BB:
        raise PromotionError(f"exploitability cross-check failed: {ex!r} > {EXPLOITABILITY_MAX_BB} BB")


def _verify_baseline_is_golden(baseline_dir: Path, golden_manifest: dict):
    by_depth = {d["depth"]: d for d in golden_manifest["depths"]}
    for depth in DEPTHS:
        pack = baseline_dir / pack_name(depth)
        if not pack.is_file():
            raise PromotionError(f"baseline missing {pack.name} (batch must be exactly 1-20BB)")
        expected = by_depth.get(depth, {}).get("packSHA256")
        actual = _sha256(pack)
        if expected != actual:
            raise PromotionError(f"baseline {pack.name} does not match the committed golden (sha256)")


def _strategy_only(pack: dict) -> str:
    p = dict(pack)
    p.pop("manifest", None)
    return json.dumps(p, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def promote(baseline_dir, destination, content_version, review_record, *,
            golden_manifest, normalized_dir, equity_path, source_lock,
            evidence_runner=default_evidence_runner):
    reviewer, reviewed_at = validate_review_record(review_record)
    baseline_dir, destination = Path(baseline_dir), Path(destination)

    _verify_baseline_is_golden(baseline_dir, golden_manifest)

    baseline_version = json.loads((baseline_dir / pack_name(1)).read_text())["manifest"]["contentVersion"]
    if content_version == baseline_version:
        raise PromotionError(f"new content version must differ from baseline {baseline_version!r}")

    measured = evidence_runner(Path(normalized_dir), Path(equity_path), source_lock)
    _check_evidence(measured)

    staging = Path(tempfile.mkdtemp(prefix="tourn-reviewed-"))
    try:
        published, pack_hashes = [], {}
        for depth in DEPTHS:
            name = pack_name(depth)
            baseline_pack = json.loads((baseline_dir / name).read_text(encoding="utf-8"))
            reviewed_pack = json.loads(json.dumps(baseline_pack))  # deep copy
            manifest = reviewed_pack["manifest"]
            manifest["reviewStatus"] = "reviewed"
            manifest["reviewedBy"] = reviewer
            manifest["reviewedAt"] = reviewed_at
            manifest["contentVersion"] = content_version
            # Re-label only: strategy must be byte-identical to the baseline.
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
            "evidenceArtifacts": {
                "goldenManifestSHA256": _sha256(TOURN / "golden-manifest.json"),
                "equityVerifyReportSHA256": _sha256(TOURN / "equity-verify-report.md"),
                "crossCheckReportSHA256": _sha256(TOURN / "cross-check-report.md"),
            },
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
    parser = argparse.ArgumentParser(description="Promote reviewed tournament packs")
    parser.add_argument("--baseline", required=True, help="committed golden unverifiedDraft packs")
    parser.add_argument("--destination", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--review-record", required=True)
    parser.add_argument("--golden-manifest", default=str(TOURN / "golden-manifest.json"))
    parser.add_argument("--normalized", default="Content/tournament-normalized")
    parser.add_argument("--equity", required=True, help="verified heads_up_pre_flop_equity.bin")
    parser.add_argument("--source-lock", default=str(TOURN / "source-lock.json"))
    args = parser.parse_args(argv)

    record = json.loads(Path(args.review_record).read_text(encoding="utf-8"))
    golden = json.loads(Path(args.golden_manifest).read_text(encoding="utf-8"))
    lock = json.loads(Path(args.source_lock).read_text(encoding="utf-8"))
    names = promote(
        args.baseline, args.destination, args.content_version, record,
        golden_manifest=golden, normalized_dir=args.normalized,
        equity_path=args.equity, source_lock=lock,
    )
    print(f"promoted {len(names)} packs to reviewed at {args.destination}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PromotionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
