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

## handlab-m2b-import-preview-20260812-01

- 归档：2026-08-12 17:49
- 位置：`openspec/changes/archive/handlab-m2b-import-preview-20260812-01-20260812-174946`
- 新增能力：hand-history-import, import-conflict-review, personal-hand-library
- 修改能力：无
- 交付（M2B 第一切片，个人牌局实验室的导入前半段）：把受支持的 PokerStars NLHE 现金文本牌谱确定性解析为统一 `ObservedHand`（整数 centi-BB、位置由入座玩家绕按钮导出、盲注/自主行动分列、抽水捕获）；不受支持格式与无法无歧义解析的字段登记为可定位冲突、绝不猜测（非整除报冲突而非四舍五入）；采纳前标准化预览、含未解决冲突不可采纳、修正后可采纳；采纳的牌谱作为版本化个人资源本地保存、重复采纳保留旧版本、导入路径持有事件存储却不产生 `TrainingEvent`。新增 `HandHistory`/`HandHistoryPersistence` 两个包，Hand Lab 入口嵌在「复盘」下（四个核心标签不变）；`Street` 抽出为 PokerCore 独立文件
- 新增规格：3 个 Capabilities、4 个 Requirements、18 个 Scenarios
- 未交付（后续 M2B 切片）：关键节点选择、策略分析与漏洞标签、分支重放与反事实对比、补救训练生成、个人牌谱跨设备同步、PokerStars 以外格式
- 已知限制（保守、不产错误数据）：摊牌对手明牌暂不读取、仅美元现金、ante/straddle 登记为冲突暂不建模

## handlab-m2b-hand-analysis-20260812-01

- 归档：2026-08-12 20:26
- 位置：`openspec/changes/archive/handlab-m2b-hand-analysis-20260812-01-20260812-202626`
- 新增能力：imported-hand-signatures, imported-hand-analysis
- 修改能力：无
- 交付（M2B 第二切片，节点粒度分析）：`ObservedHand.heroDecisionSignatures()` 重建下注状态、逐英雄决策点导出 `SpotSignature`（facing 由前同街加注次数、effectiveStack 由英雄剩余筹码、isAllIn 由投入达起始筹码，全纯扑克事实，只依赖 PokerCore）；App 层按 `SpotCoverageKey` 逐节点判覆盖并给"英雄行动 vs 范围表权重 + 偏离幅度(10000−权重)"的对照，翻后节点结构性一律 uncovered（无翻后手牌分类法，仿 SessionContentMatcher）；据 deviation(覆盖且权重<5000)/allIn 选关键节点、deviation 优先按幅度降序、上界 5、可为空；分析经持有事件存储却不写入的协调器，不产生 `TrainingEvent`。复盘→Hand Lab→某手→分析可达（四标签不变）；`hand-model-writer --signatures` + 签名黄金 + 跨进程门禁
- 新增规格：2 个 Capabilities、3 个 Requirements、11 个 Scenarios
- 复用（不改动）：`SpotSignature`/`SpotCoverageKey`、`RangeBaseline` 权重通路、偏离阈值 5000（本地重述，未 import `SessionSimulation.KeyHandSelection`）
- 未交付（后续 M2B 切片）：分支重放与反事实对比、补救训练生成、漏洞标签落库；`bigSwing`/`bigPot` 理由（需派彩数据，`ObservedHand` 未携带）

## handlab-m2b-remediation-20260812-01

- 归档：2026-08-12 23:41
- 位置：`openspec/changes/archive/handlab-m2b-remediation-20260812-01-20260812-234134`
- 新增能力：imported-hand-remediation
- 修改能力：无（`KeyNode` 追加 `coveringScenarioID` 为加法，不改 `imported-hand-analysis` 任何 scenario）
- 交付（M2B 第三切片，闭环）：偏离关键节点保留其覆盖场景 ID；分析视图对偏离节点提供"练这个漏洞"，用该 ID 经既有 `DecisionSessionViewModel` 训练流程呈现——补救事件与直接训练同场景同提交的事件除 id/时间/设备外逐字段相等（含完整 grade），走既有归约与冻结契约（满足 M2 gate）。打开分析不写事件，只有完成补救训练才产生。复盘→Hand Lab→某手→分析→练这个漏洞可达
- 新增规格：1 个 Capability、2 个 Requirements、5 个 Scenarios
- 复用（不改）：`DecisionSessionViewModel`/`TrainingEvent`/冻结契约/`PlayerModelReducer`；`SpotCoverageKey`/`RangeBaseline`
- 未交付（后续 M2B 切片）：分支重放与反事实对比、漏洞标签落库、手动场景构建器
- 已知缺口：分析/补救的取包口径与内容采纳的陈旧问题同源（见 `docs/architecture/known-gaps.md`，接入真实更新源前对齐）

## handlab-m2b-scenario-builder-20260813-01

- 归档：2026-08-13 11:07
- 位置：`openspec/changes/archive/handlab-m2b-scenario-builder-20260813-01-20260813-110719`
- 新增能力：manual-scenario-builder
- 修改能力：无（`ImportedHandContentMatcher` 抽出 `classify(signature:action:)` 核心为加法，既有入口转调）
- 交付（M2B 第四切片，手动场景构建器）：用户手搭翻前 spot（位置/两张牌/facing/筹码/行动）→ `ConstructedSpot`（HandHistory，只依赖 PokerCore；自校验：无法解析/牌数错/重复牌/非正筹码各以可判等原因拒，座位借 `TablePosition`；底牌规范排序使身份与顺序无关；Codable+规范编码+SHA-256 身份）→ `SpotSignature` → 复用匹配判覆盖：命中给范围表权重对照并可在覆盖场景上补救、未命中记 `NodeCoverage.uncovered` 绝不编造、无覆盖不评分；构造 spot 版本化存 `FileConstructedSpotStore`，构造/保存不产生 `TrainingEvent`，只有完成补救才产生。复盘→Hand Lab→构造场景可达（四核心标签不变）
- 新增规格：1 个 Capability、3 个 Requirements、6 个 Scenarios
- 复用（不改语义）：`SpotSignature`/matcher 判定/第三切片补救/`DecisionSessionViewModel`/契约
- 未交付（M2B 尾）：分支重放/反事实对比、漏洞标签聚合
- 已知缺口：分析/补救/构造的取包口径与内容采纳陈旧同源（见 `docs/architecture/known-gaps.md`）
