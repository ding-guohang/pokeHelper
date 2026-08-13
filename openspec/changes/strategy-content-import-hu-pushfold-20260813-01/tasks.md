---
name: strategy-content-import-hu-pushfold-20260813-01
status: planned
---

# HU Push/Fold Solver Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and import a reproducible, solver-origin, unverified HU
ChipEV push/fold content pack for every integer depth from 1BB through 20BB,
including 169-class frequencies and per-action milli-BB EVs.

**Architecture:** A locked BSD-2-Clause Rust CFR+ source produces combo-level
strategy and conditional pure-action EVs into normalized JSON. Independent
Python validation enforces provenance, convergence, reach normalization, 169
hand coverage, and batch atomicity. StrategyTooling converts each exact depth
into one immutable schema-1-compatible pack with additive tournament metadata.

**Tech Stack:** Rust/CFR+, Python 3 standard library, Swift 6.2/Swift Testing,
StrategyContent, StrategyTooling, CryptoKit SHA-256.

## Global Constraints

- Source is exactly `b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`,
  BSD-2-Clause, with locked input SHA-256 values from `design.md`.
- Game is NLHE tournament, heads-up, SB=0.5BB, BB=1BB, no ante, rake=0,
  chipEV, jam-or-fold only.
- Generate Open-Jam for every integer depth 1–20BB and Call-Jam for 2–20BB;
  one pack per depth; the 1BB pack has one scenario and 2–20BB packs have two.
- Frequencies are integer basis points summing to exactly 10,000 per hand
  class; EV is integer milli-BB.
- Solver output is always `origin=solver` and
  `reviewStatus=unverifiedDraft`; automated generation cannot emit `reviewed`.
- Rust is build-time tooling only and is not linked into the App.
- Existing schema-1 cash packs must continue to decode and retain their
  semantics and bytes.
- Do not modify `PokerCoach/Features/TournamentICM/`,
  `PokerCoachTests/TournamentICMViewModelTests.swift`, or
  `PokerCoachUITests/TournamentICMSurfaceTests.swift`.

---

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| tournament-strategy-source-adapter | 锁定并披露可复现来源 | 锁定来源生成 | 2 |
| tournament-strategy-source-adapter | 锁定并披露可复现来源 | 锁定来源发生变化 | 2 |
| tournament-strategy-source-adapter | 组合策略精确聚合为 169 手牌 | Open-Jam 聚合完整 | 3 |
| tournament-strategy-source-adapter | 组合策略精确聚合为 169 手牌 | Call-Jam 聚合完整 | 3 |
| tournament-strategy-source-adapter | 组合策略精确聚合为 169 手牌 | EV 不是求解器同源反事实值 | 3 |
| tournament-strategy-source-adapter | 行动 EV 与策略频率使用同一均衡快照 | 同一快照生成频率与 EV | 3 |
| tournament-strategy-source-adapter | 行动 EV 与策略频率使用同一均衡快照 | 快照或阻断处理不一致 | 3, 4 |
| tournament-strategy-source-adapter | 行动 EV 与策略频率使用同一均衡快照 | BB Jam 节点没有可达概率 | 3, 4 |
| tournament-strategy-source-adapter | 覆盖 1–20BB 且记录收敛质量 | 首批覆盖完整 | 5, 7 |
| tournament-strategy-source-adapter | 覆盖 1–20BB 且记录收敛质量 | 未达到收敛阈值 | 3, 5 |
| tournament-strategy-content-import | 导入完整且假设一致的 HU Push/Fold 批次 | 合法批次导入 | 5, 6 |
| tournament-strategy-content-import | 导入完整且假设一致的 HU Push/Fold 批次 | 批次缺少一张表 | 4, 5 |
| tournament-strategy-content-import | 导入完整且假设一致的 HU Push/Fold 批次 | 表含缺失、重复或非法手牌 | 4 |
| tournament-strategy-content-import | 未经人工审核不得晋升 | 首次导入保持未审核 | 5, 6 |
| tournament-strategy-content-import | 未经人工审核不得晋升 | 缺少人工签署时请求 reviewed | 6 |
| tournament-strategy-content-import | 商业平台手工导出走隔离入口 | 用户提供合法导出 | 8 |
| tournament-strategy-content-import | 商业平台手工导出走隔离入口 | 请求自动抓取商业平台 | 8 |
| strategy-content-pipeline | 求解器输出导入 | 合法求解器导出导入 | 1, 9 |
| strategy-content-pipeline | 求解器输出导入 | 求解器导出不满足语义约束 | 1, 9 |
| strategy-content-pipeline | 求解器输出导入 | 导入是确定性的 | 7, 9 |
| strategy-content-pipeline | 内容升级黄金回归 | 升级改变了评分结果 | 7, 9 |
| strategy-content-pipeline | 内容升级黄金回归 | 升级在容差内 | 7, 9 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 首次离线启动使用内置内容 | 9 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 校验通过且版本更高的更新包被采用 | 9 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包 checksum 不匹配 | 9 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包内容版本等于当前 | 9 |
| strategy-content-pipeline | 内容随包交付与可选更新 | 更新包内容版本低于当前 | 9 |
| strategy-content-pipeline | 锦标赛求解器输出导入 | 同一批次确定性导入 | 5, 7 |
| strategy-content-pipeline | 锦标赛求解器输出导入 | 原子失败 | 4, 5 |
| strategy-content-pipeline | 首批内容黄金回归基线 | 首次建立基线 | 7 |
| versioned-strategy-content | 策略包来源可追溯 | 合法策略包加载 | 1, 9 |
| versioned-strategy-content | 策略包来源可追溯 | checksum 不匹配 | 9 |
| versioned-strategy-content | 决策节点语义校验 | 频率总和错误 | 1, 9 |
| versioned-strategy-content | 决策节点语义校验 | 非法行动进入策略 | 1, 9 |
| versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核时间 | 1, 9 |
| versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核人 | 1, 9 |
| versioned-strategy-content | 审核状态约束 | 已审核内容元数据齐备 | 1, 9 |
| versioned-strategy-content | 审核状态约束 | 开发内容展示 | 9 |
| versioned-strategy-content | 审核状态约束 | 未审核内容必须披露 | 6, 9 |
| versioned-strategy-content | 内容版本不可原地修改 | 内容升级后历史仍可追溯 | 9 |
| versioned-strategy-content | 锦标赛求解假设可追溯 | 锦标赛假设加载 | 1 |
| versioned-strategy-content | 锦标赛求解假设可追溯 | 旧现金包兼容 | 1 |

