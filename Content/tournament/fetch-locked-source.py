#!/usr/bin/env python3
"""Fetch the exact poker-cfr inputs only after every SHA-256 check succeeds."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from typing import Callable, Union
from urllib.request import urlopen


class SourceLockError(RuntimeError):
    """A source input could not be fetched or did not match its lock."""


def _validate_relative_path(value: str) -> Path:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts:
        raise SourceLockError(f"invalid locked path: {value!r}")
    return Path(*path.parts)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _locked_entries(manifest):
    try:
        license_entry = manifest["license"]
        files = manifest["files"]
        commit = manifest["commit"]
    except (KeyError, TypeError) as error:
        raise SourceLockError("invalid source lock") from error
    if not isinstance(files, list) or not files or not isinstance(commit, str) or len(commit) != 40:
        raise SourceLockError("source lock must contain a commit and non-empty files list")
    try:
        license_input = {
            "path": license_entry["path"],
            "url": license_entry["url"],
            "sha256": license_entry["sha256"],
        }
    except (KeyError, TypeError) as error:
        raise SourceLockError("invalid license entry in source lock") from error
    entries = [*files, license_input]
    for entry in entries:
        try:
            url = entry["url"]
        except (KeyError, TypeError) as error:
            raise SourceLockError("invalid file entry in source lock") from error
        if f"/{commit}/" not in url:
            raise SourceLockError(f"locked URL is not pinned to commit {commit}: {url}")
    return entries


def fetch_locked_source(
    lock_path: Union[str, Path],
    destination: Union[str, Path],
    fetch_bytes: Callable[[str], bytes] = None,
) -> None:
    """Populate a new destination atomically from a verified source-lock manifest.

    `destination` must not already exist.  Every listed input is first written to
    an isolated temporary directory and verified before that directory is moved
    into place, so a failed fetch never publishes a partial source tree.
    """
    lock_path = Path(lock_path)
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise SourceLockError(f"destination already exists: {destination}")

    try:
        manifest = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise SourceLockError(f"invalid source lock: {lock_path}") from error
    entries = _locked_entries(manifest)

    fetch = fetch_bytes or (lambda url: urlopen(url).read())
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".source-lock-") as temporary:
        staged = Path(temporary) / "source"
        staged.mkdir()
        paths = set()
        for entry in entries:
            try:
                relative = _validate_relative_path(entry["path"])
                url = entry["url"]
                expected = entry["sha256"].lower()
            except (KeyError, TypeError, AttributeError) as error:
                raise SourceLockError("invalid file entry in source lock") from error
            if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
                raise SourceLockError(f"invalid sha256 for {relative}")
            if relative in paths:
                raise SourceLockError(f"duplicate locked path: {relative}")
            paths.add(relative)
            try:
                content = fetch(url)
            except Exception as error:
                raise SourceLockError(f"fetch failed for {relative}: {error}") from error
            if not isinstance(content, bytes):
                raise SourceLockError(f"fetch returned non-bytes for {relative}")
            actual = _sha256(content)
            if actual != expected:
                raise SourceLockError(f"sha256 mismatch for {relative}: expected {expected}, got {actual}")
            target = staged / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)

        # Re-check staged bytes so publication has a single, explicit integrity gate.
        for entry in entries:
            relative = _validate_relative_path(entry["path"])
            if _sha256((staged / relative).read_bytes()) != entry["sha256"].lower():
                raise SourceLockError(f"sha256 mismatch after staging for {relative}")
        os.replace(staged, destination)
