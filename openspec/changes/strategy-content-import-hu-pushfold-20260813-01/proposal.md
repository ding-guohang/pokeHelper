---
name: strategy-content-import-hu-pushfold-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：导入可复现的单挑 ChipEV Push/Fold 策略内容

## Why

M3 已交付锦标赛结构、精确 ICM、push/fold 决策上下文与泡沫系数，但尚无可用于评分的
锦标赛策略真值。首批内容选择边界最清楚、可由开源求解器复现的单挑无 ante ChipEV
push/fold，以最小合法范围打通「求解 → 169 手牌表 → 未审核策略包 → 人工审核材料」链路。

GTO Wizard 等商业平台内容仅接受用户依其授权条款手工导出的文件；本项目不对其服务发起
自动化请求，也不把商业平台内容作为本 change 的内置数据源。

## What Changes

### New Capabilities

- `tournament-strategy-source-adapter` — 从锁定版本的 HU Push/Fold CFR+ 求解结果生成规范化、
  可追溯的 169 手牌频率表。
- `tournament-strategy-content-import` — 校验并导入 1–20BB 的 HU ChipEV Open-Jam 与
  Call-Jam 表，按精确深度生成 20 个确定性的未审核锦标赛策略包及审核报告。

### Modified Capabilities

- `strategy-content-pipeline` — 增加锦标赛精确深度、ante 声明、169 手牌完整性与来源
  产物哈希门禁，同时继续复用既有版本、来源、审核与黄金回归规则。
- `versioned-strategy-content` — 求解假设可表达锦标赛精确有效深度与 ante；未审核求解器
  内容不得被标为 `reviewed`。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: tournament-strategy-source-adapter

#### Requirement: 锁定并披露可复现来源

The system SHALL generate the bundled HU push/fold source tables only from
`b-inary/poker-cfr` at commit
`a5347082007ba1eda7932ef2fe7fad43cb3be2a1` (BSD-2-Clause), SHALL record the
solver commit, game assumptions, iteration count, exploitability, source-input
hashes, and generator version, and SHALL fail closed when any locked source
input differs.

##### Scenario: 锁定来源生成

- GIVEN 已获取与记录哈希一致的锁定求解器源码和预计算 HU 翻前 equity 数据
- WHEN 生成某一有效深度的 Push/Fold 结果
- THEN 产物记录完整 commit、BSD-2-Clause 许可证、迭代次数和 exploitability
- AND 假设明确为 NLHE tournament、heads-up、SB=0.5BB、BB=1BB、无 ante、rake=0、chipEV
- AND 生成过程不访问 GTO Wizard 或其他商业平台

##### Scenario: 锁定来源发生变化

- GIVEN 求解器源码或预计算 equity 数据的实际哈希与仓库记录不一致
- WHEN 启动生成
- THEN 生成以非零码失败并指出不匹配文件
- AND 不产生或覆盖任何规范化策略表

#### Requirement: 组合策略精确聚合为 169 手牌

The system SHALL aggregate the solver's 1,326 two-card combination frequencies
into exactly 169 canonical hand classes by legal combination count (6 pairs,
4 suited, 12 offsuit), convert action probabilities to integer basis points
using one documented deterministic rounding rule, and set the complementary
action so every hand class totals exactly 10,000 basis points. For every hand
class and legal action, the system SHALL also export the counterfactual action
EV produced by the same equilibrium evaluation, quantized deterministically to
integer milli-BB; it SHALL NOT synthesize EV from frequency or substitute a
zero placeholder.

##### Scenario: Open-Jam 聚合完整

- GIVEN 某深度的 SB combo-level push probabilities
- WHEN 生成 Open-Jam 表
- THEN 表中恰有 169 个不重复 canonical hand classes
- AND 每行只有 `allIn` 与 `fold`
- AND 每行 `allIn + fold = 10000`
- AND 每行同时包含 `allIn` 与 `fold` 各自的求解器反事实 EV（milli-BB 整数）
- AND 导入为内部 `RangeCell` 时，外部 `allIn` 确定性映射为既有行动键 `raise`
- AND 聚合前后的总 combo-weighted push probability之差仅来自已记录的 bps 量化误差
- AND 聚合前后的 action EV 误差仅来自已记录的 milli-BB 量化误差

##### Scenario: Call-Jam 聚合完整

- GIVEN 同一均衡中的 BB combo-level call probabilities
- WHEN 生成 Call-Jam 表
- THEN 表中恰有 169 个不重复 canonical hand classes
- AND 每行只有 `call` 与 `fold`
- AND 每行 `call + fold = 10000`
- AND 每行同时包含 `call` 与 `fold` 各自的求解器反事实 EV（milli-BB 整数）

##### Scenario: EV 不是求解器同源反事实值

