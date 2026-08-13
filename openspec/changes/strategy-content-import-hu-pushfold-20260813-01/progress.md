# Progress

## Task 1 — additive tournament content schema

Completed 2026-08-13.

Compatibility decisions:

- Tournament data is optional on `SolverAssumptions`, `SolverExport`, and range
  cells so schema-1 cash packs decode without invented tournament assumptions.
- Tournament-specific validation is activated only when tournament assumptions
  are present; legacy cash range semantics remain unchanged.
- `decisionEffectiveStack` affects only the constructed decision context. The
  scenario's declared effective stack and tournament depth remain the export's
  source values, preventing an importer-side derivation from rewriting solver
  metadata.
