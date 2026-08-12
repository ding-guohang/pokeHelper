# OpenSpec 归档索引

| 归档时间 | Change ID | 摘要 | 规格变更 | 归档位置 |
|---|---|---|---|---|
| 2026-08-07T09:52:31+08:00 | `poker-coach-m1a-cash-coach-20260806-01` | M1A 现金局教练纵向切片 | 新增 6 个 Capabilities、19 个 Requirements、34 个 Scenarios | `poker-coach-m1a-cash-coach-20260806-01-20260807-095231/` |
| 2026-08-10T15:07:31+08:00 | `sync-m1b-identity-sync-20260807-01` | M1B 独立身份与同步 | 新增 6 个 Capabilities、修改 local-learning-profile；共 31 个 Requirements、56 个 Scenarios | `sync-m1b-identity-sync-20260807-01-20260810-150647/` |

## curriculum-m1c-adaptive-cash-20260810-01

- 归档：2026-08-10 23:04
- 位置：`openspec/changes/archive/curriculum-m1c-adaptive-cash-20260810-01-20260810-230421`
- 新增能力：strategy-content-pipeline, initial-diagnostic, adaptive-curriculum, spaced-repetition
- 修改能力：versioned-strategy-content, local-learning-profile, m1a-release-safety
- 交付：随包已审核翻前内容、能力树与掌握判定、12 题可跳过诊断、复练阶梯、按五项输入排序的今日计划、内容导入与黄金回归工具链、三种构建频道与内容审核状态门禁
- 未交付：翻后内容（审计发现其带有核心集被驳回的同类缺陷，已移除）、服务端内容分发端点（无内容可发，推迟）

## session-m2a-cash-simulation-20260810-01

- 归档：2026-08-12 09:22
- 位置：`openspec/changes/archive/session-m2a-cash-simulation-20260810-01-20260812-092232`
- 新增能力：session-dealing, virtual-opponents, cash-session-run, key-hand-review, session-frequency-report
- 修改能力：cash-decision-domain（须跟注额由上游封顶到有效筹码、筹码用尽的跟注即全下）、local-learning-profile（Session 手牌不产生 TrainingEvent，只有复盘「重打」才走带信心训练管线）
- 交付：由种子确定的 6-max 发牌与永远合法的下注状态机、四种可披露且确定性的对手档案（带行为表版本号）、15/30/60 手可中断续打的 Session、关键手复盘（偏离内容优先）与逐街回放/对照/重打、跨 Session 按（位置,面对情形）累计的翻前频率报告；`SpotSignature`/`HandClass` 落 PokerCore，新增 SessionSimulation/SessionPersistence/TrainingPersistence 三个包，`FileTrainingEventStore` 迁出领域包
- 新增规格：5 个 Capabilities、12 个 Requirements、44 个 Scenarios（另修改 2 个既有 Capabilities）
- 未交付：Session 记录跨设备同步（事件契约已冻结，推迟）；翻后局面等同（无翻后手牌分类法，推迟 M2B）
- 遗留缺口：盲注不顺延（见 `docs/architecture/known-gaps.md`，发布前必修，本次归档后随即修复）
