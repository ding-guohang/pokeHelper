# Task 13 Implementation Report

## Status

PASS — Task 13 is implemented and committed as `09797cf` (`docs: add m1a verification and module handoff`).

## Scope delivered

- Added executable `scripts/verify-m1a.sh`.
  - Generates `PokerCoach.xcodeproj`.
  - Runs PokerCore, StrategyContent, and TrainingDomain package tests.
  - Runs all `PokerCoachTests`.
  - Runs `CashCoachHappyPathTests` on iPhone.
  - Runs `IPadLayoutTests` on iPad.
  - Prefers `iPad Pro 13-inch (M4)`, falls back to same-size `(M5)`, and fails explicitly if neither is available.
  - Supports `M1A_IPHONE_DESTINATION` and `M1A_IPAD_DESTINATION` overrides and prints the actual destinations.
  - Builds Release Simulator into a `mktemp -d` DerivedData directory guarded by an exact-prefix cleanup trap.
  - Fails if `DevStrategyPack.json` exists anywhere in that verification-specific DerivedData.
  - Runs `git diff --check`.
- Added `README.md` with required tool versions, generation/verification commands, Debug fixture launch/reset instructions, the unreviewed-strategy warning, destination selection/override behavior, and design/roadmap links.
- Added `docs/architecture/m1a-module-boundaries.md`.
  - The exhaustive M1B dependency list is exactly `TrainingEvent`, `TrainingEventStore`, `FileTrainingEventStore`, and `StrategyPackManifest`.
  - Remote synchronization is constrained to App Infrastructure around those contracts.
  - HTTP, authentication, and API/database DTOs are forbidden from PokerCore, StrategyContent, and TrainingDomain.
  - The M3-reusable `SolverAssumptions.tableSize` + `DecisionScenario.heroSeatOffsetFromButton` 2–9 player position contract is recorded with its source location and semantics.

## Focused validation before commit

- RED check: failed with exit 1 because the Task 13 files/behavior were absent.
- `bash -n scripts/verify-m1a.sh`: exit 0.
- Executable-bit, README requirement, module-contract, and script-command assertions: exit 0.
- `git diff --check`: exit 0.
- Only the three intended deliverable files were staged.

## Clean-checkout full verification after commit

Command: `bash scripts/verify-m1a.sh`

Result: exit 0; final output was `==> M1A verification passed`.

- XcodeGen generation: PASS.
- Destination selection:
  - iPhone: `platform=iOS Simulator,name=iPhone 16 Pro,OS=latest`.
  - iPad: `platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest` via automatic M5 fallback because no available M4 simulator was present.
- PokerCore package tests: PASS.
- StrategyContent package tests: PASS.
- TrainingDomain package tests: PASS.
- App unit tests: PASS, 40 executed, 0 failures.
- iPhone cash-coach happy-path UI: PASS, 1 executed, 0 failures.
- iPad layout UI: PASS, 1 executed, 0 failures.
- Release Simulator build in dedicated temporary DerivedData: PASS (`** BUILD SUCCEEDED **`).
- Release exclusion: PASS; `DevStrategyPack.json` absent.
- Script `git diff --check`: PASS.
- Temporary DerivedData cleanup: PASS; the exact generated path no longer existed after script exit.

## Final repository checks

- `git diff --check`: exit 0.
- `git status --short`: empty.
- HEAD: `09797cf`.

## Concerns

No blocking concerns. The host currently exposes M5, not M4, so the required M5 fallback path was exercised. Xcode emitted non-fatal App Intents metadata and simulator launch-screen warnings; no build or test failed.

## Review fix round — M3 position contract

- Resolved the Important review finding that the handoff text incorrectly described heads-up offset `1` as `SB`.
- Verified against `Packages/PokerCore/Sources/PokerCore/TablePosition.swift` and `TablePositionTests.swift`: `tableSize == 2` maps `0 → BTN/SB`, `1 → BB`; `tableSize >= 3` maps `0 → BTN`, `1 → SB`, `2 → BB`.
- Clarified that the valid offset range is always `0..<tableSize`.
- Scope remained documentation-only; no business code changed and the full M1A verification was not rerun per review-fix instruction.
- Focused contract assertions and `git diff --check`: PASS.
