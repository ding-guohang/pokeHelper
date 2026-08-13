import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "fetch-locked-source.py"
SPEC = importlib.util.spec_from_file_location("fetch_locked_source", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SourceLockError = MODULE.SourceLockError
fetch_locked_source = MODULE.fetch_locked_source


def sha256(data):
    if isinstance(data, Path):
        data = data.read_bytes()
    return hashlib.sha256(data).hexdigest()


class LockedSourceTests(unittest.TestCase):
    def write_manifest(self, root, files):
        manifest = {"repository": "b-inary/poker-cfr", "commit": "a" * 40, "files": files}
        path = root / "source-lock.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def test_hash_mismatch_leaves_destination_absent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = self.write_manifest(root, [{
                "path": "src/cfr.rs", "url": "https://example.invalid/cfr.rs", "sha256": "00" * 32,
            }])
            destination = root / "source"

            with self.assertRaisesRegex(SourceLockError, "sha256 mismatch"):
                fetch_locked_source(lock, destination, lambda _: b"changed")

            self.assertFalse(destination.exists())

    def test_locked_files_are_written_only_after_all_verify(self):
        payloads = {
            "https://example.invalid/cfr.rs": b"cfr source",
            "https://example.invalid/game.rs": b"push fold source",
            "https://example.invalid/equity.bin": b"equity data",
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = self.write_manifest(root, [
                {"path": "src/cfr.rs", "url": "https://example.invalid/cfr.rs", "sha256": sha256(payloads["https://example.invalid/cfr.rs"])},
                {"path": "src/game_push_fold.rs", "url": "https://example.invalid/game.rs", "sha256": sha256(payloads["https://example.invalid/game.rs"])},
                {"path": "static/heads_up_pre_flop_equity.bin", "url": "https://example.invalid/equity.bin", "sha256": sha256(payloads["https://example.invalid/equity.bin"])},
            ])
            destination = root / "source"

            fetch_locked_source(lock, destination, payloads.__getitem__)

            self.assertEqual(sha256(destination / "src/cfr.rs"), sha256(payloads["https://example.invalid/cfr.rs"]))
            self.assertEqual(sha256(destination / "src/game_push_fold.rs"), sha256(payloads["https://example.invalid/game.rs"]))
            self.assertEqual(sha256(destination / "static/heads_up_pre_flop_equity.bin"), sha256(payloads["https://example.invalid/equity.bin"]))

    def test_rejects_destination_that_already_exists(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = self.write_manifest(root, [])
            destination = root / "source"
            destination.mkdir()

            with self.assertRaisesRegex(SourceLockError, "destination already exists"):
                fetch_locked_source(lock, destination, lambda _: b"")

    def test_repository_lock_has_all_required_inputs(self):
        lock = Path(__file__).parents[1] / "source-lock.json"
        manifest = json.loads(lock.read_text(encoding="utf-8"))
        files = {entry["path"]: entry for entry in manifest["files"]}

        self.assertEqual(manifest["commit"], "a5347082007ba1eda7932ef2fe7fad43cb3be2a1")
        self.assertEqual(manifest["license"]["spdx"], "BSD-2-Clause")
        self.assertEqual(manifest["rustVersion"], "1.56.0")
        self.assertEqual(files["src/cfr.rs"]["sha256"], "6e67183dc0d05b34e3a866fecd3e0e76847b4feb406f37ea01f70563ba9bd6bf")
        self.assertEqual(files["src/game_push_fold.rs"]["sha256"], "31f40d9069bccf6c0bb06d172ef7f2d3ad11d80caa498c5bbeec684c0d23ce48")
        self.assertEqual(files["static/heads_up_pre_flop_equity.bin"]["sha256"], "006404b36d257fc9455da0d0f0ab89aef3e80ece56c8f3e770bad926cfe5ec8a")
        self.assertIn("Cargo.toml", files)
        self.assertIn("Cargo.lock", files)


if __name__ == "__main__":
    unittest.main()
