# Task 2 report — locked solver provenance

## Outcome

Implemented a fail-closed locked-source fetcher for
`b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`.  The manifest
locks Cargo inputs, required solver sources, the HU equity binary, BSD-2-Clause
license provenance, and Rust `1.56.0`.  Sources stage in a fresh temporary
directory and publish only through `os.replace` after every SHA-256 check.

## RED evidence

Before the production module existed:

```text
python3 -m unittest Content.tournament.tests.test_fetch_locked_source -v
ModuleNotFoundError: No module named 'Content.tournament.tests.test_fetch_locked_source'
```

After adding the test module but before implementation:

```text
FileNotFoundError: .../Content/tournament/fetch-locked-source.py
```

This confirmed the requested provenance behavior was unimplemented.

## GREEN evidence

```text
python3 -m unittest Content.tournament.tests.test_fetch_locked_source -v
Ran 4 tests ... OK
PYTHONPYCACHEPREFIX=/private/tmp/pycache python3 -m py_compile Content/tournament/fetch-locked-source.py
git diff --check
```

Tests cover hash-mismatch non-publication, all-file staging, an existing
destination rejection, and the committed lock's required commit/source hashes.

## Source verification

GitHub API verification at the locked commit produced the design-specified
SHA-256 values for `src/cfr.rs`, `src/game_push_fold.rs`, and
`static/heads_up_pre_flop_equity.bin`; the manifest also records verified
`Cargo.toml`, `Cargo.lock`, and license hashes. The raw GitHub path returned
404 because this repository uses `LICENSE.md`, so immutable Git blob API URLs
are used deliberately.

## Commit

`build: lock HU push-fold solver inputs` (pending creation at report write time)

## Concerns

The fetcher intentionally refuses an existing destination rather than replacing
it. Callers that want a refresh must create a new destination and switch it
after their own verification; this preserves the no-overwrite fail-closed rule.

## Fix round 1 — raw source and license verification

The lock now uses immutable `raw.githubusercontent.com` commit URLs, rather
than Git Blob API URLs whose default response is JSON.  The fetcher makes the
commit-to-URL relationship explicit for every source and license URL, and
treats the declared license as another staged, hash-verified input.  A license
mismatch now fails before publication.

### RED evidence

Before the fix, newly added license tests failed: the staged directory lacked
`LICENSE.md`, and a bad license hash did not raise `SourceLockError`.

### GREEN evidence

```text
python3 -m unittest Content.tournament.tests.test_fetch_locked_source -v
Ran 5 tests ... OK
PYTHONPYCACHEPREFIX=/private/tmp/pycache python3 -m py_compile Content/tournament/fetch-locked-source.py
git diff --check
```
