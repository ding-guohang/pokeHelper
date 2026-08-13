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

## Task 2 — locked solver provenance

Completed 2026-08-13.

Compatibility decisions:

- Solver inputs are fetched from immutable Git blob URLs at the locked commit;
  `Cargo.toml`, `Cargo.lock`, relevant Rust sources, and the equity binary each
  require a recorded SHA-256 before a fresh source directory is atomically
  published.
- A mismatch, malformed lock, failed fetch, or existing destination fails
  closed and leaves no partial source tree at the requested destination.
