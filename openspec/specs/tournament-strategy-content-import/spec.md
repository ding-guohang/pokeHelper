# Capability: tournament-strategy-content-import

## Requirement: 导入完整且假设一致的 HU Push/Fold 批次

The system SHALL import only a complete 1–20BB HU no-ante chipEV batch whose
tables and manifests agree on table size, positions, facing state, exact
effective depth, blind structure, ante, equilibrium, source, and content
version, and SHALL produce one immutable strategy pack per exact integer depth
so the existing pack-level `effectiveStack` remains truthful.

### Scenario: 合法批次导入

- GIVEN 39 张通过来源、完整性、bps 与收敛门禁的规范化表
- WHEN 执行锦标赛策略导入
- THEN 产生 20 个 pack ID 含精确深度的内容包
- AND 1BB 包仅有 SB Open-Jam；2–20BB 每包恰有 SB Open-Jam 与 BB Call-Jam
- AND Open-Jam 使用 `tableSize=2`、`heroSeatOffsetFromButton=0`、`facing=unopened`
- AND Call-Jam 使用 `tableSize=2`、`heroSeatOffsetFromButton=1`、`facing=singleRaise`
- AND 求解假设可读取精确深度、`hasAnte=false` 与明确的无 ante 描述
- AND 每个 hand class 的每个合法行动均可读取 milli-BB EV
- AND 输出策略包通过 `StrategyPackValidator`

### Scenario: 批次缺少一张表

- GIVEN 批次缺少 7BB Call-Jam 表但其余 38 张表均合法
- WHEN 执行导入
- THEN 导入以非零码失败并指出缺少 7BB Call-Jam
- AND 不产生策略包或 checksum

### Scenario: 表含缺失、重复或非法手牌

- GIVEN 某表缺少 `72o`、重复 `AA`，或含非 canonical hand class
- WHEN 执行导入
- THEN 导入以非零码失败并指出文件和具体 hand class 问题
- AND 不产生策略包或 checksum

## Requirement: 未经人工审核不得晋升

The system SHALL mark freshly generated solver content as `origin=solver` and
`reviewStatus=unverifiedDraft`, SHALL preserve source truth independently from
review state, and SHALL require an explicit later human-review operation with
reviewer identity, review timestamp, a new content version, and recorded
comparison evidence before producing `reviewed` content.

### Scenario: 首次导入保持未审核

- GIVEN 合法且达到收敛阈值的开源 solver 批次
- WHEN 运行首批自动导入
- THEN manifest 为 `origin=solver` 与 `reviewStatus=unverifiedDraft`
- AND `generatedSource` 包含仓库、commit、生成配置和批次哈希
- AND 自动化命令不存在将本批次直接标成 `reviewed` 的参数路径

### Scenario: 缺少人工签署时请求 reviewed

- GIVEN 内容未经具名策略审核，或缺少审核时间与比对记录
- WHEN 请求产出 `reviewed` 锦标赛内容
- THEN 操作失败并明确列出缺失审核材料
- AND 原 `unverifiedDraft` 内容保持不变

## Requirement: 商业平台手工导出走隔离入口

The system SHALL accept a user-supplied PioSolver/GTO+ range text or documented
export file through a local conversion entry point, SHALL never fetch such
content from the commercial platform, SHALL record the platform and
user-supplied provenance, and SHALL subject converted data to the same 169-hand,
bps, assumption, review, and license-evidence gates.

### Scenario: 用户提供合法导出

- GIVEN 用户本地提供一份商业平台允许其导出的范围文件及使用授权说明
- WHEN 运行本地转换
- THEN 转换器不访问外部网络
- AND 输出记录来源平台、用户提供的原文件 SHA-256 与授权说明引用
- AND 输出仍为 `unverifiedDraft`，除非另行完成具名人工审核

### Scenario: 请求自动抓取商业平台

- GIVEN 没有平台提供的再利用授权或官方自动化 API 授权
- WHEN 请求转换器直接登录、抓取或遍历商业平台解算库
- THEN 工具拒绝执行该网络操作
- AND 提示改用用户手工合法导出的本地文件
