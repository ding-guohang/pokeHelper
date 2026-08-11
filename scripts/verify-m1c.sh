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

change_id="curriculum-m1c-adaptive-cash-20260810-01"

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

echo "==> Test TrainingPersistence"
swift test --package-path Packages/TrainingPersistence >/dev/null

echo "==> Test StrategyTooling (includes cross-process import determinism)"
swift test --package-path Packages/StrategyTooling >/dev/null

echo "==> Test PokerCoach unit tests"
xcodebuild test \
  -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests >/dev/null

echo "==> Test the M1C surfaces through the UI"
# Included deliberately: a UI test is the only thing that distinguishes a view
# model whose output is rendered from one whose output nothing reads, which is
# how the diagnostic shipped computed and invisible.
#
# Scoped to the iPhone destination and to M1C's own class; the iPad layout test
# belongs to verify-m1a.sh, which runs it against an iPad.
xcodebuild test \
  -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachUITests/M1CSurfaceTests >/dev/null

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
  --origin "$(manifest_field origin)"
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

echo "==> Each configuration stamps the channel it is supposed to"
# Without this nothing ties a configuration to its channel: setting
# PC_CONTENT_CHANNEL to dogfood in Release.xcconfig, or deleting the line, used
# to leave every check downstream green.
expected_channel() {
  case "$1" in
    Debug) echo debug ;;
    Dogfood) echo dogfood ;;
    Release) echo store ;;
  esac
}
for config in Debug Dogfood Release; do
  actual="$(plutil -extract PCContentChannel raw "$(app_for "$config")/Info.plist" 2>/dev/null || true)"
  expected="$(expected_channel "$config")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $config produced channel '${actual:-<missing>}', expected '$expected'" >&2
    exit 1
  fi
done

echo "==> Content gate: every channel carries only what it is allowed to"
for config in Debug Dogfood Release; do
  bash scripts/check-release-content.sh "$(app_for "$config")"
done

echo "==> Content gate: rejects unverified content on the store channel"
# The unverified pack is synthesised rather than borrowed from the dogfooding
# build. Relying on a configuration to happen to carry unverified content makes
# the probe stop probing the day that content is removed -- and report success
# while doing it.
probe="$scratch/probe.app"
cp -R "$(app_for Release)" "$probe"
plutil -replace PCContentChannel -string store "$probe/Info.plist"
python3 - "$probe" <<'PYTHON'
import json
import pathlib
import sys

app = pathlib.Path(sys.argv[1])
pack = json.loads((app / "CoreStrategyPack.json").read_text())
pack["manifest"]["id"] = "probe-unverified"
pack["manifest"]["reviewStatus"] = "unverifiedDraft"
pack["manifest"]["reviewedBy"] = None
pack["manifest"]["reviewedAt"] = None
(app / "ProbeStrategyPack.json").write_text(
    json.dumps(pack, ensure_ascii=False)
)
PYTHON
if bash scripts/check-release-content.sh "$probe" >/dev/null 2>&1; then
  echo "FAIL: the store channel accepted unverifiedDraft content" >&2
  exit 1
fi

echo "==> Content gate: fails closed when the channel marker is missing"
unmarked="$scratch/unmarked.app"
cp -R "$(app_for Release)" "$unmarked"
plutil -remove PCContentChannel "$unmarked/Info.plist"
if bash scripts/check-release-content.sh "$unmarked" >/dev/null 2>&1; then
  echo "FAIL: a build with no PCContentChannel was allowed through" >&2
  exit 1
fi

echo "==> Content gate: rejects a pack that does not match its own digest"
# Rewriting an EV leaves the review status intact, so a gate reading only the
# manifest passes a pack that would misgrade every answer.
tampered="$scratch/tampered.app"
cp -R "$(app_for Release)" "$tampered"
python3 - "$tampered/CoreStrategyPack.json" <<'PYTHON'
import json
import sys

path = sys.argv[1]
pack = json.load(open(path))
pack["scenarios"][0]["options"][0]["ev"]["milliBB"] = 999_999
json.dump(pack, open(path, "w"), ensure_ascii=False)
PYTHON
if bash scripts/check-release-content.sh "$tampered" >/dev/null 2>&1; then
  echo "FAIL: a pack whose bytes no longer match its digest was accepted" >&2
  exit 1
fi

echo "==> Content gate: rejects unverified content under any filename"
# The Release xcconfig excludes unverified content by filename. If this gate
# also keyed on filenames the two would fail open together on a rename.
renamed="$scratch/renamed.app"
cp -R "$probe" "$renamed"
mv "$renamed/ProbeStrategyPack.json" "$renamed/depth-6max-100bb.json"
if bash scripts/check-release-content.sh "$renamed" >/dev/null 2>&1; then
  echo "FAIL: renaming the unverified pack defeated the gate" >&2
  exit 1
fi

echo "==> The frozen event contract is untouched"
# Compared across the change's whole commit range, not working tree against
# HEAD: the latter goes blind the moment an edit is committed, which is exactly
# when it matters.
change_base="$(
  git log --diff-filter=A --format=%H \
    -- "openspec/changes/$change_id/proposal.md" | tail -1
)"
if [[ -z "$change_base" ]]; then
  echo "FAIL: cannot locate the commit that introduced this change's proposal" >&2
  exit 1
fi
if ! git diff --quiet "$change_base^..HEAD" -- Contracts/; then
  echo "FAIL: this change must not touch Contracts/" >&2
  git diff --stat "$change_base^..HEAD" -- Contracts/ >&2
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
bash scripts/check-proposal-completeness.sh "$change_id"

echo "==> M1C verification passed"
