"""Promotion tests: an incomplete review record is refused; a complete one
produces reviewed packs whose strategy is byte-identical to the unverified
baseline (promotion re-labels, never edits)."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SPEC = importlib.util.spec_from_file_location(
    "promote_tournament_packs", _ROOT / "Content" / "promote-tournament-packs.py"
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
promote = _MOD.promote
validate_review_record = _MOD.validate_review_record
PromotionError = _MOD.PromotionError

STRATEGY_IMPORT = _ROOT / "Packages/StrategyTooling/.build/release/strategy-import"
EXPORTS = _ROOT / "Content/exports"
BASELINE = _ROOT / "Content/packs"


def complete_record():
    return {
        "reviewer": "Reviewer Name",
        "reviewedAt": "2026-08-14T00:00:00Z",
        "decision": "approved",
        "evidence": {"equityMaxDelta": 0.0, "exploitabilityMaxBB": 0.0, "reproducible": True},
    }


class PromotionRecordTests(unittest.TestCase):
    def test_missing_reviewer_is_refused(self):
        r = complete_record(); r["reviewer"] = ""
        with self.assertRaisesRegex(PromotionError, "reviewer"):
            validate_review_record(r)

    def test_unapproved_decision_is_refused(self):
        r = complete_record(); r["decision"] = "needs-revision"
        with self.assertRaisesRegex(PromotionError, "approved"):
            validate_review_record(r)

    def test_failing_evidence_is_refused(self):
        r = complete_record(); r["evidence"]["exploitabilityMaxBB"] = 0.5
        with self.assertRaisesRegex(PromotionError, "exploitability"):
            validate_review_record(r)

    def test_missing_reproducibility_is_refused(self):
        r = complete_record(); r["evidence"]["reproducible"] = False
        with self.assertRaisesRegex(PromotionError, "reproducible"):
            validate_review_record(r)

    def test_complete_record_passes_validation(self):
        reviewer, reviewed_at = validate_review_record(complete_record())
        self.assertEqual(reviewer, "Reviewer Name")
        self.assertEqual(reviewed_at, "2026-08-14T00:00:00Z")


@unittest.skipUnless(STRATEGY_IMPORT.exists() and EXPORTS.exists() and BASELINE.exists(),
                     "requires built strategy-import + Content exports/packs")
class PromotionIntegrationTests(unittest.TestCase):
    def test_promotion_preserves_strategy_and_relabels_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            record_path = Path(tmp) / "record.json"
            record_path.write_text(json.dumps(complete_record()), encoding="utf-8")
            dest = Path(tmp) / "reviewed"
            names = promote(EXPORTS, BASELINE, dest, "2026.08.14-hu-pf.reviewed.1",
                            complete_record(), str(STRATEGY_IMPORT))
            self.assertEqual(len(names), 20)

            # Strategy identical to the unverified baseline; only manifest changed.
            for name in names:
                base = json.loads((BASELINE / name).read_text())
                rev = json.loads((dest / name).read_text())
                base.pop("manifest"); rev_manifest = rev.pop("manifest")
                self.assertEqual(base, rev, f"{name} strategy changed under promotion")
                self.assertEqual(rev_manifest["reviewStatus"], "reviewed")
                self.assertEqual(rev_manifest["origin"], "solver")
                self.assertEqual(rev_manifest["reviewedBy"], "Reviewer Name")
                self.assertEqual(rev_manifest["contentVersion"], "2026.08.14-hu-pf.reviewed.1")
            self.assertTrue((dest / "promotion-record.json").is_file())

    def test_incomplete_record_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "reviewed"
            bad = complete_record(); bad["reviewer"] = ""
            with self.assertRaises(PromotionError):
                promote(EXPORTS, BASELINE, dest, "x", bad, str(STRATEGY_IMPORT))
            self.assertFalse(dest.exists())


if __name__ == "__main__":
    unittest.main()