## File Structure

| Path | Responsibility |
|---|---|
| `Packages/StrategyContent/Sources/StrategyContent/TournamentStrategyAssumptions.swift` | Tournament-only assumptions and equilibrium types |
| `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift` | Add optional tournament assumptions and range-cell action EVs |
| `Packages/StrategyContent/Sources/StrategyContent/StrategyPackValidator.swift` | Enforce tournament 169-class/frequency/EV semantics |
| `Packages/StrategyContent/Tests/StrategyContentTests/TournamentStrategyContentTests.swift` | New content model and legacy compatibility tests |
| `Packages/StrategyTooling/Sources/StrategyToolingCore/SolverExport.swift` | Add optional tournament metadata, decision stack, and range EVs |
| `Packages/StrategyTooling/Sources/StrategyToolingCore/PackBuilder.swift` | Preserve new fields without inference |
| `Packages/StrategyTooling/Tests/StrategyToolingCoreTests/TournamentPackBuilderTests.swift` | Exact-depth pack construction and validation tests |
| `Content/tournament/source-lock.json` | Locked upstream URLs, commit, license, hashes, toolchain |
| `Content/tournament/LICENSE-poker-cfr.txt` | Required BSD-2-Clause attribution |
| `Content/tournament/fetch-locked-source.py` | Download/cache and verify locked files |
| `Content/tournament/patches/poker-cfr-hu-export.patch` | Pure read-only strategy/EV JSON exporter patch |
| `Content/tournament/generate-hu-pushfold.py` | Apply patch, run checkpoints/depths, stage normalized batch |
| `Content/tournament/validate_hu_batch.py` | Independent normalized batch validator |
| `Content/tournament/tests/test_fetch_locked_source.py` | Provenance fail-closed tests |
| `Content/tournament/tests/test_validate_hu_batch.py` | Coverage, bps, EV, snapshot, and atomicity tests |
| `Content/build-tournament-exports.py` | Convert normalized batch to 20 SolverExport JSON files |
| `Content/import-tournament-packs.py` | Invoke strategy-import into a staged 20-pack directory |
| `Content/tournament/review-template.md` | Human strategy review evidence template |
| `Content/tournament/commercial-export/README.md` | Offline-only licensed-export contract |
| `Content/tournament/commercial-export/convert_local_export.py` | Reject network inputs and normalize documented local exports |
| `Content/tournament-normalized/*.json` | Solver-normalized truth, one file per depth |
| `Content/exports/tourn-hu-chip-ev-noante-*.json` | Deterministic StrategyTooling inputs |
| `Content/packs/tourn-hu-chip-ev-noante-*.json` | Unverified solver-origin app content |
| `Content/packs/tourn-hu-chip-ev-noante-*.sha256` | Per-pack checksums |
| `Content/tournament/golden-manifest.json` | Batch input hashes, pack hashes, coverage, convergence |
| `scripts/verify-tournament-content.sh` | End-to-end reproducibility and regression gate |
| `openspec/changes/strategy-content-import-hu-pushfold-20260813-01/progress.md` | Cross-task execution notes |

