#!/usr/bin/env bash
#
# Enforces the package dependency rules in docs/architecture/layering.md.
#
# Documentation does not stop an import. The rule that SessionSimulation cannot
# see StrategyContent is the one the M2A design exists to protect, and it is
# exactly the rule a hurried change breaks: the cheapest way to answer "is this
# decision point worth comparing against content?" is to look the answer up
# inside the engine, at which point the answer stops being a fact about the
# hand. The reverse direction is worse — it closes an import cycle.
#
# Checked two ways, because either alone can pass while the rule is broken:
# the manifest can list a dependency no file imports yet, and a file can import
# a module the manifest reaches transitively.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

fail() {
    printf '  FORBIDDEN  %s\n' "$1"
    status=1
}

# Walk the source files directly rather than parsing the manifest's graph:
# a manifest can list a dependency nothing imports, and a file can import a
# module the manifest only reaches transitively.
check_imports() {
    local package="$1"
    shift
    # `${a[@]+...}` rather than `${a[@]}`: macOS ships bash 3.2, where
    # expanding an empty array under `set -u` is an error, and PokerCore is
    # deliberately called with no permitted dependencies at all.
    local allowed=("$@")

    while IFS= read -r file; do
        while IFS= read -r module; do
            local permitted=0
            for candidate in ${allowed[@]+"${allowed[@]}"}; do
                [[ $module == "$candidate" ]] && permitted=1
            done
            case $module in
            "$package" | Foundation | Testing | XCTest | Synchronization | Observation | SwiftUI | CryptoKit) permitted=1 ;;
            esac
            (( permitted )) || fail "$file imports $module"
        done < <(sed -nE 's/^ *(@testable )? *import ([A-Za-z_]+) *$/\2/p' "$file")
    done < <(find "Packages/$package/Sources" "Packages/$package/Tests" \
        -name '*.swift' -not -path '*/.build/*' 2>/dev/null)
}

check_manifest() {
    local package="$1"
    shift
    # `${a[@]+...}` rather than `${a[@]}`: macOS ships bash 3.2, where
    # expanding an empty array under `set -u` is an error, and PokerCore is
    # deliberately called with no permitted dependencies at all.
    local allowed=("$@")
    local manifest="Packages/$package/Package.swift"

    while IFS= read -r dependency; do
        local permitted=0
        for candidate in ${allowed[@]+"${allowed[@]}"}; do
            [[ $dependency == "$candidate" ]] && permitted=1
        done
        (( permitted )) || fail "$manifest declares a dependency on $dependency"
    done < <(grep -oE '\.package\(path: "\.\./[A-Za-z]+"\)' "$manifest" |
        sed -E 's|.*\.\./||; s|"\)||')
}

echo "==> SessionSimulation may only see PokerCore"
check_manifest SessionSimulation PokerCore
check_imports SessionSimulation PokerCore

# Session records go through this package, and it must not be able to reach a
# TrainingEvent. "Session hands never produce a training event" is asserted by a
# test that plays a whole session; this is the structural half of the same
# claim, and the cheaper half to keep true.
echo "==> SessionPersistence may only see SessionSimulation and PokerCore"
check_manifest SessionPersistence PokerCore SessionSimulation
check_imports SessionPersistence PokerCore SessionSimulation

echo "==> TrainingDomain may not see SessionSimulation"
check_manifest TrainingDomain PokerCore StrategyContent
check_imports TrainingDomain PokerCore StrategyContent

# The concrete event store lives outside the domain package, and the gate is
# what keeps it outside: the dependency runs persistence -> domain and never
# back, so nothing in TrainingDomain can reach a file. Listed with its
# permitted set rather than left unchecked, because an unlisted package is one
# nothing stops from importing StrategyContent or SessionSimulation.
echo "==> TrainingPersistence may only see TrainingDomain and PokerCore"
check_manifest TrainingPersistence PokerCore TrainingDomain
check_imports TrainingPersistence PokerCore TrainingDomain

echo "==> StrategyContent may not see SessionSimulation or TrainingDomain"
check_manifest StrategyContent PokerCore
check_imports StrategyContent PokerCore

# The hand-history parser only knows poker facts. Letting it see StrategyContent
# or the training domain would make "what a real hand was" depend on what the
# curriculum happens to teach — the same boundary SessionSimulation keeps.
echo "==> HandHistory may only see PokerCore"
check_manifest HandHistory PokerCore
check_imports HandHistory PokerCore

# The personal-hand file store sits outside the parser package, like the two
# other persistence packages, and must not reach the training domain — that is
# the structural half of "an imported hand produces no TrainingEvent."
echo "==> HandHistoryPersistence may only see HandHistory and PokerCore"
check_manifest HandHistoryPersistence PokerCore HandHistory
check_imports HandHistoryPersistence PokerCore HandHistory

# The tournament engine only knows poker facts — blind levels, chips, depth. It
# must not reach the cash engine or teaching content, the same boundary
# SessionSimulation and HandHistory keep.
echo "==> TournamentEngine may only see PokerCore"
check_manifest TournamentEngine PokerCore
check_imports TournamentEngine PokerCore

echo "==> PokerCore depends on nothing in this repository"
check_manifest PokerCore
check_imports PokerCore

echo "==> Entitlements depends on nothing in this repository"
check_manifest Entitlements
check_imports Entitlements

if (( status )); then
    echo
    echo "See docs/architecture/layering.md. These are not style rules:"
    echo "SessionSimulation seeing StrategyContent turns 'is this spot worth"
    echo "comparing?' into an engine lookup, and the reverse closes a cycle."
    exit 1
fi

echo "package dependencies match the layer graph"
