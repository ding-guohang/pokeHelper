#!/usr/bin/env bash
#
# Verifies the M2A slice: the simulation engine, the opponent table, session
# records, and the layer boundary that keeps the engine from knowing teaching
# content exists.
#
# Every gate that can only pass is also run against a deliberately broken
# input. A gate with no observed failure is indistinguishable from one that
# always succeeds, and this milestone has already produced three of those.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

change_id="session-m2a-cash-simulation-20260810-01"

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
    StrategyTooling SessionSimulation SessionPersistence; do
    echo "==> Test $package"
    swift test --package-path "Packages/$package" >/dev/null
done

echo "==> Test the app"
xcodebuild test \
    -project PokerCoach.xcodeproj \
    -scheme PokerCoach \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
    -only-testing:PokerCoachTests >/dev/null

echo "==> Package dependencies match the layer graph"
bash scripts/check-package-layering.sh >/dev/null

# The rule this milestone exists to protect. Broken two ways, because the
# manifest can declare a dependency nothing imports and a file can import a
# module the manifest only reaches transitively.
echo "==> Layer gate: rejects an engine that can see teaching content"
guard Packages/SessionSimulation/Package.swift
python3 - <<'PY'
path = "Packages/SessionSimulation/Package.swift"
text = open(path).read()
marker = '.package(path: "../PokerCore"),'
assert text.count(marker) == 1
open(path, "w").write(
    text.replace(marker, marker + '\n        .package(path: "../StrategyContent"),')
)
PY
if bash scripts/check-package-layering.sh >/dev/null 2>&1; then
    echo "FAIL: the layer gate accepted SessionSimulation depending on StrategyContent" >&2
    exit 1
fi
cp "$scratch/Packages_SessionSimulation_Package.swift" Packages/SessionSimulation/Package.swift

echo "==> Layer gate: rejects an engine that imports teaching content"
guard Packages/SessionSimulation/Sources/SessionSimulation/Deck.swift
printf 'import StrategyContent\n' | cat - \
    "$scratch/Packages_SessionSimulation_Sources_SessionSimulation_Deck.swift" \
    > Packages/SessionSimulation/Sources/SessionSimulation/Deck.swift
if bash scripts/check-package-layering.sh >/dev/null 2>&1; then
    echo "FAIL: the layer gate accepted an import of StrategyContent from the engine" >&2
    exit 1
fi
cp "$scratch/Packages_SessionSimulation_Sources_SessionSimulation_Deck.swift" \
    Packages/SessionSimulation/Sources/SessionSimulation/Deck.swift

# Replay determinism rests on seed, dealing and the opponent behaviour table.
# Changing the third without bumping its version makes recorded sessions replay
# differently while every other assertion still passes, so the goldens are
# bound to the version and this checks that binding is live.
echo "==> Opponent goldens are bound to the behaviour table version"
guard Packages/SessionSimulation/Sources/SessionSimulation/OpponentProfile.swift
python3 - <<'PY'
path = "Packages/SessionSimulation/Sources/SessionSimulation/OpponentProfile.swift"
text = open(path).read()
marker = 'public static let version = "1"'
assert text.count(marker) == 1, marker
open(path, "w").write(text.replace(marker, 'public static let version = "2"'))
PY
if swift test --package-path Packages/SessionSimulation >/dev/null 2>&1; then
    echo "FAIL: the opponent goldens passed with a version the fixtures do not name" >&2
    exit 1
fi
cp "$scratch/Packages_SessionSimulation_Sources_SessionSimulation_OpponentProfile.swift" \
    Packages/SessionSimulation/Sources/SessionSimulation/OpponentProfile.swift

echo "==> Cross-process determinism really uses a second process"
if ! grep -rq "session-transcript" Packages/SessionSimulation/Tests; then
    echo "FAIL: no test shells out to the transcript binary, so determinism is" >&2
    echo "      only being observed inside one process, where per-process hash" >&2
    echo "      seeding and SystemRandomNumberGenerator are both stable" >&2
    exit 1
fi
swift build --package-path Packages/SessionSimulation --product session-transcript >/dev/null

echo "==> The frozen event contract is untouched"
contract_base="$(git log --diff-filter=A --format=%H -1 -- \
    "openspec/changes/$change_id/proposal.md")"
if [[ -z $contract_base ]]; then
    echo "FAIL: cannot locate the commit that introduced this change's proposal," >&2
    echo "      so 'the contract did not move during M2A' cannot be checked" >&2
    exit 1
fi
if ! git diff --quiet "$contract_base^..HEAD" -- Contracts/; then
    echo "FAIL: Contracts/ changed during M2A; the event contract is frozen" >&2
    git diff --stat "$contract_base^..HEAD" -- Contracts/ >&2
    exit 1
fi

echo "==> The reviewed content pack matches its recorded digest"
recorded="$(tr -d '[:space:]' < PokerCoach/Resources/CoreStrategyPack.sha256)"
actual="$(shasum -a 256 PokerCoach/Resources/CoreStrategyPack.json | cut -d' ' -f1)"
if [[ $recorded != "$actual" ]]; then
    echo "FAIL: CoreStrategyPack.json does not match its sidecar" >&2
    echo "      recorded $recorded" >&2
    echo "      actual   $actual" >&2
    exit 1
fi

echo "==> Proposal preserves every existing requirement"
bash scripts/check-proposal-completeness.sh "$change_id"

echo "==> Earlier milestones still pass"
bash scripts/verify-m1a.sh >/dev/null
bash scripts/verify-m1c.sh >/dev/null

echo "==> M2A verification passed"