### Task 1: Additive tournament content schema | covers: versioned-strategy-content/锦标赛求解假设可追溯

**Files:**
- Create: `Packages/StrategyContent/Sources/StrategyContent/TournamentStrategyAssumptions.swift`
- Modify: `Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift`
- Modify: `Packages/StrategyContent/Sources/StrategyContent/StrategyPackValidator.swift`
- Modify: `Packages/StrategyTooling/Sources/StrategyToolingCore/SolverExport.swift`
- Modify: `Packages/StrategyTooling/Sources/StrategyToolingCore/PackBuilder.swift`
- Create: `Packages/StrategyContent/Tests/StrategyContentTests/TournamentStrategyContentTests.swift`
- Create: `Packages/StrategyTooling/Tests/StrategyToolingCoreTests/TournamentPackBuilderTests.swift`
- Create: `openspec/changes/strategy-content-import-hu-pushfold-20260813-01/progress.md`

**Interfaces:**
- Produces: `TournamentEquilibrium.chipEV`, `TournamentSolverAssumptions`,
  `SolverAssumptions.tournament`, `RangeCell.actionEVs`,
  `SolverExport.tournament`, `SolverNode.decisionEffectiveStack`,
  `SolverRangeCell.actionEVs`.

- [ ] **Step 1: Write failing StrategyContent tests**

```swift
@Test func tournamentScenarioRequiresAll169HandsAndActionEVs() throws {
    // GIVEN a valid legacy fixture copied with tournament assumptions and one range cell
    let pack = try TournamentStrategyFixture.pack(rangeCells: [
        .init(
            handClass: "AA",
            actionWeightsBasisPoints: ["fold": 0, "raise": 10_000],
            actionEVs: [
                "fold": .init(milliBB: -500),
                "raise": .init(milliBB: 1_250),
            ]
        ),
    ])
    // WHEN/THEN validation rejects incomplete tournament coverage
    #expect(throws: StrategyPackValidationError.self) {
        try StrategyPackValidator().validate(pack)
    }
}

@Test func legacyCashPackStillDecodesWithoutTournamentFields() throws {
    // GIVEN the checked-in schema-1 cash fixture
    let data = try Data(contentsOf: fixtureURL("valid-pack.json"))
    // WHEN decoded with the additive model
    let pack = try StrategyPackLoader().decode(data)
    // THEN no tournament assumptions are invented
    #expect(pack.scenarios[0].assumptions.tournament == nil)
    #expect(pack.scenarios[0].rangeCells.allSatisfy { $0.actionEVs == nil })
}
```

- [ ] **Step 2: Run tests and verify the missing API failure**

Run:
`swift test --package-path Packages/StrategyContent --filter TournamentStrategyContentTests`

Expected: compilation fails because `TournamentSolverAssumptions`,
`actionEVs`, and `tournament` do not exist.

- [ ] **Step 3: Add the minimal additive model**

```swift
public enum TournamentEquilibrium: String, Codable, Hashable, Sendable {
    case chipEV
    case icm
}

public struct TournamentSolverAssumptions: Codable, Hashable, Sendable {
    public let effectiveBigBlinds: Int
    public let smallBlindCentiBB: Int
    public let bigBlindCentiBB: Int
    public let hasAnte: Bool
    public let anteDescription: String
    public let equilibrium: TournamentEquilibrium
}

public struct RangeCell: Codable, Hashable, Sendable {
    public let handClass: String
    public let actionWeightsBasisPoints: [String: Int]
    public let actionEVs: [String: EVAmount]?
}
```

Add `tournament: TournamentSolverAssumptions? = nil` to
`SolverAssumptions`, mirror the optional fields in `SolverExport` and
`SolverRangeCell`, and add `decisionEffectiveStack: BBAmount?` to
`SolverNode`. `PackBuilder` uses
`node.decisionEffectiveStack ?? export.effectiveStack` only for the decision
context and passes all other values without derivation.

- [ ] **Step 4: Implement tournament-only validation**

Generate the canonical 169 notation set from ranks
`["A","K","Q","J","T","9","8","7","6","5","4","3","2"]`. When
`assumptions.tournament != nil`, require exactly that set once, require
frequency keys equal EV keys, allow exactly `fold+raise` or `fold+call`, and
require each frequency row to total 10,000. Reject non-positive depth/blinds,
`hasAnte == false` with an empty description, or exact depth inconsistent with
`effectiveStack.centiBB / 100`.

- [ ] **Step 5: Run affected package suites**

Run:

```bash
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/StrategyTooling
```

Expected: both exit 0; existing schema-1 cash tests pass unchanged.

