---
name: strategy-content-import-hu-pushfold-20260813-01
status: designed
---

# HU Push/Fold 策略内容导入设计

## 1. 目标与可信度边界

本 change 交付第一批真实求解的锦标赛策略内容：单挑、SB=0.5BB、BB=1BB、无 ante、
rake=0、chipEV、1–20BB，每个深度包含 SB Open-Jam 与 BB Call-Jam。

数字不由生成模型或人工规则填写。频率、每手每行动 EV 和收敛指标来自同一份冻结 CFR+
平均策略快照，且每次生成都能追溯到固定源码、固定 equity 数据、固定参数与输入哈希。

首批自动产物固定标记为：

- `origin=solver`
- `reviewStatus=unverifiedDraft`

这表示“真实求解器产出、通过工程门禁，但尚未由具名扑克策略审核人签署”。内容只有在
独立范围抽查、差异记录和具名签署完成后，才能用新 `contentVersion` 晋升为 `reviewed`。

GTO Wizard 不作为自动数据源。后续只允许转换用户依平台授权手工导出的本地文件。

## 2. 方案选择

采用“固定上游求解器 + 仓库维护的最小导出补丁 + 本地 Swift 导入器”。

不重写 CFR 算法，因为重写会新增一套尚未验证的策略真值实现；也不从商业平台抓取，
因为自动化访问和第三方应用使用受平台条款限制。固定上游实现可以保留其已存在的 CFR+、
发牌概率和预计算 equity 语义；仓库补丁只增加只读导出，不改变训练更新公式。

锁定来源：

| 输入 | 锁定值 |
|---|---|
| 仓库 | `b-inary/poker-cfr` |
| commit | `a5347082007ba1eda7932ef2fe7fad43cb3be2a1` |
| 许可证 | BSD-2-Clause |
| `src/game_push_fold.rs` SHA-256 | `31f40d9069bccf6c0bb06d172ef7f2d3ad11d80caa498c5bbeec684c0d23ce48` |
| `src/cfr.rs` SHA-256 | `6e67183dc0d05b34e3a866fecd3e0e76847b4feb406f37ea01f70563ba9bd6bf` |
| equity binary SHA-256 | `006404b36d257fc9455da0d0f0ab89aef3e80ece56c8f3e770bad926cfe5ec8a` |

仓库保存来源 manifest、许可证副本、导出补丁和生成脚本，不把求解器链接进 App。生成脚本
将锁定源码放入临时/缓存目录，先验哈希再应用补丁；哈希不符即停止。规范化结果与最终
内容包签入仓库，所以 App 构建与运行不依赖网络或 Rust。

## 3. 产物与目录

```text
Content/
  tournament/
    source-lock.json                 # 上游 commit、文件 URL、SHA-256、许可证
    patches/poker-cfr-hu-export.patch
    generate-hu-pushfold.sh          # 获取/验源/补丁/运行/批次原子替换
    validate-hu-batch.py             # 独立校验规范化 JSON 与审计不变量
    review-template.md               # 人工审核模板
    commercial-export/README.md      # 仅本地手工导出的转换约束
  tournament-normalized/
    hu-chip-ev-noante-01bb.json
    ...
    hu-chip-ev-noante-20bb.json
  exports/
    tourn-hu-chip-ev-noante-01bb.json
    ...
    tourn-hu-chip-ev-noante-20bb.json
  packs/
    tourn-hu-chip-ev-noante-01bb.json
    ...
    tourn-hu-chip-ev-noante-20bb.json
```

每个 normalized 文件保存一个深度的两张 169 手表、combo 聚合审计信息、iterations、
NashConv、`NashConv/2`、上游输入哈希、求解配置与 snapshot SHA-256。生成时间是配置中的
固定 `exportedAt`，而不是运行时钟，保证相同输入输出相同字节。

## 4. 求解与收敛

### 4.1 游戏语义

锁定上游的 public history：

- `[]`：SB 决策；动作 `0=fold`、`1=jam`
- `[1]`：SB jam 后 BB 决策；动作 `0=fold`、`1=call`

有效深度 `S` 是开局总筹码 BB。上游收益：

- SB 首先弃牌：`-0.5BB`
- BB 面对 jam 弃牌：`-1BB`
- 摊牌：`S × (2 × equity - 1) BB`
- SB jam、BB fold：SB `+1BB`