- GIVEN 某手牌缺少任一合法行动的反事实 EV，或 EV 来自另一轮不同策略/参数的求解
- WHEN 生成规范化表
- THEN 生成以非零码失败并指出深度、节点、手牌和缺失/不一致行动
- AND 不得用 `0`、频率或启发式公式补齐 EV

#### Requirement: 行动 EV 与策略频率使用同一均衡快照

The system SHALL evaluate each pure action against the opponent reach
probabilities from the exact averaged equilibrium strategy snapshot whose
frequencies are exported, SHALL preserve card-removal effects at combo level
before hand-class aggregation, and SHALL record a snapshot hash tying
frequencies, action EVs, and NashConv together. The root SB action EV SHALL be
conditioned on the hero's dealt combo; the BB action EV SHALL additionally be
conditioned on the compatible SB range reaching the jam node. A zero reach
denominator SHALL be rejected rather than represented as zero EV. Hand-class
EV SHALL be the ratio of the sums of combo-level counterfactual numerators and
reach denominators, not an unweighted average of already-rounded combo EVs.

##### Scenario: 同一快照生成频率与 EV

- GIVEN 某深度已完成求解并冻结平均策略快照
- WHEN 导出 SB Open-Jam 与 BB Call-Jam 表
- THEN 每个 combo 的行动频率和每行动反事实 EV 均取自该快照
- AND 对手 reach probability 排除与英雄两张牌冲突的组合
- AND SB `fold` 的条件 EV 精确为 `-500` milli-BB
- AND 对可达的 BB 节点，BB `fold` 的条件 EV 精确为 `-1000` milli-BB
- AND 两张表、NashConv 与求解配置共同写入同一个 snapshot SHA-256

##### Scenario: 快照或阻断处理不一致

- GIVEN EV 计算使用不同策略快照，或未排除与英雄手牌冲突的对手组合
- WHEN 执行导出一致性校验
- THEN 导出失败并报告 snapshot hash 或阻断一致性错误
- AND 该深度不得进入规范化批次

##### Scenario: BB Jam 节点没有可达概率

- GIVEN 某个 BB combo 对应的所有兼容 SB combo 的 Jam reach 总和为零
- WHEN 计算该 combo 的 Call-Jam 行动 EV
- THEN 导出失败并指出该深度与 combo 的零分母
- AND 不得把未定义 EV 写成 `0`

#### Requirement: 覆盖 1–20BB 且记录收敛质量

The system SHALL generate Open-Jam and Call-Jam tables for each integer
effective depth from 1BB through 20BB and SHALL reject a table whose measured
NashConv exceeds the approved convergence threshold. If a report also displays
the conventional two-player exploitability, it SHALL label it explicitly as
`NashConv / 2`; the two values SHALL NOT be conflated.

##### Scenario: 首批覆盖完整

- GIVEN 深度集合 `{1, 2, ..., 20}`
- WHEN 完成批量生成
- THEN 恰有 20 张 Open-Jam 表和 20 张 Call-Jam 表
- AND 每张表标明对应的精确 `effectiveBigBlinds`
- AND 每张表的 NashConv 不超过同一份生成配置中声明的阈值

##### Scenario: 未达到收敛阈值

- GIVEN 某深度的求解结果 NashConv 高于声明阈值
- WHEN 生成器准备写入规范化表
- THEN 该深度生成失败并报告实际 NashConv 和阈值
- AND 该批次不得被导入策略包

### Capability: tournament-strategy-content-import

#### Requirement: 导入完整且假设一致的 HU Push/Fold 批次

The system SHALL import only a complete 1–20BB HU no-ante chipEV batch whose
tables and manifests agree on table size, positions, facing state, exact
effective depth, blind structure, ante, equilibrium, source, and content
version, and SHALL produce one immutable strategy pack per exact integer depth
so the existing pack-level `effectiveStack` remains truthful.

##### Scenario: 合法批次导入

- GIVEN 40 张通过来源、完整性、bps 与收敛门禁的规范化表
- WHEN 执行锦标赛策略导入
- THEN 产生 20 个 pack ID 含精确深度的内容包，每包恰有 SB Open-Jam 与 BB Call-Jam
  两个语义对应场景
- AND Open-Jam 使用 `tableSize=2`、`heroSeatOffsetFromButton=0`、`facing=unopened`
- AND Call-Jam 使用 `tableSize=2`、`heroSeatOffsetFromButton=1`、`facing=singleRaise`
- AND 求解假设可读取精确深度、`hasAnte=false` 与明确的无 ante 描述
- AND 每个 hand class 的每个合法行动均可读取 milli-BB EV
- AND 输出策略包通过 `StrategyPackValidator`

##### Scenario: 批次缺少一张表