- [ ] **Step 6: Record progress and commit**

Record only compatibility decisions in `progress.md`, then:

```bash
git add Packages/StrategyContent Packages/StrategyTooling \
  openspec/changes/strategy-content-import-hu-pushfold-20260813-01/progress.md
git commit -m "feat: add tournament strategy content metadata"
```

### Task 2: Lock and verify the solver source | covers: tournament-strategy-source-adapter/锁定并披露可复现来源

**Files:**
- Create: `Content/tournament/source-lock.json`
- Create: `Content/tournament/LICENSE-poker-cfr.txt`
- Create: `Content/tournament/fetch-locked-source.py`
- Create: `Content/tournament/tests/test_fetch_locked_source.py`

**Interfaces:**
- Produces: `fetch_locked_source(lock_path, destination, fetch_bytes)`;
  verified source directory consumed by Task 3.

- [ ] **Step 1: Write provenance failure tests**

```python
def test_hash_mismatch_leaves_destination_absent(tmp_path):
    lock = locked_manifest(tmp_path, sha256="00" * 32)
    destination = tmp_path / "source"
    with pytest_raises(SourceLockError, "sha256 mismatch"):
        fetch_locked_source(lock, destination, lambda _: b"changed")
    assert not destination.exists()

def test_locked_files_are_written_only_after_all_verify(tmp_path):
    lock = three_file_manifest(tmp_path)
    destination = tmp_path / "source"
    fetch_locked_source(lock, destination, bytes_for_locked_url)
    assert sha256(destination / "src/cfr.rs") == CFR_SHA256
    assert sha256(destination / "src/game_push_fold.rs") == GAME_SHA256
    assert sha256(destination / "static/heads_up_pre_flop_equity.bin") == EQUITY_SHA256
```

Use `unittest`, not a third-party pytest dependency; implement the
`pytest_raises` helper as `self.assertRaisesRegex`.

- [ ] **Step 2: Verify tests fail because the module is absent**

Run:
`python3 -m unittest Content.tournament.tests.test_fetch_locked_source -v`

Expected: import failure for `fetch_locked_source`.

- [ ] **Step 3: Implement locked fetch and manifest**

`source-lock.json` contains the exact commit, three raw GitHub URLs and hashes,
the upstream `Cargo.toml`/`Cargo.lock` hashes, BSD-2-Clause license URL/hash,
and Rust version. Download every file to a fresh `tempfile.TemporaryDirectory`,
verify all SHA-256 values, then use `os.replace` only after the complete staged
tree passes.

- [ ] **Step 4: Run source-lock tests**

Run:
`python3 -m unittest Content.tournament.tests.test_fetch_locked_source -v`

Expected: tests pass; mismatch test confirms no partial destination.

- [ ] **Step 5: Commit**

```bash
git add Content/tournament/source-lock.json \
  Content/tournament/LICENSE-poker-cfr.txt \
  Content/tournament/fetch-locked-source.py \
  Content/tournament/tests/test_fetch_locked_source.py
git commit -m "build: lock HU push-fold solver inputs"
```

### Task 3: Export same-snapshot frequencies and conditional EVs | covers: tournament-strategy-source-adapter/组合策略精确聚合为 169 手牌, tournament-strategy-source-adapter/行动 EV 与策略频率使用同一均衡快照, tournament-strategy-source-adapter/覆盖 1–20BB 且记录收敛质量

**Files:**
- Create: `Content/tournament/patches/poker-cfr-hu-export.patch`
- Create: `Content/tournament/generate-hu-pushfold.py`
- Create: `Content/tournament/tests/test_solver_export.py`

**Interfaces:**
- Produces: one normalized JSON document per depth containing `source`,
  `configuration`, `snapshotSHA256`, `iterations`, `nashConvBB`,
  `exploitabilityBB`, and 169-row tables with `actionWeightsBasisPoints`
  and `actionEVsMilliBB`; 1BB omits Call-Jam.

- [ ] **Step 1: Write a 1BB solver smoke test**

```python
def test_one_bb_export_has_same_snapshot_frequency_and_ev(tmp_path):
    result = run_solver(depth=1, checkpoints=[2_000], output=tmp_path)
    assert result["effectiveBigBlinds"] == 1
    assert len(result["tables"]["openJam"]) == 169
    assert all(row["actionEVsMilliBB"]["fold"] == -500
               for row in result["tables"]["openJam"])
    assert "callJam" not in result["tables"]
    assert result["snapshotSHA256"] == recompute_snapshot_hash(result)
```

- [ ] **Step 2: Run the smoke test and observe missing patch/runner**

Run:
`python3 -m unittest Content.tournament.tests.test_solver_export -v`

Expected: failure because the patch and generator do not exist.