### 4.2 确定性配置

- Rust toolchain 由来源 manifest 固定。
- `RAYON_NUM_THREADS=1`，避免线程调度改变浮点归约顺序。
- 深度按 `1...20` 固定升序处理。
- CFR+ checkpoint 依次为 `10_000`、`20_000`、`40_000`、`80_000`、`160_000`
  iterations；训练连续进行，不在 checkpoint 间重启。
- 第一个满足 `NashConv <= 0.001 BB/hand` 的 checkpoint 成为冻结快照。
- `160_000` 后仍不满足则该深度失败，整批不发布。

上游函数名为 `compute_exploitability`，实际返回两位玩家最佳回应收益之和，即 NashConv。
产物记录 `nashConvBB` 原值，并另记 `exploitabilityBB = nashConvBB / 2`，不混用名称。

## 5. 每手频率和行动 EV

### 5.1 不能直接使用现有详细 EV 函数

上游 `compute_ev_detail` 会乘入英雄自身 reach，并保存混合策略后的节点/终局加权值；
它不是“固定某一纯行动后，在已发到该手牌条件下”的行动 EV。导出补丁新增独立只读
evaluator：不修改 CFR regret 或平均策略，只读取冻结 `avg_sigma`。

### 5.2 条件 EV

令：

- `h` 为英雄两张牌 combo；
- `C(h)` 为与 `h` 不冲突的 1,225 个对手 combo；
- `q = 4 / (52×51×50×49) = 1 / 1,624,350`；
- `E(h,o)` 为英雄对对手 combo 的 equity；
- `S` 为有效深度 BB。

SB：

```text
D_SB(h)     = q × 1225 = 1/1326
N_fold(h)   = -0.5 × D_SB(h)
N_jam(h)    = q × Σ_o [
                  σ_BB(fold|o) × 1
                + σ_BB(call|o) × S × (2E(h,o)-1)
              ]
Q_action(h) = N_action(h) / D_SB(h)
```

BB 必须额外条件于“兼容的 SB combo 已到达 jam 节点”：

```text
D_BB(h)     = q × Σ_o σ_SB(jam|o)
N_fold(h)   = -1 × D_BB(h)
N_call(h)   = q × Σ_o σ_SB(jam|o) × S × (2E(h,o)-1)
Q_action(h) = N_action(h) / D_BB(h)
```

若 `D_BB(h) == 0`，该 combo 的节点 EV 未定义，整档失败，不能写成零。

### 5.3 聚合为 169 类

策略频率先在 1,326 combo 层产生，再按合法 combo 数聚合：

- 对子 6 个；
- 同花非对子 4 个；
- 非同花 12 个。

每类行动 EV 使用：

```text
Q_action(class) = Σ_h N_action(h) / Σ_h D(h)
```

因此 SB 自然等权，BB 自动按“SB jam 后的 blocker reach”加权。不能先把 combo EV 四舍五入
再简单平均。

量化仅发生在最后：

- 频率：half-away-from-zero 到 bps；互补行动取 `10000 - 主行动bps`；
- EV：half-away-from-zero 到 milli-BB。

normalized 表使用外部语义 `allIn/fold` 与 `call/fold`。导入 `RangeCell` 时，`allIn`
映射到既有内部范围键 `raise`，与 `RangeBaseline.actionKey(.allIn)` 保持一致。

## 6. 内容模型

### 6.1 锦标赛 assumptions 隔离

`SolverAssumptions` 新增可选的嵌套字段：

```swift
public struct TournamentSolverAssumptions: Codable, Hashable, Sendable {
    public let effectiveBigBlinds: Int
    public let smallBlindCentiBB: Int
    public let bigBlindCentiBB: Int
    public let hasAnte: Bool
    public let anteDescription: String
    public let equilibrium: TournamentEquilibrium
}

public let tournament: TournamentSolverAssumptions?
```

现有 schema-1 现金包缺少该键时解码为 `nil`，其 `effectiveStack`、rake 和下注尺度语义不变。
锦标赛 validator 要求该嵌套对象完整，不允许部分 assumptions。

### 6.2 RangeCell 保存每手行动 EV

`RangeCell` 新增可选 `actionEVs: [String: EVAmount]?`。现金旧包为 `nil`；锦标赛表必须：

