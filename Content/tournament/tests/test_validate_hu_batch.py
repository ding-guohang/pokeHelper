"""Independent-validator tests: a complete synthetic batch passes; each
structural or provenance defect fails closed with a naming message."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "validate_hu_batch.py"
SPEC = importlib.util.spec_from_file_location("validate_hu_batch", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

validate_batch = MODULE.validate_batch
BatchValidationError = MODULE.BatchValidationError
CANONICAL = MODULE.CANONICAL
snapshot_hash = MODULE._snapshot_hash


def make_doc(depth: int) -> dict:
    def table(primary: str, fold_ev: int):
        rows = []
        for hand in sorted(CANONICAL):
            rows.append({
                "handClass": hand,
                "actionWeightsBasisPoints": {primary: 6_000, "fold": 4_000},
                "actionEVsMilliBB": {primary: 120, "fold": fold_ev},
            })
        return rows

    tables = {"openJam": table("allIn", -500)}
    if depth >= 2:
        tables["callJam"] = table("call", -1000)
    doc = {
        "effectiveBigBlinds": depth,
        "source": {"repository": "b-inary/poker-cfr", "commit": "a" * 40, "licenseSpdx": "BSD-2-Clause", "lockedHashes": {}},
        "configuration": {
            "nashConvThresholdBB": 0.001, "equilibrium": "chipEV",
            "smallBlindCentiBB": 50, "bigBlindCentiBB": 100,
            "hasAnte": False, "anteDescription": "no ante",
        },
        "iterations": 10_000,
        "nashConvBB": 0.0001,
        "exploitabilityBB": 0.00005,
        "testOnly": False,
        "exportedAt": "2026-08-13T00:00:00Z",
        "tables": tables,
    }
    doc["snapshotSHA256"] = snapshot_hash(doc)
    return doc


class BatchValidationTests(unittest.TestCase):
    def write_batch(self, root: Path, mutate=None):
        for depth in range(1, 21):
            doc = make_doc(depth)
            if mutate is not None:
                mutate(depth, doc)
                doc["snapshotSHA256"] = snapshot_hash(doc)  # re-seal after mutation
            (root / f"hu-chip-ev-noante-{depth:02d}bb.json").write_text(
                json.dumps(doc, sort_keys=True, indent=2) + "\n", encoding="utf-8"
            )

    def test_complete_batch_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_batch(root)
            audit = validate_batch(root)
            self.assertEqual(audit["depths"], list(range(1, 21)))
            self.assertEqual(audit["tableCount"], 39)  # 20 open + 19 call
            self.assertEqual(audit["rowCount"], 39 * 169)

    def test_missing_7bb_call_jam_is_rejected(self):
        def mutate(depth, doc):
            if depth == 7:
                del doc["tables"]["callJam"]
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"7BB: missing Call-Jam"):
                validate_batch(Path(tmp))

    def test_missing_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp))
            (Path(tmp) / "hu-chip-ev-noante-12bb.json").unlink()
            with self.assertRaisesRegex(BatchValidationError, r"missing 12BB"):
                validate_batch(Path(tmp))

    def test_duplicate_and_missing_hand_reported(self):
        def mutate(depth, doc):
            if depth == 3:
                rows = doc["tables"]["openJam"]
                # Replace 72o with a duplicate AA: one missing + one duplicate.
                for row in rows:
                    if row["handClass"] == "72o":
                        row["handClass"] = "AA"
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"3BB Open-Jam: duplicate hand AA"):
                validate_batch(Path(tmp))

    def test_noncanonical_hand_is_rejected(self):
        def mutate(depth, doc):
            if depth == 4:
                doc["tables"]["openJam"][0]["handClass"] = "ZZ"
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"non-canonical hand 'ZZ'"):
                validate_batch(Path(tmp))

    def test_frequency_total_not_10000_is_rejected(self):
        def mutate(depth, doc):
            if depth == 5:
                doc["tables"]["openJam"][0]["actionWeightsBasisPoints"]["fold"] = 3_999
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"basis points total 9999"):
                validate_batch(Path(tmp))

    def test_frequency_and_ev_keys_must_match(self):
        def mutate(depth, doc):
            if depth == 6:
                doc["tables"]["openJam"][0]["actionEVsMilliBB"] = {"allIn": 120, "raise": -500}
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"EV keys .* != frequency keys"):
                validate_batch(Path(tmp))

    def test_null_ev_is_rejected(self):
        def mutate(depth, doc):
            if depth == 8:
                doc["tables"]["callJam"][0]["actionEVsMilliBB"]["call"] = None
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"call EV must be an integer"):
                validate_batch(Path(tmp))

    def test_fold_ev_invariant_is_enforced(self):
        def mutate(depth, doc):
            if depth == 9:
                doc["tables"]["openJam"][0]["actionEVsMilliBB"]["fold"] = -499
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"fold EV -499 != invariant -500"):
                validate_batch(Path(tmp))

    def test_snapshot_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_batch(root)
            path = root / "hu-chip-ev-noante-10bb.json"
            doc = json.loads(path.read_text())
            doc["snapshotSHA256"] = "0" * 64
            path.write_text(json.dumps(doc, sort_keys=True, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(BatchValidationError, r"10BB: snapshot hash mismatch"):
                validate_batch(root)

    def test_nash_conv_above_threshold_is_rejected(self):
        def mutate(depth, doc):
            if depth == 11:
                doc["nashConvBB"] = 0.5
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"11BB: NashConv 0.5 exceeds threshold"):
                validate_batch(Path(tmp))

    def test_test_only_output_is_rejected(self):
        def mutate(depth, doc):
            if depth == 2:
                doc["testOnly"] = True
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"2BB: testOnly"):
                validate_batch(Path(tmp))

    def test_exploitability_must_equal_nashconv_half(self):
        def mutate(depth, doc):
            if depth == 13:
                doc["exploitabilityBB"] = doc["nashConvBB"]  # not /2
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"exploitabilityBB"):
                validate_batch(Path(tmp))

    def test_wrong_equilibrium_or_ante_rejected(self):
        def mutate(depth, doc):
            if depth == 14:
                doc["configuration"]["hasAnte"] = True
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"hasAnte must be false"):
                validate_batch(Path(tmp))

    def test_nan_nashconv_rejected(self):
        def mutate(depth, doc):
            if depth == 15:
                doc["nashConvBB"] = float("nan")
                doc["exploitabilityBB"] = float("nan")
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp), mutate)
            with self.assertRaisesRegex(BatchValidationError, r"not a finite number"):
                validate_batch(Path(tmp))

    def test_source_commit_mismatch_rejected(self):
        source_lock = {
            "commit": "b" * 40,  # differs from doc's "a"*40
            "license": {"spdx": "BSD-2-Clause"},
            "files": [],
        }
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp))
            with self.assertRaisesRegex(BatchValidationError, r"source commit"):
                validate_batch(Path(tmp), source_lock=source_lock)

    def test_source_lock_hash_mismatch_is_rejected(self):
        source_lock = {
            "commit": "a" * 40,
            "license": {"spdx": "BSD-2-Clause"},
            "files": [{"path": "src/cfr.rs", "sha256": "beef" * 16}],
        }
        with tempfile.TemporaryDirectory() as tmp:
            self.write_batch(Path(tmp))  # docs carry empty lockedHashes
            with self.assertRaisesRegex(BatchValidationError, r"source hash for src/cfr.rs"):
                validate_batch(Path(tmp), source_lock=source_lock)


if __name__ == "__main__":
    unittest.main()