- [ ] **Step 3: Add the upstream patch**

The patch adds a `hu_export` binary and read-only evaluator. It must implement:

```rust
fn class_action_ev(numerators: &[f64], denominators: &[f64]) -> Result<i64, ExportError> {
    let denominator: f64 = denominators.iter().sum();
    if denominator == 0.0 {
        return Err(ExportError::ZeroReach);
    }
    Ok(round_half_away_from_zero(
        numerators.iter().sum::<f64>() / denominator * 1000.0,
    ))
}
```

SB uses `D=q*1225`, fold numerator `-0.5D`, and jam branches through frozen BB
strategy. BB uses `D=q*Σ compatible σ_SB(jam)`, fold numerator `-D`, and call
branches through showdown equity. Aggregate EV by ratio-of-sums, never by
averaging rounded EVs. Serialize sorted hand classes and stable decimal strings
used as snapshot hash input.

- [ ] **Step 4: Implement deterministic checkpoint runner**

`generate-hu-pushfold.py` verifies the source with Task 2, applies the patch,
builds `--release`, and runs depths/checkpoints with `RAYON_NUM_THREADS=1`.
Checkpoint sequence is `[10_000, 20_000, 40_000, 80_000, 160_000]`; first
snapshot with `nashConvBB <= 0.001` wins. A depth that misses the threshold is
an error. Test mode may supply `[2_000]` and a relaxed threshold but must stamp
`testOnly=true`, which Task 4 rejects from production batches.

- [ ] **Step 5: Add mathematical reconstruction assertions**

The Rust exporter must fail unless:

```text
abs(openJamFoldEV + 0.5) <= 0
abs(callJamFoldEV + 1.0) <= 0
abs(reconstructedProfileEV - trainOverallEV) <= 1e-10
abs(player0ProfileEV + player1ProfileEV) <= 1e-10
abs(reconstructedNashConv - solverNashConv) <= 1e-10
E(h,o) + E(o,h) == 1 for every compatible ordered pair
```

- [ ] **Step 6: Run the solver smoke test twice**

Run the same 1BB test in two fresh temporary directories. Expected: both pass
and normalized JSON bytes match exactly.

- [ ] **Step 7: Commit**

```bash
git add Content/tournament/patches \
  Content/tournament/generate-hu-pushfold.py \
  Content/tournament/tests/test_solver_export.py
git commit -m "feat: export HU solver frequencies and action EVs"
```

### Task 4: Validate normalized batches independently | covers: tournament-strategy-source-adapter/行动 EV 与策略频率使用同一均衡快照, tournament-strategy-content-import/导入完整且假设一致的 HU Push/Fold 批次, strategy-content-pipeline/锦标赛求解器输出导入

**Files:**
- Create: `Content/tournament/validate_hu_batch.py`
- Create: `Content/tournament/tests/test_validate_hu_batch.py`

**Interfaces:**
- Produces: `validate_batch(directory, source_lock) -> BatchAudit`;
  no writes on failure.

- [ ] **Step 1: Write malformed-batch tests**

Cover exactly:

```python
def test_missing_7bb_call_jam_is_rejected(): ...
def test_duplicate_aa_and_missing_72o_are_both_reported(): ...
def test_noncanonical_hand_is_rejected(): ...
def test_frequency_total_not_10000_is_rejected(): ...
def test_frequency_and_ev_keys_must_match(): ...
def test_zero_bb_reach_is_rejected(): ...
def test_snapshot_hash_mismatch_is_rejected(): ...
def test_nash_conv_above_threshold_is_rejected(): ...
def test_test_only_solver_output_is_rejected(): ...
```

Each fixture names the failing depth/table/hand/action in the expected typed
error string.

- [ ] **Step 2: Run tests and verify import failure**

Run:
`python3 -m unittest Content.tournament.tests.test_validate_hu_batch -v`

Expected: import failure for `validate_hu_batch`.

- [ ] **Step 3: Implement the independent validator**

Do not import solver code. Recompute canonical hand classes, combination
counts, bps totals, snapshot SHA-256, source hashes, assumptions, table count,
depth set, NashConv threshold, fold-EV invariants, and table/action vocabulary
from JSON only. Return a stable audit object sorted by depth.

- [ ] **Step 4: Run validator tests**

Run:
`python3 -m unittest Content.tournament.tests.test_validate_hu_batch -v`

Expected: all malformed cases fail closed and one complete synthetic batch
passes.

- [ ] **Step 5: Commit**

```bash
git add Content/tournament/validate_hu_batch.py \
  Content/tournament/tests/test_validate_hu_batch.py
git commit -m "feat: validate HU solver content batches"
```

