"""Integration smoke test for the HU push/fold solver export.

Requires network (to clone the locked source once) and the Rust toolchain, so
it is a content-build test. It solves the trivial 1BB depth at a small
checkpoint and asserts the export's shape, the SB fold-EV invariant, the absence
of a 1BB Call-Jam table, snapshot-hash reproducibility, and cross-run
determinism.
"""

import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "generate-hu-pushfold.py"
SPEC = importlib.util.spec_from_file_location("generate_hu_pushfold", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

run_solver = MODULE.run_solver
snapshot_hash = MODULE.snapshot_hash

CARGO = Path.home() / ".cargo" / "bin" / "cargo"


@unittest.skipUnless(CARGO.exists(), "Rust toolchain not installed")
class SolverExportSmokeTests(unittest.TestCase):
    def test_one_bb_export_has_same_snapshot_frequency_and_ev(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "out"
            result = run_solver(depth=1, checkpoints=[2_000], threshold=0.05, output=output)

            self.assertEqual(result["effectiveBigBlinds"], 1)
            self.assertEqual(len(result["tables"]["openJam"]), 169)
            self.assertTrue(
                all(row["actionEVsMilliBB"]["fold"] == -500 for row in result["tables"]["openJam"]),
                "every SB open-jam row must carry the -500 milli-BB fold EV",
            )
            self.assertNotIn("callJam", result["tables"], "1BB has no Call-Jam decision")

            # The snapshot hash reproduces from the returned document.
            recorded = result["snapshotSHA256"]
            self.assertEqual(recorded, snapshot_hash(result))

            # The file was written.
            self.assertTrue((output / "hu-chip-ev-noante-01bb.json").is_file())

    def test_open_jam_frequencies_sum_to_10000(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run_solver(depth=1, checkpoints=[2_000], threshold=0.05, output=Path(tmp) / "out")
            for row in result["tables"]["openJam"]:
                weights = row["actionWeightsBasisPoints"]
                self.assertEqual(weights["allIn"] + weights["fold"], 10_000, row["handClass"])

    def test_cross_run_bytes_are_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "a"
            second = Path(tmp) / "b"
            run_solver(depth=1, checkpoints=[2_000], threshold=0.05, output=first)
            run_solver(depth=1, checkpoints=[2_000], threshold=0.05, output=second)
            a = (first / "hu-chip-ev-noante-01bb.json").read_bytes()
            b = (second / "hu-chip-ev-noante-01bb.json").read_bytes()
            self.assertEqual(a, b, "same input must produce byte-identical normalized output")


if __name__ == "__main__":
    unittest.main()
