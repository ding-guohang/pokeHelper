"""Task 8 tests: the local-export converter is offline-only, requires license
evidence, and refuses frequency-only (non-scorable) files."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_SPEC = importlib.util.spec_from_file_location(
    "convert_local_export",
    _ROOT / "Content" / "tournament" / "commercial-export" / "convert_local_export.py",
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
convert = _MOD.convert
LocalExportError = _MOD.LocalExportError


def metadata(**overrides):
    base = {
        "platform": "PioSolver",
        "license_evidence": "personal subscription export, per platform ToS §4",
        "assumptions": {"equilibrium": "chipEV", "hasAnte": False},
    }
    base.update(overrides)
    return base


class ConvertLocalExportTests(unittest.TestCase):
    def test_http_input_is_rejected(self):
        with self.assertRaisesRegex(LocalExportError, "local file"):
            convert("https://gtowizard.com/solution", metadata())

    def test_missing_license_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "range.txt"
            source.write_text("AA:1", encoding="utf-8")
            with self.assertRaisesRegex(LocalExportError, "license evidence"):
                convert(source, metadata(license_evidence=""))

    def test_frequency_only_export_cannot_become_scorable_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "range.json"
            source.write_text(json.dumps({
                "hands": [{"handClass": "AA", "actionWeightsBasisPoints": {"raise": 10000, "fold": 0}}]
            }), encoding="utf-8")
            with self.assertRaisesRegex(LocalExportError, "per-action EV"):
                convert(source, metadata())

    def test_symlink_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            real = Path(tmp) / "real.json"
            real.write_text("{}", encoding="utf-8")
            link = Path(tmp) / "link.json"
            link.symlink_to(real)
            with self.assertRaisesRegex(LocalExportError, "symlink"):
                convert(link, metadata())

    def test_valid_local_export_records_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "range.json"
            source.write_text(json.dumps({
                "hands": [{
                    "handClass": "AA",
                    "actionWeightsBasisPoints": {"raise": 10000, "fold": 0},
                    "actionEVsMilliBB": {"raise": 2978, "fold": -500},
                }]
            }), encoding="utf-8")
            result = convert(source, metadata())
            self.assertEqual(result["reviewStatus"], "unverifiedDraft")
            self.assertEqual(result["provenance"]["platform"], "PioSolver")
            self.assertEqual(len(result["provenance"]["sourceSHA256"]), 64)


if __name__ == "__main__":
    unittest.main()
