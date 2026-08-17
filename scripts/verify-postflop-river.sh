#!/usr/bin/env bash
#
# Reproducibility + independent-verification gate for the postflop river content.
#
# Re-solves every board in the batch from the locked solver (single-threaded for
# byte-reproducibility), re-runs the INDEPENDENT best-response exploitability
# check (the batch runner fails closed unless each board matches the solver and
# stays under threshold), re-normalizes/exports/imports, and byte-compares every
# regenerated pack + sidecar + report against the tracked files. Then runs the
# content suite and the package layering gate. Requires the Rust toolchain and
# network (to fetch the locked source once).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTENT_VERSION="2026.08.17-srp-river.1"
BATCH="Content/postflop/spots/srp-checked-river-batch.json"
TRACKED="Content/postflop/packs"
export PATH="$HOME/.cargo/bin:$PATH"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "==> Build strategy-import"
swift build --package-path Packages/StrategyTooling -c release >/dev/null

echo "==> Re-run the river batch from the locked solver (single-threaded)"
python3 Content/postflop/run-river-batch.py \
    --batch "$BATCH" \
    --content-version "$CONTENT_VERSION" \
    --strategy-import Packages/StrategyTooling/.build/release/strategy-import \
    --dest "$scratch/packs" >/dev/null

echo "==> Regenerated packs are byte-identical to tracked"
for f in "$TRACKED"/*.json "$TRACKED"/*.sha256; do
    name="$(basename "$f")"
    diff "$scratch/packs/$name" "$f" >/dev/null
done

echo "==> Independent best-response check passed for every board"
python3 - "$scratch/packs/batch-report.json" <<'PY'
import json, sys
report = json.loads(open(sys.argv[1]).read())
# The independent recompute and the solver's self-report are separate code paths,
# so the delta is float noise (~1e-6), not exactly zero. A tight absolute bound
# still catches any real divergence. (The batch runner already fails closed on
# the pot-relative tolerance and the exploitability threshold.)
MAX_DELTA = 1e-3  # chips
bad = [(b["id"], b["deltaChips"]) for b in report["boards"] if b["deltaChips"] > MAX_DELTA]
if bad:
    raise SystemExit(f"independent BR delta exceeds {MAX_DELTA} chips for: {bad}")
worst = max(b["deltaChips"] for b in report["boards"])
print(f"   {len(report['boards'])} boards, worst independent BR delta = {worst:.2e} chips")
PY

echo "==> Content and tooling suites"
swift test --package-path Packages/StrategyContent >/dev/null
swift test --package-path Packages/StrategyTooling >/dev/null

echo "==> Package layering"
bash scripts/check-package-layering.sh >/dev/null

echo "postflop river content verification passed"
