# 评审报告：strategy-content-import-hu-pushfold-20260813-01

## 内容状态

- `origin=solver`,`reviewStatus=unverifiedDraft`(自动导入无法产出 `reviewed`;
  strategy-import 对锦标赛内容有防御性守卫)。
- 覆盖:**20 个深度 / 39 张表 / 6591 手行**(Open-Jam 1–20BB,Call-Jam 2–20BB)。
- 来源:`b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`(BSD-2-Clause),
  锁定 4 份源输入 + Cargo.toml/lock + LICENSE 的 SHA-256(`source-lock.json`)。
- 收敛:每深度在首个 10,000 迭代 checkpoint 即达 NashConv ≤ 0.001;实测**最大 NashConv
  ≈ 2.135e-7 BB/hand**(20BB…实际见 `golden-manifest.json`)。
- 20 个 pack 的 SHA-256 记录在 `Content/tournament/golden-manifest.json`。
- **人工策略审核:待办**(`review-template.md` 是晋升所需证据;晋升是独立操作 + 新版本)。

## Capability / Scenario → 证据

| Capability | Scenario | 证据 |
|---|---|---|
| tournament-strategy-source-adapter | 锁定来源生成 / 变化 | `fetch-locked-source.py` + `test_fetch_locked_source.py`(7)；`source-lock.json`（含 game_node.rs） |
| tournament-strategy-source-adapter | 169 聚合 / 同源 EV / 零 reach | `main_hu_export.rs`（evaluate 同快照、ΣN/ΣD）+ `test_solver_export.py`；depth-10 NashConv 3.855e-8 对齐上游 |
| tournament-strategy-source-adapter | 1–20BB 覆盖 / 收敛阈值 | 真实批次 20 深度全达阈值；`validate_hu_batch.py`（NashConv 门禁）+ 13 测试 |
| tournament-strategy-content-import | 合法/缺表/非法手批次 | `build-tournament-exports.py` + `test_build_tournament_exports.py`（缺表写空） |
| tournament-strategy-content-import | 未经审核不得晋升 | `import-tournament-packs.py`（固定 unverifiedDraft/solver,无 reviewed 参数）+ strategy-import 守卫 + `test_import_tournament_packs.py` |
| tournament-strategy-content-import | 商业平台手工导出隔离 | `commercial-export/convert_local_export.py`（拒 URL/symlink、必需授权与 EV）+ `test_convert_local_export.py` |
| strategy-content-pipeline | 求解器导入 / 确定性 / 原子 / 黄金 | 确定性(单线程+固定迭代,cross-run 逐位一致)；`golden-manifest.json`；`verify-tournament-content.sh` |
| versioned-strategy-content | 锦标赛假设 / 旧包兼容 / 审核状态约束 | `TournamentStrategyAssumptions` + `StrategyPackValidator` 锦标赛校验 + `TournamentStrategyContentTests`;旧 schema-1 现金包仍解码 |

## 门禁

- `swift test`:StrategyContent(54)、StrategyTooling(25)全绿。
- Python:`test_fetch_locked_source`(7)、`test_solver_export`(3)、`test_validate_hu_batch`(13)、
  `test_build_tournament_exports`(3)、`test_import_tournament_packs`(2)、`test_convert_local_export`(5)。
- `scripts/verify-tournament-content.sh`:重生成逐位一致 + 内容/工具套件 + 层禁。
- 受保护文件未改:`PokerCoach/Features/TournamentICM/` 及其测试(`git diff` 为空)。

## 结论

- [x] 通过 — 可归档。首批 HU push/fold ChipEV 内容以 `unverifiedDraft` 交付,数学收敛
  自证、来源锁定可复现;进入训练前需具名人工审核晋升为 `reviewed`。
