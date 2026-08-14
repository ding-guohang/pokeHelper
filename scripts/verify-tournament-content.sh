#!/usr/bin/env bash
#
# Reproducibility + regression gate for the HU push/fold solver content.
#
# Regenerates the normalized batch from the locked solver into a temp dir,
# revalidates it, rebuilds exports/packs and the golden manifest, and byte-
# compares every regenerated artifact against the tracked files. Then runs the
# affected Swift suites and the package layering gate. Requires the Rust
# toolchain and network (to fetch the locked source once).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTENT_VERSION="2026.08.13-hu-pf.1"
export PATH="$HOME/.cargo/bin:$PATH"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "==> Regenerate normalized batch from the locked solver"
python3 Content/tournament/generate-hu-pushfold.py \
    --source-lock Content/tournament/source-lock.json \
    --depths 1-20 --nash-conv-threshold 0.001 \
    --output "$scratch/normalized" >/dev/null

echo "==> Validate the regenerated batch"
python3 Content/tournament/validate_hu_batch.py "$scratch/normalized" \
    --source-lock Content/tournament/source-lock.json

echo "==> Normalized files are byte-identical to tracked"
for depth in $(seq -w 1 20); do
    name="hu-chip-ev-noante-${depth}bb.json"
    diff "$scratch/normalized/$name" "Content/tournament-normalized/$name" >/dev/null
done

echo "==> Rebuild exports and compare the 20 tournament files"
python3 Content/build-tournament-exports.py \
    --input "$scratch/normalized" --output "$scratch/exports" \
    --content-version "$CONTENT_VERSION" >/dev/null
for depth in $(seq -w 1 20); do
    name="tourn-hu-chip-ev-noante-${depth}bb.json"
    diff "$scratch/exports/$name" "Content/exports/$name" >/dev/null
done

echo "==> Rebuild packs and compare"
swift build --package-path Packages/StrategyTooling -c release >/dev/null
python3 Content/import-tournament-packs.py \
    --exports "$scratch/exports" --destination "$scratch/packs" \
    --content-version "$CONTENT_VERSION" \
    --strategy-import Packages/StrategyTooling/.build/release/strategy-import >/dev/null
for depth in $(seq -w 1 20); do
    name="tourn-hu-chip-ev-noante-${depth}bb.json"
    sidecar="tourn-hu-chip-ev-noante-${depth}bb.sha256"
    diff "$scratch/packs/$name" "Content/packs/$name" >/dev/null
    diff "$scratch/packs/$sidecar" "Content/packs/$sidecar" >/dev/null
done

echo "==> Rebuild golden manifest and compare"
python3 Content/tournament/build-golden-manifest.py \
    --root . --content-version "$CONTENT_VERSION" \
    --output "$scratch/golden-manifest.json" >/dev/null
# The manifest hashes the tracked artifacts, so build against the repo, then diff.
diff "$scratch/golden-manifest.json" "Content/tournament/golden-manifest.json" >/dev/null

echo "==> Independent evidence: equity recompute + exploitability cross-check"
# The generate step above populated the locked solver checkout in the default
# cache; the upstream equity table lives at <crate>/static. Both tools re-verify
# the table's SHA-256 against source-lock and exit non-zero if a threshold is
# exceeded, and we byte-diff the regenerated reports so a stale committed report
# also fails the gate.
solver_cache="$(python3 -c 'import tempfile; print(tempfile.gettempdir())')/pokerhelper-solver-cache"
commit="$(python3 -c "import json; print(json.load(open('Content/tournament/source-lock.json'))['commit'])")"
equity_bin="$solver_cache/poker-cfr-$commit/static/heads_up_pre_flop_equity.bin"
if [ ! -f "$equity_bin" ]; then
    echo "FAIL: locked equity table missing at $equity_bin (solver cache not populated)" >&2
    exit 1
fi
python3 Content/tournament/verify-equities.py \
    --equity "$equity_bin" --source-lock Content/tournament/source-lock.json \
    --report "$scratch/equity-verify-report.md" >/dev/null
diff "$scratch/equity-verify-report.md" "Content/tournament/equity-verify-report.md" >/dev/null
python3 Content/tournament/cross-check-exploitability.py \
    --normalized Content/tournament-normalized --equity "$equity_bin" \
    --source-lock Content/tournament/source-lock.json \
    --report "$scratch/cross-check-report.md" >/dev/null
diff "$scratch/cross-check-report.md" "Content/tournament/cross-check-report.md" >/dev/null

echo "==> Content and tooling suites"
swift test --package-path Packages/StrategyContent >/dev/null
swift test --package-path Packages/StrategyTooling >/dev/null
python3 -m unittest discover -s Content/tournament/tests >/dev/null 2>&1

echo "==> Package layering"
bash scripts/check-package-layering.sh >/dev/null

echo "tournament content verification passed"
