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

## handlab-m2b-branching-replay-20260813-01

- 归档：2026-08-13 12:39
- 位置：`openspec/changes/archive/handlab-m2b-branching-replay-20260813-01-20260813-123955`
- 新增能力：hand-lab-replay
- 修改能力：无
- 交付（M2B 第五切片，逐街回放与内容反事实）：把已存储个人牌谱逐街回放（每街可见公共牌+该街自主行动，逐字来自 `ObservedHand.streets`，含所有玩家），每个英雄决策点给"你的行动 vs 内容在该局面的权重"反事实（命中查范围表、未命中记 `NodeCoverage.uncovered` 不编造）；命中节点可复用第三切片补救。**不显示派生底池**（ObservedHand 无底池字段，避免为导入牌重实现结算/边池而显示错误底池）、**不重模拟对手**（真实对手后续未知，臆造即编造）、回放不产生 `TrainingEvent`（仅完成补救才产生）。复盘→Hand Lab→某手→回放可达（四核心标签不变）
- 新增规格：1 个 Capability、2 个 Requirements、5 个 Scenarios
- 复用（不改语义）：`ObservedHand.streets`/`heroDecisionSignatures`/matcher/第三切片补救/`DecisionSessionViewModel`
- 未做（有意）：派生底池展示、对手重模拟/真正 what-if 续打（后者只在 M2A Session 的虚拟对手下成立）

## tournament-m3-structure-20260813-01

- 归档：2026-08-13 14:06
- 位置：`openspec/changes/archive/tournament-m3-structure-20260813-01-20260813-140652`
- 新增能力：tournament-structure
- 修改能力：无
- 交付（M3 第一切片，锦标赛结构地基）：新包 `TournamentEngine`（只依赖 PokerCore）——升盲/ante 级别表 `BlindSchedule`（校验：非空、级别从 1 连续、大盲严格递增、SB≤BB、BB>0、ante≥0、SB≥0，共 8 类各以可判等原因拒），按固定手数取当前级别并在末级 clamp；整数锦标赛筹码（非 `BBAmount`，因 BB 逐级升）；`effectiveBigBlinds(chips:atLevel:)` 向下取整据算有效深度。全整数、内容无关（无范围/ICM/push-fold）。接入 `check-package-layering.sh`（TournamentEngine 只见 PokerCore + 反向失败）并更新 `layering.md` 层图
- 新增规格：1 个 Capability、2 个 Requirements、4 个 Scenarios
- 未做（有意，硬边界）：push/fold 与 ICM 的策略内容/范围（策略真值，不编造，待你提供审核）；可玩赛事推进（对手打法=内容）；ICM 计算器（下一切片，含精确表示设计）
- 评审加固：BlindScheduleError 补 Sendable；补 negativeSmallBlind 校验（术语要求非负）

## tournament-m3-icm-20260813-01

- 归档：2026-08-13 14:33
- 位置：`openspec/changes/archive/tournament-m3-icm-20260813-01-20260813-143340`
- 新增能力：tournament-icm
- 修改能力：无
- 交付（M3 第二切片，ICM 权益计算器，纯数学、内容无关）：`TournamentEngine` 新增精确有理数 `Fraction`（`Int/Int`，构造即约分、分母恒正、`0`→`0/1`，`Sendable/Hashable/Comparable`；具名 throwing 算术 `adding`/`multiplied(by:)`/`multiplied(byInteger:)`，先约分再相乘、每步 `*ReportingOverflow`，溢出即抛 `ICMError.overflow`，绝不回退浮点或截断）；`ICMCalculator.equities(chipStacks:payouts:)` 按 Malmuth-Harville **只枚举入钱名次**（O(n^K)，把中间分母压到至多 K 个剩余总和连乘，避免 O(n!) 全枚举溢出），未入钱名次派彩为 0，**先按筹码 gcd 归一**（ICM 只依赖比例）使现实决赛桌落进 `Int`；六级校验（noPlayers/emptyPayouts/nonPositiveStack/negativePayout/morePayoutsThanPlayers/tooManySeats）+ overflow 共 7 个可判等 `ICMError`。全整数/有理、无策略真值（不含范围/频率/求解器）
- 新增规格：1 个 Capability、3 个 Requirements、13 个 Scenarios
- 逐家精确值独立手算校验：三家 `[5000,3000,2000]`+`[500,300,200]` → `5375/14`、`655/2`、`2020/7`，和 `1000/1`；三家等筹码 → 各 `10000/3`、和 `10000/1`（浮点判别关卡）
- 评审加固（含正反双向）：溢出用 `Int.max` payout 固定输入 + 阈值下成功配对；补 `tooManySeats`（>64 座位位掩码丢位→拒绝而非悄悄算错）+ 64 座位成功配对；chip 总和改 `addingReportingOverflow` 与 `Fraction` 同守「宁报错不静默」契约；补 `adding` 溢出/零分子/负数/×0 直测
- 诚实边界（有意，非缺陷）：互质大筹码满座赛场其精确权益分母本就超 `Int64`，此时抛 `overflow` 是正确行为（换 Int128/大数也只是抬高天花板、病态输入总会溢出）；现实决赛桌筹码共用单位、归一后很小，落在精确范围内
- 未做（有意，硬边界）：push/fold 与 ICM 压力下的开牌/跟注范围（策略真值，待审核）；泡沫/决赛桌决策建议；ICM 近似加速；`Fraction`→百分比/货币的展示层（接入锦标赛特性时）

