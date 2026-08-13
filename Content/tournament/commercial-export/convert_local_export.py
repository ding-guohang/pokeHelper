#!/usr/bin/env python3
"""Offline-only conversion for a user-supplied, licensed commercial range export.

This never reaches a commercial platform. It accepts a local regular file the
user is licensed to use, records its provenance and SHA-256, and requires
same-source per-action EV so the result can be scored. It imports no networking
or browser library on purpose. Converted output is still `unverifiedDraft` until
a named human review; this module does not promote content.
"""

import hashlib
import json
from pathlib import Path


class LocalExportError(RuntimeError):
    """A local export could not be accepted or was not scorable."""


def _reject_network_input(source):
    if isinstance(source, str):
        lowered = source.strip().lower()
        if "://" in lowered or lowered.startswith(("http:", "https:", "ftp:", "file:")):
            raise LocalExportError("input must be a local file, not a URL")
        return Path(source)
    if isinstance(source, Path):
        return source
    raise LocalExportError("input must be a local file path")


def convert(source, metadata):
    """Convert a licensed local export into a normalized, unverified document.

    Rejects URLs, symlinks, directories, missing provenance/license evidence,
    missing assumptions, and frequency-only files with no per-action EV.
    """
    path = _reject_network_input(source)
    if path.is_symlink():
        raise LocalExportError("input must be a regular local file, not a symlink")
    if not path.is_file():
        raise LocalExportError("input must be an existing local file")

    metadata = metadata or {}
    if not metadata.get("platform"):
        raise LocalExportError("missing source platform provenance")
    if not metadata.get("license_evidence"):
        raise LocalExportError("missing license evidence for the exported range")
    assumptions = metadata.get("assumptions")
    if not assumptions:
        raise LocalExportError("missing solver assumptions")

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise LocalExportError(f"export is not valid JSON: {error}") from error

    hands = data.get("hands")
    if not isinstance(hands, list) or not hands:
        raise LocalExportError("export must list hand frequencies")
    for row in hands:
        evs = row.get("actionEVsMilliBB")
        if not evs:
            raise LocalExportError(
                "export must include same-source per-action EV; a frequency-only file is not scorable content"
            )

    return {
        "provenance": {
            "platform": metadata["platform"],
            "sourceSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "licenseEvidence": metadata["license_evidence"],
        },
        "assumptions": assumptions,
        "reviewStatus": "unverifiedDraft",
        "hands": hands,
    }
