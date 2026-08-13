# 锦标赛策略内容需求（提供给内容来源方 / 审核人）

本文件说明：要把已建好的 M3 锦标赛引擎变成**可玩的锦标赛训练**，需要你提供什么样的
策略内容、以什么格式、经过什么审核。引擎侧（结构、ICM、push/fold 上下文、泡沫系数、
ICM 计算器）已全部交付且**内容无关**；缺的唯一一块是**策略真值**——哪些手该全下/
跟注/开池的范围与频率。这块**不能编造**，必须来自真实求解器或经人工审核的来源。

> 谁读这份文档：负责产出/采购/审核锦标赛范围数据的人。读完你应能：知道先交哪些表、
> 每张表要填什么、要钉死哪些假设、以及交付格式。

---

## 0. 铁律（不可协商，来自项目既有约定）

1. **不编造策略真值**。范围/频率/EV 必须有真实来源（solver 导出或公开可核对的
   Nash push/fold 表），并经人工审核。没有来源的表一律不进 App。
2. **精确整数单位**。每个决策节点内各行动的频率以 **basis points** 表示，**同一节点
   总和恒为 10,000**（例：全下 62% = 6200，弃牌 38% = 3800，和 = 10000）。不接受
   百分比小数作为真值。EV 以 **milli-BB** 整数表示（可选，见 §4）。
3. **溯源与审核分离**。`origin`（数据从哪来：`solver` / `generativeModel`）与
   `reviewStatus`（有没有人核对过：`reviewed` 必须带 `reviewedBy` + `reviewedAt`）
   是两件事。人工审核不能把生成内容“变成”求解器产出。
4. **已发布内容不可原地改**。任何修订出新的 `contentVersion`，并过黄金回归比对。
5. **每张表必须钉死其假设**（人数、ante、chipEV 还是 ICM、若 ICM 则 payout 结构）。
   同一位置同一深度，有无 ante、chipEV vs ICM 的范围可以差很多。

---

## 1. 范围与优先级（分两期，先易后确定）

### 第一期（MVP，最成熟、最无歧义）——**ChipEV 单挑/多人 Push/Fold**

短筹码「全下或弃牌」的 chipEV 纳什均衡表是公开、成熟、可核对的（Nash push/fold）。
先交这批，能立刻支撑一个真实有用的短筹码训练：

- **开局全下（Open-Jam / RFI-Jam）**：对每个位置、每个有效深度，给「全下 vs 弃牌」
  的 169 手牌频率表。未加注传到英雄（`facing = unopened`）。
- **面对全下跟注（Call-Jam）**：对（英雄位置、全下者位置、有效深度），给「跟注 vs
  弃牌」的 169 手牌频率表。

覆盖建议（可分批）：
- 人数：先 **单挑（heads-up, tableSize=2）** 与 **9-max**（或你的目标桌型）。
- 有效深度：**1–20 BB**，每 1 BB 一档（push/fold 表通常逐 BB 变化）；若来源按档
  （如 8–10bb）给，也可，但要标明档口。
- ante：**必须两套或明确其一**——「有 ante」与「无 ante」，并注明 ante 大小（如
  1 BB ante / big-blind-ante）。

### 第二期（更难、更依赖情境）——**ICM 调整范围**

泡沫/决赛桌的开池/跟注范围依赖 payout 结构与各家筹码，是情境特定的：

- 需要指定 **payout 结构** 与 **筹码分布**（引擎能算 ICM 权益/泡沫系数，但“据此该
  怎么打”的范围仍是策略真值，要来源+审核）。
- 建议以「典型泡沫/决赛桌情境集」的形式提供，每个情境钉死 payout 与筹码，再给范围。

> 不在本需求内（有意）：翻后打法、对手打法模型（可玩 sim 的对手 = 也是内容，另议）。

---

## 2. 每张表要提供的数据（逐表 schema）

一张「表」= 一个（人数、位置、面对情形、有效深度、ante 假设、chipEV/ICM）确定下的
**169 手牌 → 行动频率** 映射。字段：

| 字段 | 含义 | 取值 |
|---|---|---|
| `tableSize` | 桌上人数 | 2–9 的整数 |
| `heroSeatOffsetFromButton` | 英雄相对按钮的座位偏移 | `0..<tableSize`，`0`=BTN（单挑 0=BTN/SB） |
| `facing` | 英雄面对的情形 | `unopened`（开局）/ `singleRaise`（面对一个全下/加注）/ `reraise` |
| `opponentSeatOffsetFromButton` | 仅 Call-Jam 表：全下者位置 | `0..<tableSize` |
| `effectiveBigBlinds` | 有效深度（BB） | 正整数（如 `10`）；若按档给，标明档 `[lo,hi]` |
| `hasAnte` / `anteDescription` | ante 假设 | 布尔 + 文字（如 “每人 0，无 ante” / “大盲 ante 1BB”） |
| `equilibrium` | chipEV 还是 ICM | `chipEV` / `ICM`（ICM 需附 §3 的 payout 与筹码） |
| `source` | 数据来源 | solver 名+版本 或 公开表引用（可核对） |
| `handClass` | 169 手牌之一 | 如 `AA`、`AKs`、`AKo`、`72o`（同花 `s`、非同花 `o`、对子如 `77`） |
| `actionWeightsBasisPoints` | 该手牌各行动频率 | 映射，**总和 = 10000**；键用行动名（见下） |

**行动名**（push/fold 期只需前两个）：
- `allIn`（全下）、`fold`（弃牌）；（开池非全下期可扩展 `raise`/`call`/`check`）。

