"""Promotion tests (hardened): structural sign-off, measured-evidence gating,
baseline-is-golden, new-version, and re-label-only (strategy preserved)."""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SPEC = importlib.util.spec_from_file_location(
    "promote_tournament_packs", _ROOT / "Content" / "promote-tournament-packs.py")
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
promote = _MOD.promote
validate_review_record = _MOD.validate_review_record
PromotionError = _MOD.PromotionError

TOURN = _ROOT / "Content" / "tournament"
BASELINE = _ROOT / "Content" / "packs"
NORMALIZED = _ROOT / "Content" / "tournament-normalized"
GOLDEN_PATH = TOURN / "golden-manifest.json"
LOCK_PATH = TOURN / "source-lock.json"
BASELINE_VERSION = "2026.08.13-hu-pf.1"


def record(**over):
    r = {"reviewer": "Reviewer Name", "reviewedAt": "2026-08-14T00:00:00Z", "decision": "approved"}
    r.update(over)
    return r


def ok_evidence(*_a, **_k):
    return {"equityMaxDelta": 0.0, "exploitabilityMaxBB": 0.0}


class ReviewRecordTests(unittest.TestCase):
    def test_missing_reviewer_refused(self):
        with self.assertRaisesRegex(PromotionError, "reviewer"):
            validate_review_record(record(reviewer=""))

    def test_unapproved_refused(self):
        with self.assertRaisesRegex(PromotionError, "approved"):
            validate_review_record(record(decision="needs-revision"))

    def test_bad_timestamp_refused(self):
        with self.assertRaisesRegex(PromotionError, "ISO8601"):
            validate_review_record(record(reviewedAt="yesterday"))


@unittest.skipUnless(BASELINE.exists() and GOLDEN_PATH.exists(), "requires committed golden batch")
class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.golden = json.loads(GOLDEN_PATH.read_text())
        self.lock = json.loads(LOCK_PATH.read_text())

    def _promote(self, dest, version, rec=None, evidence=ok_evidence, golden=None):
        return promote(BASELINE, dest, version, rec or record(),
                       golden_manifest=golden or self.golden, normalized_dir=NORMALIZED,
                       equity_path="unused-by-stub", source_lock=self.lock, evidence_runner=evidence)

    def test_relabel_only_and_preserves_strategy(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "reviewed"
            names = self._promote(dest, "2026.08.14-hu-pf.reviewed.1")
            self.assertEqual(len(names), 20)
            for name in names:
                base = json.loads((BASELINE / name).read_text())
                rev = json.loads((dest / name).read_text())
                base.pop("manifest"); m = rev.pop("manifest")
                self.assertEqual(base, rev, f"{name} strategy changed")
                self.assertEqual(m["reviewStatus"], "reviewed")
                self.assertEqual(m["origin"], "solver")
                self.assertEqual(m["reviewedBy"], "Reviewer Name")
                self.assertEqual(m["contentVersion"], "2026.08.14-hu-pf.reviewed.1")
            self.assertTrue((dest / "promotion-record.json").is_file())

    def test_failing_exploitability_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "reviewed"
            bad = lambda *a, **k: {"equityMaxDelta": 0.0, "exploitabilityMaxBB": 0.5}
            with self.assertRaisesRegex(PromotionError, "exploitability"):
                self._promote(dest, "2026.08.14-hu-pf.reviewed.1", evidence=bad)
            self.assertFalse(dest.exists())

    def test_nan_evidence_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = lambda *a, **k: {"equityMaxDelta": float("nan"), "exploitabilityMaxBB": 0.0}
            with self.assertRaisesRegex(PromotionError, "equity"):
                self._promote(Path(tmp) / "r", "2026.08.14-hu-pf.reviewed.1", evidence=bad)

    def test_same_content_version_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(PromotionError, "must differ"):
                self._promote(Path(tmp) / "r", BASELINE_VERSION)

    def test_baseline_not_golden_refused(self):
        tampered = json.loads(GOLDEN_PATH.read_text())
        tampered["depths"][0]["packSHA256"] = "0" * 64
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(PromotionError, "committed golden"):
                self._promote(Path(tmp) / "r", "2026.08.14-hu-pf.reviewed.1", golden=tampered)

    def test_incomplete_record_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "reviewed"
            with self.assertRaises(PromotionError):
                self._promote(dest, "2026.08.14-hu-pf.reviewed.1", rec=record(reviewer=""))
            self.assertFalse(dest.exists())


if __name__ == "__main__":
    unittest.main()
