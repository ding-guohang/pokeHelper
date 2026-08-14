# 锦标赛 Push/Fold 审核阻断问题 · 修订记录（2026-08-14）

本文件回应 `review-template.md` 第 6 节列出的阻断问题。签署的审核记录本身保持原样，
作为“发现了什么”的历史存证；本文件记录“改了什么、由哪个门禁复验”。

**内容状态未变：仍为 `unverifiedDraft`。** 本次修订修复的是流水线完整性缺陷，
不构成对策略的人工签署。要晋升为 `reviewed`，仍需具名人类填写 review record，
再走 `promote-tournament-packs.py`（该脚本现会实际重算证据并 fail-closed）。

## Critical

1. **来源缓存复验** — `generate-hu-pushfold.py::ensure_source` 现在**每次调用都重新
   核对全部锁定哈希**，删除了 `.verified` 快路径通行证；`build_solver` 把 pristine
   checkout 复制到 `<crate>-build` 后才追加导出二进制与 `[[bin]]` 段，绝不改动被锁定的
   checkout。复验：`verify-tournament-content.sh` 重跑逐位一致。
2. **工具链 / 导出补丁绑定** — 新增 `verify_toolchain(lock)`：运行 `rustc --version`
   并要求与 `source-lock.json.rustVersion` 精确一致；lock 中的 `rustVersion` 已改为
   真实使用的 `1.97.1`（此前虚标 `1.56.0`）。导出补丁只作用于构建副本，锁定的
   `Cargo.toml` 不再被就地改写。
3. **validator 证据链** — `validate_hu_batch.py` 现在校验 commit==lock、
   licenseSpdx==lock、盲注 SB=50/BB=100、`hasAnte=false`、`anteDescription` 非空、
   `equilibrium==chipEV`、`exploitabilityBB == nashConvBB/2`（并拒绝 NaN/非有限），
   而不再只验证可由被审文档自身重算的哈希。测试见 `tests/test_validate_hu_batch.py`。
4. **strategy-import 守卫** — 重新加入严格守卫：`export.tournament != nil` 且
   `--review-status reviewed` 直接报错退出。`reviewed` 锦标赛内容只能由晋升路径产出，
   raw importer 无法再直达。

## Important

1. **generatedSource 绑定** — 现在写入 `poker-cfr@<commit> … iters=<n> · NashConv=<e>
   · snapshot=<hash16> (unverified solver output)`，绑定迭代数、NashConv 与 normalized
   快照哈希（`build-tournament-exports.py`）。
2. **importer 全批次** — `import-tournament-packs.py::import_packs` 现在要求 export 集合
   恰好为 1–20BB，缺档或多档即报错（`test_import_tournament_packs.py`）。
3. **晋升重导比较** — 晋升脚本以 baseline 为准仅改 manifest，并断言非 manifest 策略内容
   逐位不变（此前已修，保留）。
4. **晋升 evidence 实测** — `promote-tournament-packs.py::default_evidence_runner` 实际
   运行 `verify-equities` 与 `cross-check-exploitability` 并读回实测最坏值，`_finite`
   拒绝 NaN，超阈值 fail-closed；不再信任 review JSON 自报数字。
5. **晋升前置约束** — 晋升现强制：baseline 各档 pack SHA-256 等于签入 golden manifest、
   批次恰好 1–20BB、新 `contentVersion` 与 baseline 不同；promotion-record 记录 baseline
   与 reviewed pack 哈希及三份 evidence artifact 的 SHA-256（`test_promote_tournament_packs.py`）。
6. **证据接入主门禁** — `verify-tournament-content.sh` 现在对锁定 equity 表重跑
   `verify-equities` 与 `cross-check-exploitability`，并**逐位比对**重生成的
   `equity-verify-report.md` / `cross-check-report.md` 与签入版本；静态报告漂移即使门禁失败。

## 复验证据（2026-08-14）

- `bash scripts/verify-tournament-content.sh` → exit 0（逐位可复现 + 独立证据 + 报告不漂移 + 套件 + 分层）。
- `bash scripts/verify-m1c.sh` → exit 0（三频道构建、内容门禁正反双向、冻结契约）。
- 独立 equity 重算最大偏差 `0.00e+00`（阈值 1e-6）；最坏深度可利用度 `0.00000 BB/手`（阈值 0.02）。
- 策略数值未变：`cross-check-report.md` 与 `equity-verify-report.md` 相对上次提交逐位一致。
