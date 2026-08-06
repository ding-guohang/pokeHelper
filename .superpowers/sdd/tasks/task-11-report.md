# Task 11 Report

Status: implemented and verified.

- Today and Review refresh from the shared `TrainingEventStore`, then derive their display state through `PlayerModelReducer` and `TrainingPlanner`.
- Today presents one primary item, two supporting items, the deterministic planner reason, total duration, and scenario routing.
- Review sorts ability snapshots deterministically, exposes historical score / EV-loss / content-version details, and creates weak-area training.
- Learn shows the read-only M1A cash path and identifies MTT as a later milestone.
- Debug catalog entries are training-directory metadata only; they include no strategy frequencies, EV, ranges, or solver truth.

Verification:

- `TodayViewModelTests` and `ReviewViewModelTests`: pass.
- Full `PokerCoach` app test suite: pass.
- Release simulator build: pass.
