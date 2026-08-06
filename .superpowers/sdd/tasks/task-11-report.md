# Task 11 Report

Status: implemented and verified.

## Fix round 1

- Replaced the Debug-only catalog with `M1ALocalTrainingCatalog`, injected through `AppDependencies` so Debug and Release both generate directory plans without embedding strategy truth.
- Added explicit loading, loaded, empty, and recoverable failed states for Today and Review, including Chinese loading and actionable empty/error UI.
- Added deterministic Chinese ability names, raw `milliBB` EV-loss history, and a Review empty-state route to training.
- Added append-then-refresh regressions against one shared in-memory event store, plus catalog and state-contract tests.

## Fix round 2

- Today empty state now routes through the existing root training destination with an injected callback instead of retrying an immutable empty catalog.
- Added the empty-catalog refresh regression and a testable Chinese `前往训练` action contract; normal and failure-state actions are unchanged.

- Today and Review refresh from the shared `TrainingEventStore`, then derive their display state through `PlayerModelReducer` and `TrainingPlanner`.
- Today presents one primary item, two supporting items, the deterministic planner reason, total duration, and scenario routing.
- Review sorts ability snapshots deterministically, exposes historical score / EV-loss / content-version details, and creates weak-area training.
- Learn shows the read-only M1A cash path and identifies MTT as a later milestone.
- Local catalog entries are training-directory metadata only; they include no strategy frequencies, EV, ranges, or solver truth.

Verification:

- `TodayViewModelTests` and `ReviewViewModelTests`: pass.
- Full `PokerCoach` app test suite: pass.
- Release simulator build: pass.