## tournament-m3-pushfold-20260813-01

- 归档：2026-08-13 14:42
- 位置：`openspec/changes/archive/tournament-m3-pushfold-20260813-01-20260813-144254`
- 新增能力：tournament-pushfold
- 修改能力：无
- 交付（M3 第三切片，短筹码 push/fold 决策上下文，引擎、内容无关）：`TournamentEngine` 新增筹码计（`Int`）锦标赛原生的 `PushFoldContext`（throwing init 校验 `effectiveChips>0`、`bigBlindChips>0`）——`isAtOrBelow(thresholdBigBlinds:)` 用整数比较 `effectiveChips ≤ threshold×bigBlindChips` **精确**判定短筹码局面（含等号边界、无 floor 损失，阈值×BB 溢出抛 `thresholdOverflow`），`effectiveBigBlinds`（复用 slice-1，floored）仅供展示；`options()` 返回 jam-or-fold 简化模型的两个候选 `[.fold, .jam(toChips: effectiveChips)]`（**与深度无关、披露式**，不冒充合法穷尽/最优/推荐）。`PushFoldOption`/`PushFoldError`（4 个可判等 case）
- 新增规格：1 个 Capability、3 个 Requirements、5 个 Scenarios
- 三条硬边界（不编造策略真值）：不主张合法性穷尽（跛入/最小加注仍合法，现金侧 `BettingDecisionContext.legalActions()` 保有更宽合法集）；不内置/背书任何阈值（调用方传入）；不含 push/fold 范围与评分（该 jam 哪些手=策略真值，待审核）
- 有意偏离任务初拟：**不复用**现金 `BettingDecisionContext`/`DecisionAction`（centi-BB，锦标赛筹码不整除 BB，强塞会 floor 丢精度，违反精确数据铁律）→ 改用筹码计原生类型
- 评审加固：`options()` 的「无 range API」从可测 THEN 移出（不可证伪）→ 改断言与深度无关；补深度无关正向断言；阈值溢出用 `multipliedReportingOverflow` 报错而非 trap；`.fold` 假定英雄面对下注（免费过牌不建模，已文档化）
- 未做（有意）：按（位置,面对情形,深度）范围查表（内容切片）；jam EV/ICM 压力评分；泡沫/决赛桌建议

## tournament-m3-bubble-20260813-01

