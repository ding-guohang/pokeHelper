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

## Task 3 — same-snapshot frequencies and conditional EVs

Completed 2026-08-13 (taken over after the parallel session was stopped).

Implementation decisions:

- The export is a NEW bin (`main_hu_export.rs`) dropped into the verified
  checkout; it touches no hash-locked source and uses only the public API
  (`cfr::train`, `PushFoldNode::{new,play}`, `GameNode::evaluate`), so the
  equilibrium and update formulas are exactly upstream's.
- Same-snapshot conditional EVs are computed by calling the upstream terminal
  `evaluate()` on the `[0]`/`[1,0]`/`[1,1]` nodes with equilibrium reach
  vectors, which is already blocker/card-removal aware:
  SB `N_jam = evaluate([1,0],0,σ_BB_fold) + evaluate([1,1],0,σ_BB_call)`,
  `D_SB = -2·evaluate([0],0,ones)` (constant 1/1326);
  BB `N_call = evaluate([1,1],1,σ_SB_jam)`, `D_BB = -evaluate([1,0],1,σ_SB_jam)`.
  Aggregation to 169 is ratio-of-sums (`ΣN/ΣD`); quantization (bps, milli-BB)
  is `f64::round` (half-away-from-zero) and only at the end.
- `game_node.rs` was added to `source-lock.json` — it compiles into the export
  binary, so provenance must cover it (hash `3942c963…`).
- `generate-hu-pushfold.py` uses a pinned `git` checkout and verifies EVERY
  locked hash (fail-closed), because building the export bin needs the complete
  crate (game_node.rs and valid `[[bin]]` paths), which the minimal
  pinned-URL fetch set does not provide. `fetch-locked-source.py` remains the
  tested pinned-URL primitive.
- Deviation from the plan's Task 3 Step 5: the Rust exporter enforces the SB/BB
  fold-EV invariants (−0.5/−1.0 bb) and NashConv≤threshold, but does not
  re-derive NashConv or reconstruct full profile EV in-binary (that would
  duplicate the private `compute_exploitability`); `train` already returns
  NashConv, and independent JSON-only checks live in the Task 4 validator.
- Verified: depth-10 NashConv 3.855e-8 matches the upstream `push_fold`
  reference; AA/22/ATs jam, 72o folds; SB fold EV −500, BB fold EV −1000;
  169 rows; 1BB omits Call-Jam; cross-run bytes identical.
