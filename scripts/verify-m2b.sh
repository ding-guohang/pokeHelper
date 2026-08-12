#!/usr/bin/env bash
#
# Verifies the M2B first slice: the hand-history parser, the conflict model, the
# versioned personal-hand library, and the layer boundary that keeps the parser
# from knowing teaching content exists and keeps an imported hand from becoming
# a training event.
#
# Every gate that can only pass is also run against a deliberately broken input.
# A gate with no observed failure is indistinguishable from one that always
# succeeds.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

change_id="handlab-m2b-import-preview-20260812-01"

scratch="$(mktemp -d)"
restore_list=()
restore() {
    local index=0
    while (( index < ${#restore_list[@]} )); do
        cp "${restore_list[index + 1]}" "${restore_list[index]}"
        index=$((index + 2))
    done
    rm -rf "$scratch"
}
trap restore EXIT

# Saves a file so a deliberate break can be undone even if the script dies.
guard() {
    local original="$1"
    local backup="$scratch/$(echo "$original" | tr '/' '_')"
    cp "$original" "$backup"
    restore_list+=("$original" "$backup")
}

echo "==> Generate the Xcode project"
xcodegen generate >/dev/null

for package in PokerCore StrategyContent TrainingDomain TrainingPersistence \
    StrategyTooling SessionSimulation SessionPersistence \
    HandHistory HandHistoryPersistence; do
    echo "==> Test $package"
    swift test --package-path "Packages/$package" >/dev/null
done

echo "==> Test the app"
xcodebuild test \
    -project PokerCoach.xcodeproj \
    -scheme PokerCoach \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
    -only-testing:PokerCoachTests >/dev/null

# A capability that is computed and never rendered passes every unit test it
# has. Only a UI test tells the two apart: this drives import, the standardized
# preview and the personal library through the built app.
echo "==> Hand Lab import, preview, library and analysis are reachable"
xcodebuild test \
    -project PokerCoach.xcodeproj \
    -scheme PokerCoach \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
    -only-testing:PokerCoachUITests/M2BSurfaceTests \
    -only-testing:PokerCoachUITests/M2BAnalysisSurfaceTests >/dev/null

echo "==> Package dependencies match the layer graph"
bash scripts/check-package-layering.sh >/dev/null

# The rule this slice exists to protect. Broken two ways, because the manifest
# can declare a dependency nothing imports and a file can import a module the
# manifest only reaches transitively.
echo "==> Layer gate: rejects a parser that can see teaching content"
guard Packages/HandHistory/Package.swift
python3 - <<'PY'
path = "Packages/HandHistory/Package.swift"
text = open(path).read()
marker = '.package(path: "../PokerCore"),'
assert text.count(marker) == 1
open(path, "w").write(
    text.replace(marker, marker + '\n        .package(path: "../SessionSimulation"),')
)
PY
if bash scripts/check-package-layering.sh >/dev/null 2>&1; then
    echo "FAIL: the layer gate accepted HandHistory depending on SessionSimulation" >&2
    exit 1
fi
cp "$scratch/Packages_HandHistory_Package.swift" Packages/HandHistory/Package.swift

echo "==> Layer gate: rejects a parser that imports teaching content"
guard Packages/HandHistory/Sources/HandHistory/PokerStarsParser.swift
printf 'import StrategyContent\n' | cat - \
    "$scratch/Packages_HandHistory_Sources_HandHistory_PokerStarsParser.swift" \
    > Packages/HandHistory/Sources/HandHistory/PokerStarsParser.swift
if bash scripts/check-package-layering.sh >/dev/null 2>&1; then
    echo "FAIL: the layer gate accepted an import of StrategyContent from the parser" >&2
    exit 1
fi
cp "$scratch/Packages_HandHistory_Sources_HandHistory_PokerStarsParser.swift" \
    Packages/HandHistory/Sources/HandHistory/PokerStarsParser.swift

# The parsed model's canonical serialization is committed as a golden. If the
# committed bytes and a fresh parse disagree, either the parser drifted or the
# golden is stale; either way the byte-for-byte determinism claim is dead.
echo "==> The committed model golden equals a fresh parse"
golden="Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.model.json"
fixture="Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.txt"
swift build --package-path Packages/HandHistory --product hand-model-writer >/dev/null
writer_bin="$(swift build --package-path Packages/HandHistory --product hand-model-writer --show-bin-path)/hand-model-writer"
if ! diff <("$writer_bin" --fixture "$fixture") "$golden" >/dev/null; then
    echo "FAIL: hand-model-writer output no longer matches the committed golden" >&2
    exit 1
fi

# And the golden is actually load-bearing: corrupt it and the suite must go red,
# or "equals the golden" was comparing against something nothing else reads.
echo "==> The model golden is load-bearing"
guard "$golden"
python3 - "$golden" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read().replace('"rakeCentiBB" : 50', '"rakeCentiBB" : 51', 1)
open(path, "w").write(text)
PY
if swift test --package-path Packages/HandHistory >/dev/null 2>&1; then
    echo "FAIL: the HandHistory suite passed with a corrupted model golden" >&2
    exit 1
fi
cp "$scratch/Packages_HandHistory_Tests_Fixtures_sample-ps-6max-nlhe.model.json" "$golden"

# The hero decision signatures have their own committed golden, produced by the
# same writer under --signatures. Same two checks: it matches a fresh derivation
# and it is load-bearing.
echo "==> The committed signatures golden equals a fresh derivation"
sig_golden="Packages/HandHistory/Tests/Fixtures/sample-ps-6max-nlhe.signatures.json"
if ! diff <("$writer_bin" --signatures --fixture "$fixture") "$sig_golden" >/dev/null; then
    echo "FAIL: hand-model-writer --signatures output no longer matches the committed golden" >&2
    exit 1
fi

echo "==> The signatures golden is load-bearing"
guard "$sig_golden"
python3 - "$sig_golden" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
# Flip the first stack-bucket value; any real hero signature carries one.
for marker in ('"stackBucket" : "deep"', '"stackBucket" : "medium"', '"stackBucket" : "short"'):
    if marker in text:
        text = text.replace(marker, '"stackBucket" : "shallowest"', 1)
        break
open(path, "w").write(text)
PY
if swift test --package-path Packages/HandHistory >/dev/null 2>&1; then
    echo "FAIL: the HandHistory suite passed with a corrupted signatures golden" >&2
    exit 1
fi
cp "$scratch/Packages_HandHistory_Tests_Fixtures_sample-ps-6max-nlhe.signatures.json" "$sig_golden"

echo "==> Cross-process determinism really uses a second process"
if ! grep -rq "hand-model-writer" Packages/HandHistory/Tests; then
    echo "FAIL: no test shells out to hand-model-writer, so determinism is only" >&2
    echo "      being observed inside one process" >&2
    exit 1
fi

echo "==> The frozen event contract is untouched"
contract_base="$(git log --diff-filter=A --format=%H -1 -- \
    "openspec/changes/$change_id/proposal.md")"
if [[ -z $contract_base ]]; then
    echo "FAIL: cannot locate the commit that introduced this change's proposal," >&2
    echo "      so 'the contract did not move during M2B' cannot be checked" >&2
    exit 1
fi
if ! git diff --quiet "$contract_base^..HEAD" -- Contracts/; then
    echo "FAIL: Contracts/ changed during M2B; the event contract is frozen" >&2
    git diff --stat "$contract_base^..HEAD" -- Contracts/ >&2
    exit 1
fi

echo "==> The reviewed content pack matches its recorded digest"
recorded="$(tr -d '[:space:]' < PokerCoach/Resources/CoreStrategyPack.sha256)"
actual="$(shasum -a 256 PokerCoach/Resources/CoreStrategyPack.json | cut -d' ' -f1)"
if [[ $recorded != "$actual" ]]; then
    echo "FAIL: CoreStrategyPack.json does not match its sidecar" >&2
    exit 1
fi

echo "==> Proposal preserves every existing requirement"
bash scripts/check-proposal-completeness.sh "$change_id"

echo "==> Earlier milestones still pass"
bash scripts/verify-m1a.sh >/dev/null
bash scripts/verify-m1c.sh >/dev/null
bash scripts/verify-m2a.sh >/dev/null

echo "==> M2B verification passed"