### Task 5: Build 20 deterministic SolverExport files | covers: tournament-strategy-source-adapter/覆盖 1–20BB 且记录收敛质量, tournament-strategy-content-import/导入完整且假设一致的 HU Push/Fold 批次, tournament-strategy-content-import/未经人工审核不得晋升, strategy-content-pipeline/锦标赛求解器输出导入

**Files:**
- Create: `Content/build-tournament-exports.py`
- Create: `Content/tournament/tests/test_build_tournament_exports.py`

**Interfaces:**
- Consumes: validated normalized batch.
- Produces: 20 sorted SolverExport JSON files, one exact depth each.

- [ ] **Step 1: Write exporter tests**

```python
def test_each_depth_builds_two_correct_nodes(tmp_path):
    build_exports(valid_batch(), tmp_path, content_version="2026.08.13-hu-pf.1")
    export = load(tmp_path / "tourn-hu-chip-ev-noante-07bb.json")
    assert export["packID"].endswith("-07bb")
    assert export["effectiveStack"] == {"centiBB": 700}
    assert [n["facing"] for n in export["nodes"]] == ["unopened", "singleRaise"]
    assert export["nodes"][0]["decisionEffectiveStack"] == {"centiBB": 650}
    assert export["nodes"][1]["decisionEffectiveStack"] == {"centiBB": 600}
    assert export["nodes"][0]["rangeCells"][0]["actionEVs"] is not None

def test_partial_batch_writes_nothing(tmp_path):
    with self.assertRaisesRegex(BatchValidationError, "missing 7BB Call-Jam"):
        build_exports(batch_missing_7bb_call(), tmp_path, "2026.08.13-hu-pf.1")
    assert list(tmp_path.iterdir()) == []
```

- [ ] **Step 2: Run and verify missing exporter**

Run:
`python3 -m unittest Content.tournament.tests.test_build_tournament_exports -v`

Expected: import failure.

- [ ] **Step 3: Implement exact betting contexts**

For depth `S` in centi-BB:

```python
open_jam = {
    "pot": {"centiBB": 150},
    "decisionEffectiveStack": {"centiBB": S - 50},
    "amountToCall": {"centiBB": 50},
}
call_jam = {
    "pot": {"centiBB": S + 100},
    "decisionEffectiveStack": {"centiBB": S - 100},
    "amountToCall": {"centiBB": S - 100},
}
```

Never build a 1BB Call-Jam node: the BB has no remaining chips after posting
the blind, so no fold/call decision exists. Open-Jam maps external `allIn` to
range key `raise`. Use `AA` as stable example and copy its frequencies/EVs
into `SolverAction`.

- [ ] **Step 4: Make batch output atomic and deterministic**

Validate all inputs and build all JSON bytes in memory before creating the
staging directory. Encode with sorted keys, compact separators, fixed
`exportedAt="2026-08-13T00:00:00Z"`, and a trailing newline. Replace the final
directory only after all 20 files exist.

- [ ] **Step 5: Run exporter tests twice**

Expected: both runs pass and every file hash matches across fresh directories.

- [ ] **Step 6: Commit**

```bash
git add Content/build-tournament-exports.py \
  Content/tournament/tests/test_build_tournament_exports.py
git commit -m "feat: build exact-depth tournament solver exports"
```

### Task 6: Import only unverified solver-origin packs | covers: tournament-strategy-content-import/导入完整且假设一致的 HU Push/Fold 批次, tournament-strategy-content-import/未经人工审核不得晋升

**Files:**
- Create: `Content/import-tournament-packs.py`
- Create: `Content/tournament/tests/test_import_tournament_packs.py`
- Modify: `Packages/StrategyTooling/Sources/strategy-import/main.swift`

**Interfaces:**
- Consumes: 20 validated SolverExport files.
- Produces: 20 pack JSON files and 20 `.sha256` files in one staged replacement.

- [ ] **Step 1: Write status/provenance gate tests**

```python
def test_import_command_is_fixed_to_unverified_solver(tmp_path):
    commands = plan_imports(valid_exports(), tmp_path, "2026.08.13-hu-pf.1")
    assert all("--origin solver" in command for command in commands)
    assert all("--review-status unverifiedDraft" in command for command in commands)
    assert all("--reviewed-by" not in command for command in commands)

def test_reviewed_request_is_not_an_available_argument():
    with self.assertRaises(SystemExit):
        parse_args(["--review-status", "reviewed"])
```

- [ ] **Step 2: Run and verify missing importer**

Run:
`python3 -m unittest Content.tournament.tests.test_import_tournament_packs -v`

Expected: import failure.

- [ ] **Step 3: Implement staged imports**

The Python wrapper exposes only `--content-version`, `--exports`,
`--destination`, and `--strategy-import`. It invokes:

```text
strategy-import
--export <file>
--content-version <version>
--review-status unverifiedDraft
--origin solver
--output <staged pack path>
```

