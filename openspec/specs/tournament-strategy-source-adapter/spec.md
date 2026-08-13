# Capability: tournament-strategy-source-adapter

## Requirement: 锁定并披露可复现来源

The system SHALL generate the bundled HU push/fold source tables only from
`b-inary/poker-cfr` at commit
`a5347082007ba1eda7932ef2fe7fad43cb3be2a1` (BSD-2-Clause), SHALL record the
solver commit, game assumptions, iteration count, exploitability, source-input
hashes, and generator version, and SHALL fail closed when any locked source
input differs.

### Scenario: 锁定来源生成

- GIVEN 已获取与记录哈希一致的锁定求解器源码和预计算 HU 翻前 equity 数据
- WHEN 生成某一有效深度的 Push/Fold 结果
- THEN 产物记录完整 commit、BSD-2-Clause 许可证、迭代次数和 exploitability
- AND 假设明确为 NLHE tournament、heads-up、SB=0.5BB、BB=1BB、无 ante、rake=0、chipEV
- AND 生成过程不访问 GTO Wizard 或其他商业平台

### Scenario: 锁定来源发生变化

- GIVEN 求解器源码或预计算 equity 数据的实际哈希与仓库记录不一致
- WHEN 启动生成
- THEN 生成以非零码失败并指出不匹配文件
- AND 不产生或覆盖任何规范化策略表

## Requirement: 组合策略精确聚合为 169 手牌

The system SHALL aggregate the solver's 1,326 two-card combination frequencies
into exactly 169 canonical hand classes by legal combination count (6 pairs,
4 suited, 12 offsuit), convert action probabilities to integer basis points
using one documented deterministic rounding rule, and set the complementary
action so every hand class totals exactly 10,000 basis points. For every hand
class and legal action, the system SHALL also export the counterfactual action
EV produced by the same equilibrium evaluation, quantized deterministically to
integer milli-BB; it SHALL NOT synthesize EV from frequency or substitute a
zero placeholder.

### Scenario: Open-Jam 聚合完整

- GIVEN 某深度的 SB combo-level push probabilities
- WHEN 生成 Open-Jam 表
- THEN 表中恰有 169 个不重复 canonical hand classes
- AND 每行只有 `allIn` 与 `fold`
- AND 每行 `allIn + fold = 10000`
- AND 每行同时包含 `allIn` 与 `fold` 各自的求解器反事实 EV（milli-BB 整数）
- AND 导入为内部 `RangeCell` 时，外部 `allIn` 确定性映射为既有行动键 `raise`
- AND 聚合前后的总 combo-weighted push probability之差仅来自已记录的 bps 量化误差
- AND 聚合前后的 action EV 误差仅来自已记录的 milli-BB 量化误差

### Scenario: Call-Jam 聚合完整

- GIVEN 同一均衡中的 BB combo-level call probabilities
- WHEN 生成 Call-Jam 表
- THEN 表中恰有 169 个不重复 canonical hand classes
- AND 每行只有 `call` 与 `fold`
- AND 每行 `call + fold = 10000`
- AND 每行同时包含 `call` 与 `fold` 各自的求解器反事实 EV（milli-BB 整数）

### Scenario: EV 不是求解器同源反事实值

- GIVEN 某手牌缺少任一合法行动的反事实 EV，或 EV 来自另一轮不同策略/参数的求解
- WHEN 生成规范化表
- THEN 生成以非零码失败并指出深度、节点、手牌和缺失/不一致行动
- AND 不得用 `0`、频率或启发式公式补齐 EV

## Requirement: 行动 EV 与策略频率使用同一均衡快照

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

### Scenario: 同一快照生成频率与 EV

- GIVEN 某深度已完成求解并冻结平均策略快照
- WHEN 导出 SB Open-Jam 与 BB Call-Jam 表
- THEN 每个 combo 的行动频率和每行动反事实 EV 均取自该快照
- AND 对手 reach probability 排除与英雄两张牌冲突的组合
- AND SB `fold` 的条件 EV 精确为 `-500` milli-BB
- AND 对可达的 BB 节点，BB `fold` 的条件 EV 精确为 `-1000` milli-BB
- AND 两张表、NashConv 与求解配置共同写入同一个 snapshot SHA-256

### Scenario: 快照或阻断处理不一致

- GIVEN EV 计算使用不同策略快照，或未排除与英雄手牌冲突的对手组合
- WHEN 执行导出一致性校验
- THEN 导出失败并报告 snapshot hash 或阻断一致性错误
- AND 该深度不得进入规范化批次

### Scenario: BB Jam 节点没有可达概率

- GIVEN 某个 BB combo 对应的所有兼容 SB combo 的 Jam reach 总和为零
- WHEN 计算该 combo 的 Call-Jam 行动 EV
- THEN 导出失败并指出该深度与 combo 的零分母
- AND 不得把未定义 EV 写成 `0`

## Requirement: 覆盖 1–20BB 且记录收敛质量

The system SHALL generate Open-Jam tables for each integer effective depth from
1BB through 20BB and Call-Jam tables for each integer effective depth from 2BB
through 20BB. It SHALL NOT create a 1BB Call-Jam decision because the BB has no
chips remaining after posting the 1BB blind. The system SHALL reject a table
whose measured NashConv exceeds the approved convergence threshold. If a
report also displays the conventional two-player exploitability, it SHALL
label it explicitly as `NashConv / 2`; the two values SHALL NOT be conflated.

### Scenario: 首批覆盖完整

- GIVEN 深度集合 `{1, 2, ..., 20}`
- WHEN 完成批量生成
- THEN 恰有 20 张 Open-Jam 表和 19 张 Call-Jam 表
- AND 1BB 只有 Open-Jam，2–20BB 各有 Open-Jam 与 Call-Jam
- AND 每张表标明对应的精确 `effectiveBigBlinds`
- AND 每张表的 NashConv 不超过同一份生成配置中声明的阈值

### Scenario: 未达到收敛阈值

- GIVEN 某深度的求解结果 NashConv 高于声明阈值
- WHEN 生成器准备写入规范化表
- THEN 该深度生成失败并报告实际 NashConv 和阈值
- AND 该批次不得被导入策略包
