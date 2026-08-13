"""Task 6 tests: the import wrapper is fixed to unverified solver origin and
exposes no review-status argument."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SPEC = importlib.util.spec_from_file_location(
    "import_tournament_packs", _ROOT / "Content" / "import-tournament-packs.py"
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
plan_imports = _MOD.plan_imports
parse_args = _MOD.parse_args


class ImportTournamentPacksTests(unittest.TestCase):
    def _dummy_exports(self, root):
        for depth in (1, 7, 20):
            (root / f"tourn-hu-chip-ev-noante-{depth:02d}bb.json").write_text("{}", encoding="utf-8")

    def test_import_command_is_fixed_to_unverified_solver(self):
        with tempfile.TemporaryDirectory() as tmp:
            exports = Path(tmp) / "exports"
            exports.mkdir()
            self._dummy_exports(exports)
            commands = plan_imports(exports, Path(tmp) / "packs", "2026.08.13-hu-pf.1")

            self.assertEqual(len(commands), 3)
            for command in commands:
                self.assertIn("--review-status", command)
                self.assertEqual(command[command.index("--review-status") + 1], "unverifiedDraft")
                self.assertIn("--origin", command)
                self.assertEqual(command[command.index("--origin") + 1], "solver")
                self.assertNotIn("--reviewed-by", command)
                self.assertNotIn("--reviewed-at", command)

    def test_reviewed_request_is_not_an_available_argument(self):
        with self.assertRaises(SystemExit):
            parse_args([
                "--content-version", "x", "--exports", "e", "--destination", "d",
                "--strategy-import", "s", "--review-status", "reviewed",
            ])


if __name__ == "__main__":
    unittest.main()
