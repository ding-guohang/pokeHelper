#!/usr/bin/env python3
"""Import validated tournament SolverExport files into unverified solver packs.

The command surface is deliberately narrow: there is no way to request a review
status. Every pack is imported as `origin=solver` / `reviewStatus=unverifiedDraft`;
human promotion is a separate future operation that consumes review evidence.
Packs and their `.sha256` sidecars are written to a staging directory and only
moved into place after every import and checksum succeeds.
"""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

EXPORT_GLOB = "tourn-hu-chip-ev-noante-*.json"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Import unverified tournament solver packs")
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--exports", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--strategy-import", required=True)
    return parser.parse_args(argv)


def plan_imports(exports_dir, destination, content_version, strategy_import="strategy-import"):
    """Return one fixed strategy-import argv per export file. The status and
    origin are hard-coded; no reviewer arguments are ever emitted."""
    exports_dir = Path(exports_dir)
    destination = Path(destination)
    commands = []
    for export in sorted(exports_dir.glob(EXPORT_GLOB)):
        pack = destination / export.name
        commands.append([
            str(strategy_import),
            "--export", str(export),
            "--content-version", content_version,
            "--review-status", "unverifiedDraft",
            "--origin", "solver",
            "--output", str(pack),
        ])
    return commands


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def import_packs(exports_dir, destination, content_version, strategy_import):
    """Import all exports into a staging directory, then atomically publish.
    Writes nothing to `destination` unless every import and checksum succeeds."""
    exports_dir = Path(exports_dir)
    destination = Path(destination)
    staging = Path(tempfile.mkdtemp(prefix="tourn-packs-"))
    try:
        commands = plan_imports(exports_dir, staging, content_version, strategy_import)
        if not commands:
            raise RuntimeError(f"no export files matching {EXPORT_GLOB} in {exports_dir}")
        for command in commands:
            subprocess.run(command, check=True, capture_output=True, text=True)
        names = []
        for command in commands:
            pack = Path(command[command.index("--output") + 1])
            if not pack.is_file():
                raise RuntimeError(f"strategy-import did not write {pack.name}")
            (pack.with_suffix(".sha256")).write_text(_sha256(pack) + "\n", encoding="utf-8")
            names.append(pack.name)

        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(destination))
        return sorted(names)
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main(argv=None):
    args = parse_args(argv)
    names = import_packs(args.exports, args.destination, args.content_version, args.strategy_import)
    print(f"imported {len(names)} unverified tournament packs to {args.destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
