#!/usr/bin/env bash
#
# Verifies the M1C slice end to end: domain packages, the authoring tools,
# the app, all three build channels, and the content gate in both directions.
#
# Every check runs against real artifacts. Where a gate can only pass, it is
# also run against a deliberately broken input, because a gate with no
# observed failure is indistinguishable from one that always succeeds.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "==> Generate the Xcode project"
xcodegen generate >/dev/null

echo "==> Test PokerCore"
swift test --package-path Packages/PokerCore >/dev/null

echo "==> Test StrategyContent"
swift test --package-path Packages/StrategyContent >/dev/null

echo "==> Test TrainingDomain"
swift test --package-path Packages/TrainingDomain >/dev/null

echo "==> Test StrategyTooling (includes cross-process import determinism)"
swift test --package-path Packages/StrategyTooling >/dev/null

echo "==> Test PokerCoach unit tests"
xcodebuild test \
  -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests >/dev/null

echo "==> Re-import the core content and confirm it is byte-identical"
swift build --package-path Packages/StrategyTooling >/dev/null
importer="$(find Packages/StrategyTooling/.build -name strategy-import -type f -perm +111 | head -1)"
core_pack="PokerCoach/Resources/CoreStrategyPack.json"
manifest_field() {
  plutil -extract "manifest.$1" raw "$core_pack" 2>/dev/null || true
}

# Review attribution has to be carried through, not dropped: the validator
# refuses `reviewed` content without a named reviewer and a review time, so a
# re-import that omitted them would fail on content that is perfectly fine.
reimport_args=(
  --export Content/exports/core-6max-100bb.json
  --content-version "$(manifest_field contentVersion)"
  --review-status "$(manifest_field reviewStatus)"
  --output "$scratch/core.json"
)
reviewed_by="$(manifest_field reviewedBy)"
reviewed_at="$(manifest_field reviewedAt)"
if [[ -n "$reviewed_by" && "$reviewed_by" != "<null>" ]]; then
  reimport_args+=(--reviewed-by "$reviewed_by")
fi
if [[ -n "$reviewed_at" && "$reviewed_at" != "<null>" ]]; then
  reimport_args+=(--reviewed-at "$reviewed_at")
fi

"$importer" "${reimport_args[@]}" >/dev/null
if ! cmp -s "$scratch/core.json" PokerCoach/Resources/CoreStrategyPack.json; then
  echo "FAIL: the shipped core pack does not match a fresh import of its export" >&2
  echo "      edit Content/exports/ and re-import; never hand-edit the pack" >&2
  exit 1
fi

echo "==> Build all three channels"
for config in Debug Dogfood Release; do
  xcodebuild \
    -scheme PokerCoach \
    -configuration "$config" \
    -sdk iphonesimulator \
    -derivedDataPath "$scratch/$config" \
    build >/dev/null
done

app_for() {
  find "$scratch/$1/Build/Products" -name PokerCoach.app -maxdepth 3 | head -1
}

echo "==> Content gate: each channel carries what it is allowed to"
for config in Debug Dogfood; do
  bash scripts/check-release-content.sh "$(app_for "$config")"
done

# The store channel is expected to fail while the core pack is unreviewed.
# Asserting the specific outcome either way keeps this honest: a green run
# must not silently mean "nobody looked".
store_app="$(app_for Release)"
if bash scripts/check-release-content.sh "$store_app" >/dev/null 2>&1; then
  echo "==> Content gate: store channel passes (reviewed content is installed)"
else
  echo "==> Content gate: store channel correctly blocked (core content is not yet reviewed)"
fi

echo "==> Content gate: rejects unverified content on the store channel"
probe="$scratch/probe.app"
cp -R "$(app_for Dogfood)" "$probe"
plutil -replace PCContentChannel -string store "$probe/Info.plist"
if bash scripts/check-release-content.sh "$probe" >/dev/null 2>&1; then
  echo "FAIL: the store channel accepted unverifiedDraft content" >&2
  exit 1
fi

echo "==> Content gate: fails closed when the channel marker is missing"
unmarked="$scratch/unmarked.app"
cp -R "$(app_for Dogfood)" "$unmarked"
plutil -remove PCContentChannel "$unmarked/Info.plist"
if bash scripts/check-release-content.sh "$unmarked" >/dev/null 2>&1; then
  echo "FAIL: a build with no PCContentChannel was allowed through" >&2
  exit 1
fi

echo "==> Content gate: accepts an all-reviewed store build"
reviewed="$scratch/reviewed.app"
cp -R "$(app_for Release)" "$reviewed"
plutil -replace PCContentChannel -string store "$reviewed/Info.plist"
python3 - "$reviewed/CoreStrategyPack.json" <<'PYTHON'
import json
import sys

path = sys.argv[1]
pack = json.load(open(path))
pack["manifest"]["reviewStatus"] = "reviewed"
pack["manifest"]["reviewedBy"] = "verify-m1c probe"
pack["manifest"]["reviewedAt"] = "2026-08-10T00:00:00Z"
json.dump(pack, open(path, "w"), ensure_ascii=False)
PYTHON
bash scripts/check-release-content.sh "$reviewed" >/dev/null

echo "==> The frozen event contract is untouched"
if ! git diff --quiet HEAD -- Contracts/; then
  echo "FAIL: M1C must not change Contracts/" >&2
  exit 1
fi
# The .sha256 file holds a bare digest, so compare it directly rather than
# through `shasum -c`, which expects a "digest  filename" line.
recorded="$(tr -d '[:space:]' < Contracts/training-event-upload-v1.sha256)"
actual="$(shasum -a 256 Contracts/training-event-upload-v1.json | awk '{print $1}')"
if [[ "$recorded" != "$actual" ]]; then
  echo "FAIL: Contracts/training-event-upload-v1.json does not match its recorded digest" >&2
  exit 1
fi

echo "==> Proposal preserves every existing requirement"
bash scripts/check-proposal-completeness.sh curriculum-m1c-adaptive-cash-20260810-01 >/dev/null

echo "==> M1C verification passed"
