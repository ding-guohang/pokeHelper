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

## Tasks 4–7 — validation, exports, import, and the real batch

Completed 2026-08-13.

- Task 4 validator is JSON-only (no solver import); 13 cases cover coverage,
  bps totals, key vocabulary, null EV, fold-EV invariants, snapshot hash,
  NashConv threshold, testOnly, and source-hash mismatch.
- Task 5 exporter builds one immutable SolverExport per depth. Betting-context
  edge case at 1BB: the SB has exactly the call behind, so `legalActions`
  yields `call` (all-in call), not `allIn` — the 1BB open node therefore uses
  `call` / range key `call`; depths ≥2 use `allIn` / range key `raise`.
- Task 6 import wrapper is fixed to `unverifiedDraft`/`solver` with no
  review-status flag; strategy-import gains a defence-in-depth guard rejecting
  reviewed tournament content.
- `rakeDescription` must be exactly `rake=0` (the validator's `isZeroRake`
  accepts only `0`/`rake=0`/`rake 0`).
- Task 7 real batch: all 20 depths converged at the first 10,000-iteration
  checkpoint (NashConv 2e-8…2e-7, max 2.135e-7, well under 0.001). Validator:
  20 depths / 39 tables / 6591 rows PASS. 20 unverified `origin=solver` packs
  imported; AA open-jam raise EV +2978 milli-BB at 10BB. Golden manifest binds
  locked source, normalized, export, and pack hashes. `scripts/verify-tournament-content.sh`
  regenerates and byte-compares end to end.
