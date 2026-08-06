# Poker Coach Implementation Roadmap

> **For agentic workers:** This roadmap separates the approved product design into independently reviewable plans. Each plan must be executed with `superpowers:subagent-driven-development` or `superpowers:executing-plans`.

**Design source:** `docs/superpowers/specs/2026-08-06-texas-holdem-coach-design.md`

## Why the work is split

The approved product contains independent rule, content, training, synchronization, simulation, import, tournament, and commerce subsystems. Combining them into one implementation plan would prevent useful review gates and make failures difficult to isolate. The plans below are ordered so every accepted plan leaves behind working, testable software.

## Plan sequence

| Order | Plan | Independently testable result | Product milestone |
|---|---|---|---|
| 1 | M1A Offline Cash Coach Vertical Slice | Native iPhone/iPad app with a deterministic cash-game decision, professional feedback, local event history, and four-tab navigation | M1 |
| 2 | M1B Independent Identity and Sync | Apple/email sign-in, Go API, PostgreSQL event store, idempotent outbox sync, device sessions, export, and deletion | M1 |
| 3 | M1C Adaptive Cash Curriculum | Initial diagnostic, cash-game skill tree, reviewed strategy packs, ability profile, spaced repetition, and daily plan | M1 |
| 4 | M2A Cash Session Simulation | Seeded dealing, legal betting state, four virtual opponent profiles, 15/30/60-hand sessions, and key-hand selection | M2 |
| 5 | M2B Personal Hand Lab | Text hand-history parsers, conflict preview, manual scenario builder, branching replay, and generated remediation drills | M2 |
| 6 | M3 Tournament Extension | Ante and blind progression, 40/20/10BB content, push/fold, rejam, tournament runs, bubble and final-table ICM | M3 |
| 7 | M4 Commercial Release | Production content operations, StoreKit subscriptions, entitlements, consented analytics, privacy material, and App Store release hardening | M4 |

## Authoring rule

Only the next executable plan is written at step-level detail. After a plan is implemented and accepted, the following plan is written against the actual codebase and interfaces that now exist. This prevents speculative file paths and signatures from becoming stale.

The first executable plan is:

`docs/superpowers/plans/2026-08-06-m1a-offline-cash-coach.md`

## Milestone gates

### M1 gate

M1 is complete only after M1A, M1B, and M1C all pass. In particular, the offline slice does not waive the approved requirement that independent identity and cloud synchronization begin in M1.

### M2 gate

M2 begins only after the M1 ability model and synchronization event schema are stable. Simulation and hand-history import must emit the same versioned `TrainingEvent` contract as cash drills.

### M3 gate

M3 reuses the accepted poker state, strategy-pack, scoring, and player-model interfaces. Tournament-only state is added without changing historical cash-game grades.

### M4 gate

M4 starts only after four weeks of owner dogfooding satisfy the approved validation criteria. Subscription packaging must not redesign the learning loop.