After all commands exit 0, verify every checksum and replace the destination
directory. On any failure delete only the unique staging directory.

- [ ] **Step 4: Add a defense-in-depth tournament guard**

In `strategy-import`, when `export.tournament != nil`, reject
`reviewStatus != .unverifiedDraft`. This does not change cash import behavior;
human promotion remains a future separate operation that consumes review
evidence rather than the raw import path.

- [ ] **Step 5: Run StrategyTooling and wrapper tests**

```bash
swift test --package-path Packages/StrategyTooling
python3 -m unittest Content.tournament.tests.test_import_tournament_packs -v
```

Expected: both exit 0.

- [ ] **Step 6: Commit**

```bash
git add Content/import-tournament-packs.py \
  Content/tournament/tests/test_import_tournament_packs.py \
  Packages/StrategyTooling/Sources/strategy-import/main.swift
git commit -m "feat: import unverified tournament solver packs"
```

### Task 7: Generate the 1–20BB batch and golden baseline | covers: tournament-strategy-source-adapter/覆盖 1–20BB 且记录收敛质量, strategy-content-pipeline/锦标赛求解器输出导入, strategy-content-pipeline/首批内容黄金回归基线

**Files:**
- Create: `Content/tournament-normalized/hu-chip-ev-noante-01bb.json` through `20bb.json`
- Create: `Content/exports/tourn-hu-chip-ev-noante-01bb.json` through `20bb.json`
- Create: `Content/packs/tourn-hu-chip-ev-noante-01bb.json` through `20bb.json`
- Create: corresponding `.sha256` files
- Create: `Content/tournament/golden-manifest.json`
- Create: `scripts/verify-tournament-content.sh`

**Interfaces:**
- Produces: repository-tracked unverified solver content and reproducibility
  gate.

- [ ] **Step 1: Run the complete deterministic solver batch**

Run:

```bash
python3 Content/tournament/generate-hu-pushfold.py \
  --source-lock Content/tournament/source-lock.json \
  --depths 1-20 \
  --nash-conv-threshold 0.001 \
  --output Content/tournament-normalized
```

Expected: 20 normalized files; every depth reaches the threshold by 160,000
iterations. If any depth does not converge, stop and record actual NashConv in
`progress.md`; do not relax the threshold without a design revision.

- [ ] **Step 2: Validate the complete batch**

Run:
`python3 Content/tournament/validate_hu_batch.py Content/tournament-normalized`

Expected: `20 depths, 39 tables, 6591 rows: PASS`.

- [ ] **Step 3: Build exports and packs**

```bash
python3 Content/build-tournament-exports.py \
  --input Content/tournament-normalized \
  --output Content/exports \
  --content-version 2026.08.13-hu-pf.1
swift build --package-path Packages/StrategyTooling -c release
python3 Content/import-tournament-packs.py \
  --exports Content/exports \
  --destination Content/packs \
  --content-version 2026.08.13-hu-pf.1 \
  --strategy-import Packages/StrategyTooling/.build/release/strategy-import
```

Expected: 20 packs + 20 checksums, each
`origin=solver/reviewStatus=unverifiedDraft`.

- [ ] **Step 4: Build the golden manifest**

Write sorted arrays containing normalized input SHA-256, export SHA-256, pack
SHA-256, depth, iterations, NashConv, exploitability, two table row counts,
and the locked source hashes. Encode deterministically.

- [ ] **Step 5: Add and run the reproducibility script**

`verify-tournament-content.sh` regenerates into `mktemp -d`, validates, builds
exports/packs, and byte-compares all results to tracked files. It also runs:

```bash
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/StrategyTooling
bash scripts/check-layering.sh
```

Run it once. Expected: all checks pass with actual test counts printed.

- [ ] **Step 6: Commit generated truth and baseline**

```bash
git add Content/tournament-normalized Content/exports Content/packs \
  Content/tournament/golden-manifest.json scripts/verify-tournament-content.sh
git commit -m "data: add unverified HU push-fold solver content"
```

### Task 8: Add review and licensed local-export handoff | covers: tournament-strategy-content-import/商业平台手工导出走隔离入口

**Files:**
- Create: `Content/tournament/review-template.md`
- Create: `Content/tournament/commercial-export/README.md`
- Create: `Content/tournament/commercial-export/convert_local_export.py`
- Create: `Content/tournament/tests/test_convert_local_export.py`

**Interfaces:**
- Produces: offline-only conversion entry; review evidence template.

- [ ] **Step 1: Write local-only boundary tests**