- 恰有全部 169 canonical hand classes；
- 每类频率键与 EV 键相同；
- 频率键只允许 `fold/raise` 或 `fold/call`；
- 每类频率总和为 10,000；
- 所有 EV 为 milli-BB 整数。

`SolverRangeCell` 同步增加可选字段，`PackBuilder` 原样传递，不自行推导 EV。

### 6.3 每深度独立 pack

沿用文档已倾向的“每深度独立包”，不改变冻结的粗粒度 `SpotCoverageKey`：

```text
content-tourn-hu-pushfold-chip-ev-noante-01bb
...
content-tourn-hu-pushfold-chip-ev-noante-20bb
```

每包仅两个 scenario。`SolverAssumptions.effectiveStack` 表示开局总深度 `S`；新增
`SolverNode.decisionEffectiveStack` 表示决策时尚可投入的筹码：

- SB：`S - 0.5BB`，`amountToCall=0.5BB`，`pot=1.5BB`；
- BB：`S - 1BB`，`amountToCall=S - 1BB`，`pot=S + 1BB`。

这避免把已投入盲注重复算入合法行动。Open-Jam options 是 fold/all-in；Call-Jam options
是 fold/call。

每个 scenario 以 `AA` 作为稳定展示样例，`StrategyOption` 的频率和 EV 取 `AA` 的
`RangeCell`。完整 169 手的频率与 EV 全部保存在 `rangeCells`；本 change 不接入随机发牌
训练，后续训练接入需按实际 hand class 从 `RangeCell` 物化 options。

## 7. 导入与原子性

生成器先在批次临时目录产生全部 20 个 normalized 文件；独立 Python validator 校验通过后
才原子替换正式 normalized 目录。Swift tournament exporter 再生成 20 个 `SolverExport`，
`strategy-import` 以固定参数输出 20 个 pack 和 checksum。

自动入口固定：

```text
origin=solver
reviewStatus=unverifiedDraft
reviewedBy=nil
reviewedAt=nil
```

锦标赛批量命令不暴露 `--review-status reviewed`。人工晋升是未来独立命令，必须读取完成的
审核报告、要求 reviewer/time/new contentVersion，并运行 golden regression。

任一深度失败时，不替换任何正式表或 pack。已存在的旧版本保持不变。

## 8. 商业平台本地导出入口

本 change 只建立格式说明与离线转换边界，不内置 GTO Wizard 内容：

1. 用户在平台允许的界面手工导出 PioSolver/GTO+ 文本；
2. 用户提供本地文件和授权说明引用；
3. 转换器只读本地文件，不访问网络；
4. 保存原文件 SHA-256 和来源说明；
5. 仍通过 169 手、频率、EV、assumptions 与审核门禁。

如果导出只有范围频率而没有同源每行动 EV，该文件不能成为本 App 可评分内容。

## 9. 验证策略

### 求解器导出不变量

- equity 全表满足 `E(h,o) + E(o,h) = 1`；
- SB fold EV 精确为 `-500` milli-BB；
- 可达 BB fold EV 精确为 `-1000` milli-BB；
- combo 混合 EV 重建上游 SB overall EV；
- 双方 profile EV 和约为零；
- 独立最佳回应枚举重建 NashConv；
- snapshot hash 同时覆盖频率、EV、NashConv 与配置。

### 规范化与内容门禁

- 20 个深度 × 2 张表；
- 每表恰有 169 个不重复 canonical hand classes；
- 每行合法行动齐备且 bps 和为 10,000；
- 每行频率键与 EV 键一致；
- assumptions、深度、位置和 facing 与文件名一致；
- 缺表、重复手、未知手、零 reach、超 NashConv、错误哈希均原子失败。

### 向后兼容与确定性

- 当前 CoreStrategyPack schema-1 资源继续成功解码；
- 现有现金 range baseline 与 checksum 相关测试不变；
- 两个独立进程逐包生成相同字节与 SHA-256；
- `git diff` 确认不触碰当前未提交的 TournamentICM UI 文件。

## 10. 非目标

- 不提供 9-max、ante/BBA、ICM、limp、小加注或翻后范围。
- 不把未经人工签署的内容描述为“已审核”。
- 不在本 change 中接入可玩锦标赛训练 UI。
- 不运行或抓取 GTO Wizard。
- 不把 Rust 或其他第三方库加入 App 运行时。