- GIVEN 批次缺少 7BB Call-Jam 表但其余 39 张表均合法
- WHEN 执行导入
- THEN 导入以非零码失败并指出缺少 7BB Call-Jam
- AND 不产生策略包或 checksum

##### Scenario: 表含缺失、重复或非法手牌

- GIVEN 某表缺少 `72o`、重复 `AA`，或含非 canonical hand class
- WHEN 执行导入
- THEN 导入以非零码失败并指出文件和具体 hand class 问题
- AND 不产生策略包或 checksum

#### Requirement: 未经人工审核不得晋升

The system SHALL mark freshly generated solver content as `origin=solver` and
`reviewStatus=unverifiedDraft`, SHALL preserve source truth independently from
review state, and SHALL require an explicit later human-review operation with
reviewer identity, review timestamp, a new content version, and recorded
comparison evidence before producing `reviewed` content.

##### Scenario: 首次导入保持未审核

- GIVEN 合法且达到收敛阈值的开源 solver 批次
- WHEN 运行首批自动导入
- THEN manifest 为 `origin=solver` 与 `reviewStatus=unverifiedDraft`
- AND `generatedSource` 包含仓库、commit、生成配置和批次哈希
- AND 自动化命令不存在将本批次直接标成 `reviewed` 的参数路径

##### Scenario: 缺少人工签署时请求 reviewed

- GIVEN 内容未经具名策略审核，或缺少审核时间与比对记录
- WHEN 请求产出 `reviewed` 锦标赛内容
- THEN 操作失败并明确列出缺失审核材料
- AND 原 `unverifiedDraft` 内容保持不变

#### Requirement: 商业平台手工导出走隔离入口

The system SHALL accept a user-supplied PioSolver/GTO+ range text or documented
export file through a local conversion entry point, SHALL never fetch such
content from the commercial platform, SHALL record the platform and
user-supplied provenance, and SHALL subject converted data to the same 169-hand,
bps, assumption, review, and license-evidence gates.

##### Scenario: 用户提供合法导出

- GIVEN 用户本地提供一份商业平台允许其导出的范围文件及使用授权说明
- WHEN 运行本地转换
- THEN 转换器不访问外部网络
- AND 输出记录来源平台、用户提供的原文件 SHA-256 与授权说明引用
- AND 输出仍为 `unverifiedDraft`，除非另行完成具名人工审核

##### Scenario: 请求自动抓取商业平台

- GIVEN 没有平台提供的再利用授权或官方自动化 API 授权
- WHEN 请求转换器直接登录、抓取或遍历商业平台解算库
- THEN 工具拒绝执行该网络操作
- AND 提示改用用户手工合法导出的本地文件

### Capability: strategy-content-pipeline

#### Requirement: 锦标赛求解器输出导入

The system SHALL extend solver-output import with tournament exact-depth,
ante-assumption, 169-hand completeness, convergence, and provenance validation,
while preserving deterministic output, atomic writes, semantic validation, and
golden regression behavior of the existing strategy content pipeline.

##### Scenario: 同一批次确定性导入

- GIVEN 同一份锁定的 40 表输入、相同 manifest 和相同 content version
- WHEN 在两个独立进程中各导入一次
- THEN 两次生成的 20 个策略包逐包字节与 SHA-256 完全相同
- AND 不把系统时钟、临时路径或字典哈希顺序写入产物

##### Scenario: 原子失败

- GIVEN 第 40 张表违反 bps 总和或来源哈希门禁
- WHEN 导入完整批次
- THEN 命令以非零码失败
- AND 最终输出目录不存在部分策略包或部分 checksum

#### Requirement: 首批内容黄金回归基线

The system SHALL create a signed-in-repository golden baseline for all 20 packs
in the first unverified HU batch and SHALL require later content versions to
report all frequency and action-EV changes and fail on unapproved changes
beyond the configured tolerance.

##### Scenario: 首次建立基线

- GIVEN 通过全部门禁的首批未审核策略包
- WHEN 建立黄金基线
- THEN 仓库记录 20 个策略包的 SHA-256、40 张表的输入哈希与关键覆盖统计
- AND 后续同版本重建得到相同字节

### Capability: versioned-strategy-content

#### Requirement: 锦标赛求解假设可追溯

The system SHALL expose exact effective big blinds and ante assumptions on
tournament strategy scenarios without changing the meaning of existing cash
content, and SHALL decode legacy schema-1 cash packs with their current
semantics.

##### Scenario: 锦标赛假设加载

- GIVEN 一个合法 HU no-ante tournament scenario
- WHEN loader 解码并校验
- THEN 可读取精确整数 `effectiveBigBlinds`
- AND 可读取 `hasAnte=false` 与非空 `anteDescription`
- AND 现金内容现有 `effectiveStack`、rake 与下注尺度字段语义不变

##### Scenario: 旧现金包兼容