```python
def test_http_input_is_rejected():
    with self.assertRaisesRegex(LocalExportError, "local file"):
        convert("https://gtowizard.com/solution", metadata())

def test_missing_license_evidence_is_rejected(tmp_path):
    source = tmp_path / "range.txt"
    source.write_text("AA:1", encoding="utf-8")
    with self.assertRaisesRegex(LocalExportError, "license evidence"):
        convert(source, metadata(license_evidence=""))

def test_frequency_only_export_cannot_become_scorable_content(tmp_path):
    with self.assertRaisesRegex(LocalExportError, "per-action EV"):
        convert(frequency_only_file(tmp_path), complete_metadata())
```

- [ ] **Step 2: Run and verify missing converter**

Run:
`python3 -m unittest Content.tournament.tests.test_convert_local_export -v`

Expected: import failure.

- [ ] **Step 3: Implement offline-only conversion**

Accept only `pathlib.Path` regular files. Reject strings with URI schemes,
symlinks, directories, missing provenance, missing license evidence, missing
assumptions, missing 169 frequencies, or missing same-source per-action EV.
Record source file SHA-256. Do not import `urllib`, `requests`, browser
libraries, or shell commands.

- [ ] **Step 4: Write the human review template**

Require reviewer name/time, solver commit/config, source and snapshot hashes,
20-depth coverage, convergence table, sampled boundary hands, independent
reference and license, frequency differences, EV invariants, and an explicit
decision. State that completing the document does not mutate pack status; a
future promotion change must issue a new content version.

- [ ] **Step 5: Run tests and commit**

```bash
python3 -m unittest Content.tournament.tests.test_convert_local_export -v
git add Content/tournament/review-template.md \
  Content/tournament/commercial-export \
  Content/tournament/tests/test_convert_local_export.py
git commit -m "docs: add tournament strategy review handoff"
```

### Task 9: Final verification and change review | covers: all acceptance criteria

**Files:**
- Modify: `openspec/changes/strategy-content-import-hu-pushfold-20260813-01/tasks.md`
- Modify: `openspec/changes/strategy-content-import-hu-pushfold-20260813-01/progress.md`
- Create: `openspec/changes/strategy-content-import-hu-pushfold-20260813-01/review.md`

- [ ] **Step 1: Run targeted unit suites**

```bash
python3 -m unittest discover -s Content/tournament/tests -v
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/StrategyTooling
bash scripts/verify-m1a.sh
```

Expected: exit 0 with non-zero test counts for every requested suite; existing
loader, checksum, review-status, golden-regression, bundled-content, update,
history, frequency, and legal-action scenarios remain covered by the unchanged
M1A regression suite.

- [ ] **Step 2: Run full content reproducibility**

Run: `bash scripts/verify-tournament-content.sh`

Expected: regenerated normalized files, exports, packs, checksums, and golden
manifest are byte-identical.

- [ ] **Step 3: Run repository gates**

```bash
bash scripts/check-proposal-completeness.sh \
  strategy-content-import-hu-pushfold-20260813-01
bash scripts/check-layering.sh
git diff --check HEAD~8..HEAD
```

Expected: all exit 0.

- [ ] **Step 4: Verify protected unrelated files are untouched**

```bash
git diff --name-only 15315a4..HEAD -- \
  PokerCoach/Features/TournamentICM \
  PokerCoachTests/TournamentICMViewModelTests.swift \
  PokerCoachUITests/TournamentICMSurfaceTests.swift
```

Expected: no output.

- [ ] **Step 5: Write the Harness review report**

Map every proposal Scenario to its passing test/evidence and record:

```text
content status: origin=solver, reviewStatus=unverifiedDraft
coverage: 20 depths / 39 tables / 6591 hand rows
source commit and three locked hashes
maximum NashConv and depth
20 pack SHA-256 values via golden-manifest.json
human strategy review: pending
```

- [ ] **Step 6: Mark tasks complete and commit**

Update all completed checkboxes and `progress.md`, then:

```bash
git add openspec/changes/strategy-content-import-hu-pushfold-20260813-01
git commit -m "docs: verify HU push-fold content pipeline"
```

## Self-Review Checklist

- [x] **Capability 追溯表完整**：proposal 中每个
  Capability/Requirement/Scenario 都有对应 Task。
- [x] **Spec coverage:** source locking, same-snapshot EVs, blocker/reach
  conditioning, 169 aggregation, 1–20BB completeness, exact-depth packs,
  unverified-only import, deterministic output, atomic failure, legacy cash
  compatibility, golden regression, local commercial exports, and review
  evidence all map to tasks.
- [x] **Placeholder scan:** no TBD/TODO/“类似”/“适当” implementation
  placeholders.
- [x] **Type consistency:** optional tournament metadata and action EV names
  match across StrategyContent, SolverExport, PackBuilder, normalized JSON,
  and tests.

## 下一步

执行
`/harness-apply strategy-content-import-hu-pushfold-20260813-01`
