"""Task 5 tests: a validated batch builds 20 exact-depth SolverExport files with
correct betting contexts; a partial batch writes nothing; output is
deterministic."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]

_VAL_SPEC = importlib.util.spec_from_file_location(
    "validate_hu_batch", _ROOT / "Content" / "tournament" / "validate_hu_batch.py"
)
_VAL = importlib.util.module_from_spec(_VAL_SPEC)
_VAL_SPEC.loader.exec_module(_VAL)
CANONICAL = _VAL.CANONICAL
snapshot_hash = _VAL._snapshot_hash

_BLD_SPEC = importlib.util.spec_from_file_location(
    "build_tournament_exports", _ROOT / "Content" / "build-tournament-exports.py"
)
_BLD = importlib.util.module_from_spec(_BLD_SPEC)
_BLD_SPEC.loader.exec_module(_BLD)
build_exports = _BLD.build_exports
BatchValidationError = _BLD.BatchValidationError


def make_normalized_doc(depth):
    def table(primary, fold_ev):
        return [{
            "handClass": hand,
            "actionWeightsBasisPoints": {primary: 6_000, "fold": 4_000},
            "actionEVsMilliBB": {primary: 120, "fold": fold_ev},
        } for hand in sorted(CANONICAL)]

    tables = {"openJam": table("allIn", -500)}
    if depth >= 2:
        tables["callJam"] = table("call", -1000)
    doc = {
        "effectiveBigBlinds": depth,
        "source": {"repository": "b-inary/poker-cfr", "commit": "a" * 40, "licenseSpdx": "BSD-2-Clause", "lockedHashes": {}},
        "configuration": {"nashConvThresholdBB": 0.001, "equilibrium": "chipEV"},
        "iterations": 10_000,
        "nashConvBB": 0.0001,
        "exploitabilityBB": 0.00005,
        "testOnly": False,
        "exportedAt": "2026-08-13T00:00:00Z",
        "tables": tables,
    }
    doc["snapshotSHA256"] = snapshot_hash(doc)
    return doc


def write_batch(root, drop=None):
    for depth in range(1, 21):
        doc = make_normalized_doc(depth)
        if drop is not None:
            drop(depth, doc)
            doc["snapshotSHA256"] = snapshot_hash(doc)
        (root / f"hu-chip-ev-noante-{depth:02d}bb.json").write_text(
            json.dumps(doc, sort_keys=True, indent=2) + "\n", encoding="utf-8"
        )


class BuildTournamentExportsTests(unittest.TestCase):
    def test_each_depth_builds_correct_nodes(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "norm", Path(tmp) / "exports"
            src.mkdir()
            write_batch(src)
            build_exports(src, out, content_version="2026.08.13-hu-pf.1")

            export = json.loads((out / "tourn-hu-chip-ev-noante-07bb.json").read_text())
            self.assertTrue(export["packID"].endswith("-07bb"))
            self.assertEqual(export["effectiveStack"], {"centiBB": 700})
            self.assertEqual([n["facing"] for n in export["nodes"]], ["unopened", "singleRaise"])
            self.assertEqual(export["nodes"][0]["decisionEffectiveStack"], {"centiBB": 650})
            self.assertEqual(export["nodes"][1]["decisionEffectiveStack"], {"centiBB": 600})
            self.assertIsNotNone(export["nodes"][0]["rangeCells"][0]["actionEVs"])
            # allIn maps to the range key `raise`.
            self.assertIn("raise", export["nodes"][0]["rangeCells"][0]["actionWeightsBasisPoints"])
            self.assertEqual(export["tournament"]["effectiveBigBlinds"], 7)
            self.assertEqual(len(export["nodes"][0]["rangeCells"]), 169)

            # 1BB has a single Open-Jam node and no Call-Jam.
            one = json.loads((out / "tourn-hu-chip-ev-noante-01bb.json").read_text())
            self.assertEqual([n["facing"] for n in one["nodes"]], ["unopened"])

    def test_partial_batch_writes_nothing(self):
        def drop(depth, doc):
            if depth == 7:
                del doc["tables"]["callJam"]
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "norm", Path(tmp) / "exports"
            src.mkdir()
            write_batch(src, drop)
            with self.assertRaisesRegex(BatchValidationError, r"7BB: missing Call-Jam"):
                build_exports(src, out, content_version="2026.08.13-hu-pf.1")
            self.assertFalse(out.exists() and any(out.iterdir()))

    def test_output_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "norm"
            src.mkdir()
            write_batch(src)
            build_exports(src, Path(tmp) / "a", content_version="2026.08.13-hu-pf.1")
            build_exports(src, Path(tmp) / "b", content_version="2026.08.13-hu-pf.1")
            for depth in range(1, 21):
                name = f"tourn-hu-chip-ev-noante-{depth:02d}bb.json"
                self.assertEqual(
                    (Path(tmp) / "a" / name).read_bytes(),
                    (Path(tmp) / "b" / name).read_bytes(),
                    name,
                )


if __name__ == "__main__":
    unittest.main()
