# Capability: strategy-content-pipeline

## Requirement: 求解器输出导入

The system SHALL import solver output into versioned strategy packs such that every decision node in the input has a semantically equal counterpart in the output, and SHALL reject any input that does not satisfy the existing decision-node semantics.

### Scenario: 合法求解器导出导入

- GIVEN 一份含 N 个决策节点的求解器导出，每个节点带位置、街道、有效筹码、行动频率与 EV
- WHEN 导入工具生成策略包
- THEN 生成包的场景数等于 N
- AND 对导出中的每一条 (position, street, action, frequencyBasisPoints, ev)，生成包中存在字段逐一相等的 StrategyOption
- AND 生成的包通过 StrategyPackValidator 的全部语义校验
- AND manifest 记录 pack ID、schema version、content version、generatedSource 与导出时间
- AND 每个场景使用 tableSize 与 heroSeatOffsetFromButton 表示位置

### Scenario: 求解器导出不满足语义约束

- GIVEN 一份导出中某决策节点的行动频率总和不是 10,000 basis points
- WHEN 导入工具处理该导出
- THEN 导入以非零码失败并指明场景 ID 与实际频率总和
- AND 输出路径下不存在任何文件

### Scenario: 导入是确定性的

- GIVEN 同一份求解器导出
- WHEN 导入工具在两个独立进程中各运行一次，两次的工作目录、系统时钟与哈希种子均不同
- THEN 两次产出的策略包字节完全相同
- AND 其 SHA-256 等于仓库中签入的黄金 checksum

## Requirement: 内容升级黄金回归

The system SHALL run a golden-data regression on every content upgrade and SHALL report each scenario whose grading outcome moves beyond tolerance, as required by `docs/standards/strategy-content.md:35`.

### Scenario: 升级改变了评分结果

- GIVEN 黄金数据集中某场景在旧内容下的 lossRateBasisPoints 为 40，新内容下为 260
- WHEN 运行升级回归
- THEN 回归以非零码失败
- AND 报告列出该场景 ID、旧值 40、新值 260 与其跨越的 quality 边界（acceptable → improvable）

### Scenario: 升级在容差内

- GIVEN 黄金数据集中所有场景的 lossRateBasisPoints 变化都不超过容差且不跨越 quality 边界
- WHEN 运行升级回归
- THEN 回归以零码通过
- AND 报告仍逐条列出实际变化量，而不是只输出一个通过结论

## Requirement: 内容随包交付与可选更新

The system SHALL ship a bundled strategy pack that works with no network, and SHALL replace it only with a pack whose checksum verifies and whose content version is strictly higher.

### Scenario: 首次离线启动使用内置内容

- GIVEN 设备从未联网且从未拉取过内容
- WHEN 用户打开 APP
- THEN `StrategyContentAvailability` 为 `.reviewedContentAvailable`
- AND 当前 pack ID 等于随包内置的核心集 pack ID
- AND 从启动到可作答期间网络层记录 0 次请求

### Scenario: 校验通过且版本更高的更新包被采用

- GIVEN 本机当前内容版本为 `2026.08.06`，服务端提供 `2026.09.01` 的包且其 SHA-256 与声明一致
- WHEN 客户端评估并应用更新
- THEN 此后新生成的训练题的 content version 为 `2026.09.01`
- AND 既有训练事件记录的 content version 仍为 `2026.08.06`

### Scenario: 更新包 checksum 不匹配

- GIVEN 服务端提供 `2026.09.01` 的包但其 SHA-256 与声明不符
- WHEN 客户端校验下载内容
- THEN 拒绝该更新并返回 checksum-specific typed error
- AND 当前内容版本仍为 `2026.08.06`，训练不中断

### Scenario: 更新包内容版本等于当前

- GIVEN 本机当前内容版本为 `2026.08.06`，服务端提供的包也是 `2026.08.06`
- WHEN 客户端评估是否替换
- THEN 不替换

### Scenario: 更新包内容版本低于当前

- GIVEN 本机当前内容版本为 `2026.09.01`，服务端提供的是 `2026.08.06`
- WHEN 客户端评估是否替换
- THEN 不替换

## Requirement: 锦标赛求解器输出导入

The system SHALL extend solver-output import with tournament exact-depth,
ante-assumption, 169-hand completeness, convergence, and provenance validation,
while preserving deterministic output, atomic writes, semantic validation, and
golden regression behavior of the existing strategy content pipeline.

### Scenario: 同一批次确定性导入

- GIVEN 同一份锁定的 40 表输入、相同 manifest 和相同 content version
- WHEN 在两个独立进程中各导入一次
- THEN 两次生成的 20 个策略包逐包字节与 SHA-256 完全相同
- AND 不把系统时钟、临时路径或字典哈希顺序写入产物

### Scenario: 原子失败

- GIVEN 第 39 张表违反 bps 总和或来源哈希门禁
- WHEN 导入完整批次
- THEN 命令以非零码失败
- AND 最终输出目录不存在部分策略包或部分 checksum

## Requirement: 首批内容黄金回归基线

The system SHALL create a signed-in-repository golden baseline for all 20 packs
in the first unverified HU batch and SHALL require later content versions to
report all frequency and action-EV changes and fail on unapproved changes
beyond the configured tolerance.

### Scenario: 首次建立基线

- GIVEN 通过全部门禁的首批未审核策略包
- WHEN 建立黄金基线
- THEN 仓库记录 20 个策略包的 SHA-256、39 张表的输入哈希与关键覆盖统计
- AND 后续同版本重建得到相同字节
