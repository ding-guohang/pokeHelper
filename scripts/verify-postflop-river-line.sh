#!/usr/bin/env bash
#
# Reproducibility + independent-verification gate for the betting-line (Batch B)
# river content.
#
# Re-solves every betting-line spot FROM THE FLOP (single-threaded), re-runs the
# independent river-subtree best-response check given the extracted narrowed
# ranges (the runner fails closed unless each is within threshold), re-normalizes/
# exports/imports, and byte-compares every regenerated pack + sidecar + report
# against the tracked files. Then the content suite + layering gate.
#
# Each flop solve is heavy (~minutes at 40bb); the whole gate is ~minutes x spots.
# Requires the Rust toolchain and network (to fetch the locked source once).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Defaults target the two-barrel batch; override via env to gate another
# betting-line batch (e.g. the single-barrel one) with the same script.
CONTENT_VERSION="${LINE_CONTENT_VERSION:-2026.08.18-srp-line-river.1}"
BATCH="${LINE_BATCH:-Content/postflop/spots/srp-betting-line-river-batch.json}"
TRACKED="${LINE_TRACKED:-Content/postflop/packs-line}"
export PATH="$HOME/.cargo/bin:$PATH"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "==> Build strategy-import"
swift build --package-path Packages/StrategyTooling -c release >/dev/null

echo "==> Re-run the betting-line river batch from the locked solver (single-threaded)"
python3 Content/postflop/run-river-from-flop-batch.py \
    --batch "$BATCH" \
    --content-version "$CONTENT_VERSION" \
    --strategy-import Packages/StrategyTooling/.build/release/strategy-import \
    --dest "$scratch/packs" >/dev/null

echo "==> Regenerated packs are byte-identical to tracked"
for f in "$TRACKED"/*.json "$TRACKED"/*.sha256; do
    name="$(basename "$f")"
    diff "$scratch/packs/$name" "$f" >/dev/null
done

echo "==> Independent river-subtree check within threshold for every spot"
python3 - "$scratch/packs/batch-report.json" <<'PY'
import json, sys
report = json.loads(open(sys.argv[1]).read())
spots = report["spots"]
# Per-spot threshold: 1% of that spot's own river pot (varies by line — e.g. the
# single-barrel line's turn checks through, so its river pot is smaller).
bad = [(s["id"], s["independentRiverSubtreeExploitabilityChips"])
       for s in spots
       if s["independentRiverSubtreeExploitabilityChips"] > s["riverPotChips"] * 0.01]
if bad:
    raise SystemExit(f"river-subtree exploitability exceeds 1% of pot for: {bad}")
worst = max(s["independentRiverSubtreeExploitabilityChips"] / s["riverPotChips"] for s in spots)
print(f"   {len(spots)} spots, worst independent river-subtree exploitability {worst:.3%} of pot")
PY

echo "==> Content and tooling suites"
swift test --package-path Packages/StrategyContent >/dev/null
swift test --package-path Packages/StrategyTooling >/dev/null

echo "==> Package layering"
bash scripts/check-package-layering.sh >/dev/null

echo "postflop betting-line river content verification passed"