- 归档：2026-08-13 14:54
- 位置：`openspec/changes/archive/tournament-m3-bubble-20260813-01-20260813-145406`
- 新增能力：tournament-bubble-factor
- 修改能力：tournament-icm（`Fraction` 追加精确 `negated`/`subtracting`/`reciprocal`/`divided(by:)`，加法式扩展，溢出仍抛 `overflow`；未改既有 ICM scenario）
- 交付（M3 第四切片，ICM 风险溢价/泡沫系数，纯数学、内容无关）：`ICMPressure.bubbleFactor(chipStacks:payouts:heroIndex:opponentIndex:)` 在 ICM 权益之上精确算英雄对单一对手一次全下的泡沫系数 `BF=(equityNow−equityLose)/(equityWin−equityNow)`（约分 `Fraction`）；全下有效额 `r=min(hero,opp)`，短/等码方输则出局领第 N 名派彩、剩余 N−1 人竞争 `payouts.prefix(N−1)`（重索引），双方存活则全场 ICM；无增益（平坦派彩→分母 0）抛 `noEquityGain` 绝不除零；座位校验 `sameSeat`/`seatOutOfRange`，沿用 ICM 六类输入校验
- 新增规格：1 个 Capability、3 个 Requirements、10 个 Scenarios
- 手算钉死并经对抗评审复核：等码 `[1000×3]`+`[500,300,200]` → `4/3`（>1）；赢家通吃 `[1000]` → `1`；大码 `[3000,1000,2000]` → `31/29`（>1）；单挑 → `1`（无阶梯）
- 内容边界：泡沫系数是描述性度量（同 ICM 权益一类的事实），不推荐跟/弃、不评分、不含范围；泡沫系数驱动的范围留作审核内容
- 评审加固：修正 proposal 输局筹码笔误 `[2000,1000,2000]`→`[2000,2000,2000]` 并把 scenario3 从「返回 Fraction」钉成精确 `31/29`；补单挑 →1 正向例；`reciprocal` 对零前置崩溃、除法路径先 `noEquityGain` 挡零
- 未做（有意）：泡沫系数驱动的跟注/开牌范围（策略真值，待审核）；多路同池联合淘汰泡沫系数（只做 hero vs 单一对手）；并列/同时淘汰；展示层

## tournament-m3-icm-calc-20260813-01

- 归档：2026-08-13 15:08
- 位置：`openspec/changes/archive/tournament-m3-icm-calc-20260813-01-20260813-150846`
- 新增能力：tournament-icm-calculator
- 修改能力：无（四核心标签不变，`AdaptiveNavigationTests` 仍断言 `[今日,学习,训练,复盘]`）
- 交付（M3 第五切片，把锦标赛引擎做成用户可见工具，内容无关）：复盘下新增「锦标赛 ICM 计算器」入口（`review.tournamentICM`，仿牌局实验室嵌在复盘、不加主标签）；输入各家筹码 + 派彩（+ 可选 hero/opp 座位）→ 调 `ICMCalculator.equities`/`ICMPressure.bubbleFactor` → 结果 `Fraction` 在展示层用**整数长除法**（`magnitude` 防溢出/`Int.min`、半入进位传播）转定点小数呈现，**不引入** `Double`/`NumberFormatter`；非法输入与每个 `ICMError` 映射为中文错误、绝不静默或编造、不产生 `TrainingEvent`。App 首次依赖并 `import TournamentEngine`（`project.yml` 加包与 target 依赖）
- 新增规格：1 个 Capability、3 个 Requirements、5 个 Scenarios
- 新增文件：`PokerCoach/Features/TournamentICM/{TournamentICMView,TournamentICMViewModel,TournamentICMPresentation}.swift`、`PokerCoachTests/TournamentICMPresentationTests.swift`、`PokerCoachUITests/TournamentICMSurfaceTests.swift`
- 验证：展示转换单测 `10000/3→3333.33`、`2/3→0.67`、`1/1→1.00`、`-4/3→-1.33`、`1999/1000→2.00`；UI 测试经复盘→计算器→ 见 `3333.33` 与泡沫系数 `1.33`、非法输入见 `icm.error`；`AdaptiveNavigationTests` 绿；层禁 OK（TournamentEngine 仍只 PokerCore）；Release 模拟器构建通过
- 内容边界：纯 ICM 数学计算器，无范围/无评分/无打法建议/无训练事件；文案中性
- 未做（有意）：push/fold 或 ICM 压力范围建议（策略真值，待审核）；多路泡沫系数；计算历史持久化/同步；货币符号/本地化格式

## tournament-m3-icm-bf-row-20260813-01