- GIVEN 当前已发布的 schema-1 现金策略包不含新增锦标赛可选字段
- WHEN 新版 loader 加载
- THEN 解码与校验结果保持成功
- AND 不把缺失字段解释为未经声明的锦标赛假设

## Impact

- **Code:** `Content/` 新增锁定来源配置、HU 求解适配器、规范化表与审计材料；
  `Packages/StrategyTooling/` 新增锦标赛批次导入/校验；`Packages/StrategyContent/` 对
  `SolverAssumptions` 做向后兼容的加法扩展，并让 tournament `RangeCell` 可携带每行动
  milli-BB EV，增加 rangeCells 完整性门禁。
- **Interfaces:** 新增本机 CLI/脚本入口与内容产物；本 change 不新增训练 UI、不产生
  `TrainingEvent`、不改变现有现金训练选择逻辑。
- **Dependencies:** 构建时使用锁定 commit 的 BSD-2-Clause Rust 求解器；不链接进 App，
  不成为运行时依赖。不得引入 GTO Wizard 自动化或其范围数据作为仓库内置依赖。

## Risks

- **求解未收敛却被当真值** → 每个深度记录并门禁 NashConv（若展示 conventional
  exploitability 则明确为 NashConv/2），人工审核前保持
  `unverifiedDraft`。
- **开源实现本身有错误** → 锁定源码与 equity 数据哈希；用独立公开 HU Nash 样本抽查
  边界手与总体频率，并保留差异报告供人工审核。
- **169 聚合/量化改变混合频率** → 组合数加权、确定性 bps 量化、互补行动补足 10,000，
  记录聚合前后误差。
- **EV 与范围不同源、未按 reach 归一化或忽略 blocker** → 同一冻结平均策略快照计算
  combo-level 纯行动反事实分子；SB 按持牌概率条件化，BB 再按兼容 SB Jam reach 条件化；
  先应用牌张移除再聚合，并用 snapshot hash 绑定频率、EV 与 NashConv。
- **新增 assumptions 破坏现金包** → 字段仅做向后兼容加法，旧资源解码测试必须通过。
- **内容被误标为已审核** → 自动导入只能生成 `unverifiedDraft`；晋升需要独立具名流程和
  新 content version。
- **商业来源许可不清** → 不自动抓取；仅转换用户本地提供且带授权说明的导出文件。
- **与当前未提交 ICM UI 修改冲突** → 本 change 不修改
  `PokerCoach/Features/TournamentICM/` 或其现有测试。

## Non-Goals

- 不抓取、遍历或自动登录 GTO Wizard 等商业平台。
- 不在首批实现 9-max、ante/BBA、ICM、非全下开池或翻后策略。
- 不把开源 solver 产出自动声明为已人工审核内容。
- 不在本 change 中把锦标赛范围接入可玩的随机发牌训练 UI。
- 不新增 App 运行时第三方依赖或联网求解。
- 不接受缺失或填造的每手 EV；无法导出同源 hand/action 反事实 EV 的深度整批失败。

## Acceptance Criteria

1. 锁定并验证 `b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`
   与预计算 equity 输入哈希，许可证记录为 BSD-2-Clause。
2. 生成 HU、SB=0.5BB、BB=1BB、无 ante、rake=0、chipEV、1–20BB 的 20 张 Open-Jam
   与 20 张 Call-Jam 表；每张恰有 169 手牌，每行行动 bps 和为 10,000，并含每个合法
   行动的同源反事实 EV（milli-BB）。
3. 每个深度记录 iterations 与 NashConv，任何超过声明阈值的表不能导入；若另报
   conventional exploitability，必须明确等于 NashConv/2。
4. 每个深度的频率、行动 EV 与 NashConv 来自同一平均策略快照，并用 snapshot
   SHA-256 绑定；combo-level 阻断生效后才聚合为 169 类。
   SB fold EV 必须为 `-500` milli-BB；可达的 BB fold EV 必须为 `-1000` milli-BB；
   BB reach 零分母必须失败。
5. 按 1–20BB 生成 20 个精确深度内容包，每包只有对应深度的 Open-Jam 与 Call-Jam；
   产物为 `origin=solver` + `reviewStatus=unverifiedDraft`，包含 solver commit、配置、
   输入哈希、content version 与生成时间。
6. 同输入在两个独立进程逐包生成字节一致的策略包与 SHA-256；失败不留下部分产物。
7. `StrategyPackValidator`、StrategyContent/StrategyTooling 单测、旧现金包兼容测试与
   首批黄金基线检查全部通过。
8. 提供人工审核报告模板与本地商业平台导出转换入口；二者都不能绕过来源、169 手、
   bps、假设和审核门禁。
9. 不修改当前工作树中未提交的 TournamentICM UI 文件。