**169 手牌必须全覆盖**：13 对子 + 78 同花 + 78 非同花 = 169 个 `handClass`，
每个都要给（哪怕是 `{fold:10000}`）。缺失手牌 = 表不完整，不予导入。

---

## 3. 必须钉死的假设（否则不导入）

对每一批表，随附一段「假设声明」：

- **游戏类型**：如 `NLHE 锦标赛`。
- **桌型/人数**：`tableSize`。
- **ante**：有无、大小、类型（传统 ante / big-blind ante）。
- **均衡口径**：`chipEV`（纳什）还是 `ICM`。
  - 若 `ICM`：附 **payout 结构**（第 1..k 名，整数最小货币单位，如 cents）与本表所设
    **筹码分布**（各家 chips）。引擎用这些算 ICM，但范围本身仍需来源+审核。
- **rake**：锦标赛通常 **0**（如非 0，注明）。
- **盲注**：SB/BB 结构（用于把 BB 深度换算成筹码，若来源以 BB 表达可留空由引擎换算）。

---

## 4. 溯源与审核要求

每批内容随附下列元信息（对应内容包 manifest）：

- `origin`：`solver`（来自求解器，注明 solver 名与版本/运行参数）或 `generativeModel`
  （生成，须永久披露；即便审核过，界面也会显示“非求解器产出，已人工审核”）。
- `reviewStatus`：交付审核通过的内容为 `reviewed`，且**必须**带：
  - `reviewedBy`：审核人（对该策略负责的人）。
  - `reviewedAt`：审核时间（ISO8601）。
- `generatedSource`：一句话来源描述（如 “HoldemResources Nash push/fold, 9-max, no ante”）。
- `contentVersion`：本批内容版本号（每次修订必换）。

EV（`ev`，milli-BB 整数）为**可选**：push/fold 训练只用频率也能评分；若来源提供每手
EV，可一并给，但不得由生成文本编造 EV。

---

## 5. 现有 schema 的缺口（实现前需与我确认的取舍）

现金内容 schema（`DecisionScenario` / `SolverAssumptions` / `SpotSignature`）是为现金
100BB 设计的，锦标赛内容会撞上三处，需先定方案（**这几处由我在收到内容后按你的选择
实现，属工程决策，不影响你产数据**）：

1. **深度作为一等轴**。现有 `StackBucket` 只有 `short(<20bb)/medium/deep/veryDeep`
   四档，太粗，撑不住逐 BB 变化的 push/fold。方案候选：(a) 每个深度出一个内容包
   （`content-tourn-pushfold-9max-noante-10bb` 之类）；(b) 扩展 scenario 携带精确
   `effectiveBigBlinds` 并新增细粒度覆盖键。**倾向 (a)**（不改冻结的覆盖键语义）。
2. **ante 字段**。`SolverAssumptions` 无 ante 字段。方案：加 `anteDescription`
   （加法、可选），或用不同包 ID 区分有/无 ante。
3. **ICM/payout 假设**。第二期 ICM 表需要在 assumptions 里记 payout 与筹码。方案：
   ICM 内容包的 assumptions 增记 payout 结构引用（加法字段）。

你只需按 §2/§3 产出数据；上述 (a)/(b) 由我实现时定并回报。

---

## 6. 交付格式与流程

1. **你交**：每张表一个 CSV 或 JSON（169 行 `handClass` + 各行动 bps，行内总和 10000），
   外加 §3 假设声明 + §4 元信息。模板见 §8。
2. **我做**：写一个锦标赛导出脚本（仿 `Content/build-core-export.py`）把你的表转成
   `Content/exports/tourn-*.json`，再用 `strategy-import` 生成已审核内容包
   （`--review-status reviewed --origin solver --reviewed-by … --reviewed-at …`），
   跑 `strategy-golden` 黄金回归。
3. **门禁**：内容包按频道限制审核状态（store 只允许 `reviewed`）；每行总和≠10000、
   缺手牌、`reviewed` 缺 `reviewedBy` 一律被校验器拒绝。

---

## 7. 验收标准（每批内容）

- [ ] 覆盖声明的（人数 × 位置 × facing × 深度 × ante）组合，无缺表。
- [ ] 每张表 169 手牌齐全，每行 bps 总和 = 10000。
- [ ] 假设声明完整（人数/ante/均衡口径/payout(若ICM)/rake）。
- [ ] 元信息完整：`origin` + `reviewStatus=reviewed` + `reviewedBy` + `reviewedAt` +
      `generatedSource` + `contentVersion`。
- [ ] 有可核对的来源（solver 名+版本或公开表引用）。
- [ ] 通过校验器与黄金回归。

---

## 8. 交付模板（示例：Open-Jam 一张表，**数字留空由你填**）

```
# 假设声明
gameType: NLHE 锦标赛
tableSize: 9
facing: unopened            # 开局全下
heroSeatOffsetFromButton: 3 # 例：UTG（9-max 下按你的座位定义）
effectiveBigBlinds: 10
hasAnte: true
anteDescription: 大盲 ante 1BB
equilibrium: chipEV         # 纳什 push/fold
rake: 0
source: <solver 名 + 版本 / 公开表引用>
origin: solver
reviewStatus: reviewed
reviewedBy: <审核人>
reviewedAt: <ISO8601>
contentVersion: <版本号>

# 169 手牌 → 行动频率（basis points，行内 allIn+fold=10000）
handClass,allIn,fold
AA,10000,0
AKs,,           # ← 填：如 10000,0
...             # ← 共 169 行，对子13 + 同花78 + 非同花78
72o,0,10000
```

> 再次强调：本文件不含任何真实范围数字。上面的 `AA=10000/0` 只是格式示例；实际每手
> 的频率必须来自你提供的真实来源，我不会替你填。