- 归档：2026-08-13 15:59
- 位置：`openspec/changes/archive/tournament-m3-icm-bf-row-20260813-01-20260813-155956`
- 新增能力：无
- 修改能力：tournament-icm-calculator（泡沫系数从「英雄 vs 单一对手，需填两个座位」改为「填英雄座位 → 显示英雄对**每位**其他座位的泡沫系数」；移除对手座位输入；单对手仍是其中一行，能力不减）
- 交付（M3 第六切片，内容无关）：ICM 计算器填英雄座位后，对每个 `j != hero` 调 `ICMPressure.bubbleFactor` 渲染一行「对 座位 j：X.XX」（`icm.bubbleFactor.j`）；某对手不可算（如平坦派彩 `noEquityGain`）就地显示可读原因、不崩不编造不影响其他行；英雄座位越界/非整数报顶层 `icm.error`，不填英雄只显示权益。这是职业读 ICM 压力的方式（对谁能/不能对拼）
- 修改规格：tournament-icm-calculator 的「泡沫系数」Requirement 整体替换为「显示英雄对每位对手的泡沫系数」（4 Scenarios）
- 验证：ViewModel 单测（等筹码两行均 1.33；`[3000,1000,2000]` 对座位1=1.07=31/29 且对座位2 独立不同；平坦每行显无增益原因且权益仍显；越界报错/空英雄无行）；UI 测试改断言 `icm.bubbleFactor.1` 含 1.33；`AdaptiveNavigationTests` 绿；层禁 OK；Release 构建通过
- 未做（有意）：非英雄视角的两两泡沫系数矩阵；泡沫系数驱动的打法建议（策略真值）；多路同池联合淘汰

## tournament-m3-icm-depth-20260813-01

- 归档：2026-08-13 16:06
- 位置：`openspec/changes/archive/tournament-m3-icm-depth-20260813-01-20260813-160618`
- 新增能力：无
- 修改能力：tournament-icm-calculator（新增「显示每家有效深度与 push/fold 区」Requirement，加法，不改既有权益/泡沫系数行为）
- 交付（M3 第七切片，内容无关，暴露此前无 UI 的 slice 1/3）：计算器新增两个可选输入——大盲（筹码/BB）与 push/fold 阈值（BB）。填大盲即用 slice-1 `effectiveBigBlinds` 显示每家向下取整 BB 深度（`icm.depth.k`）；再填阈值即用 slice-3 `PushFoldContext.isAtOrBelow`（整数精确比较 `chips ≤ 阈值×大盲`，无 floor 损失）标出短筹码「push/fold 区（全下/弃牌模型）」。披露式、不主张必须 push/fold、不含范围、不评分；大盲留空则行为完全不变
- 修改规格：tournament-icm-calculator 追加 1 Requirement、3 Scenarios
- 验证：ViewModel 单测（`12000,3000`@BB`1000`→12/3 BB；阈值 10 只标 3BB 那家；大盲 0/负、阈值 -1 报错、留空只权益）；UI 测试填 BB`250`→4 BB 且阈值 10 标 push/fold；`AdaptiveNavigationTests` 绿；层禁 OK；Release 构建通过
- 未做（有意）：完整升盲表输入/逐级推进；push/fold 范围或打法建议（策略真值）；ante 对深度/M 值换算

## training-progress-trend-20260813-01

- 归档：2026-08-13 16:18
- 位置：`openspec/changes/archive/training-progress-trend-20260813-01-20260813-161801`
- 新增能力：training-progress-trend
- 修改能力：无
- 交付（内容无关，聚合用户自己的训练历史）：TrainingDomain 新增 `DailyProgress` + `ProgressTrend.daily(events:calendar:)`——按 `calendar.startOfDay` 分组累加 `grade.score`/计数/`quality==.blunder`，升序返回，均值 `scoreTotal/sampleCount` 整除（日历由调用方注入，纯函数）；复盘下新增只读「训练进度」视图（`review.progressTrend`）显示每日行 + 总览或空态。纯聚合，无策略内容、不产生事件、不改 `TrainingEvent`/契约。四核心标签不变
- 新增规格：1 个 Capability、2 个 Requirements、4 个 Scenarios
- 验证：TrainingDomain Swift Testing（三事件两日 `140/2/1→70`、`100/1/0→100` 升序；空→空）；App 单测（注入桩存储 → 两日行 + 总览「共 3 手 · 2 天 · 总平均 80 分」；空→空态）；UI 测试复盘→训练进度可达、重置后空态；`AdaptiveNavigationTests` 绿；层禁 OK（TrainingDomain 仍只 PokerCore/StrategyContent）；Release 构建通过
- 未做（有意）：图表库；周/月桶；按维度拆分趋势；导出/同步

## strategy-content-import-hu-pushfold-20260813-01

- 归档：2026-08-13 22:11
- 位置：`openspec/changes/archive/strategy-content-import-hu-pushfold-20260813-01-20260813-221136`
- 新增能力：tournament-strategy-source-adapter、tournament-strategy-content-import
- 修改能力：strategy-content-pipeline（+锦标赛求解器输出导入、首批黄金基线）、versioned-strategy-content（+锦标赛求解假设可追溯）
- 交付（首批真实求解的锦标赛策略内容，`unverifiedDraft`）：从锁定开源 CFR+ 求解器 `b-inary/poker-cfr@a5347082`（BSD-2-Clause）生成单挑 SB=0.5/BB=1、无 ante、rake=0、chipEV 的 push/fold GTO 内容，覆盖 1–20BB（Open-Jam 全部、Call-Jam 2–20），**20 个不可变内容包 / 39 张 169 手表 / 6591 行**，含每手每行动的同源反事实 EV。链路：锁定来源(hash 门禁) → 只读导出补丁(combo 频率+条件 EV，evaluate 同快照、ΣN/ΣD 聚合、bps/milliBB 量化) → 独立 JSON 校验 → 20 个 `SolverExport` → `strategy-import` 产 `origin=solver`+`reviewStatus=unverifiedDraft` 包 + 黄金基线。全部深度首个 10k 迭代 checkpoint 即达 NashConv ≤ 0.001（最大 2.135e-7）；depth-10 与上游参照 3.856e-8 一致
- 新增规格：2 个新 Capability（7 Requirements）+ 2 个 Capability 各加 2 Requirements
- 硬边界（不编造策略真值）：数字全部来自锁定求解器、收敛度自证；自动导入永不产 `reviewed`（strategy-import 有防御守卫）；商业平台不抓取，仅用户本地合法导出经隔离转换；晋升需具名人工审核 + 新内容版本（`review-template.md`）
- 构建期依赖：Rust（`~/.cargo`），不链接进 App、不入 `project.yml`；`scripts/verify-tournament-content.sh` 重生成逐位一致
- 协作说明：本 change 的 propose/design/plan（Task 1–2）由一个并行会话完成后停止，其余（Task 3–9：求解导出、校验、导出/导入、真实批次、审核交接、终验）由本会话接手实现
- 未做（有意）：9-max/ante/ICM/limp/翻后；把内容接入可玩随机发牌训练 UI（下一步）；人工审核晋升

## tournament-pushfold-trainer-20260813-01

- 归档：2026-08-14 00:14
- 位置：`openspec/changes/archive/tournament-pushfold-trainer-20260813-01-20260814-001411`
- 新增能力：tournament-pushfold-training
- 修改能力：无（`m1a-release-safety` 既有要求不变）
- 交付（首个消费真实锦标赛内容的可玩训练，dogfood/debug）：把 20 个 `unverifiedDraft` push/fold 包打进 debug/dogfood（`Config/Release.xcconfig` 的 `EXCLUDED_SOURCE_FILE_NAMES` 追加 `tourn-hu-chip-ev-noante-*.json` 将其排除出 store）；`TournamentPushFoldLoader` 按深度加载（store 无包→入口消失）；训练器发随机 spot（深度×位置×发牌）、查该手 `rangeCell` 合成 per-hand `DecisionScenario`、用**未改动的 `DecisionScorer`** 评分、产生 `TrainingEvent`；作答与反馈两屏都披露"未经策略审核"。入口在「复盘」下（`review.tournamentPushFold`，四标签不变）
- 新增规格：1 个 Capability、4 个 Requirements
- 释安全：store 构建排除未审核包、`check-release-content.sh` 通过（store 仅 reviewed）、`verify-m1c.sh` 三频道 + 篡改探针全绿
- 附带修复：`ContentAuditTests` 跳过锦标赛导出（`export.tournament != nil`）——其现金局不变量（6-max 位置/下注树/整段频率）不适用于单挑 push/fold（此为归档的内容导入 change 落地后经陈旧缓存掩盖的回归，本次一并修）
- 验证：VM 单测（AA@10bb 全下 100/损失 0；弃牌 3478 milliBB blunder；空 bundle→不可用；手类映射）；UI 测试（复盘→训练器可达、披露未审核、作答→反馈）；`AdaptiveNavigationTests` 绿；四包套件绿
- 已知（不属本 change 的先存问题）：`check-m1b-release-secrets.sh` 的二进制串扫描对 `DevStrategyPack` 标记失败——该字面量来自 `BundledContentLoader.resourceNames`（既有 main 代码，非本 change 引入）
- 未做（有意）：ICM/多路/9-max/翻后训练；把未审核内容标 reviewed 或送 store；人工审核晋升
