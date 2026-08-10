# Capability: m1a-release-safety

## Requirement: 开发策略数据隔离

The system SHALL recognize three build classes — Debug, dogfooding, and store release — SHALL include the deterministic development strategy pack in Debug only, and SHALL admit content to each class by review status: `testFixture` in Debug, `unverifiedDraft` and `reviewed` in dogfooding, `reviewed` only in a store release.

### Scenario: Debug 训练

- GIVEN APP 使用 Debug 配置启动
- WHEN 开发策略场景被加载
- THEN 用户可以完成纵向训练流程
- AND 所有相关页面显示“开发演示数据”

### Scenario: Release 构建

- GIVEN APP 使用 Release 配置构建
- WHEN 检查生成的 APP bundle
- THEN `DevStrategyPack.json` 不存在
- AND 缺少已审核内容时显示“未安装已审核策略内容”

### Scenario: dogfooding 构建携带未审核内容

- GIVEN 一个 dogfooding 构建，随包内容含 `unverifiedDraft` 与 `reviewed` 两种
- WHEN 运行发布门禁
- THEN 门禁以 0 退出
- AND 训练可以开始
- AND 由 `unverifiedDraft` 内容生成的界面显示“未经策略审核”

### Scenario: 商店发布拒绝未审核内容

- GIVEN 一个商店发布构建，随包内容含至少一个 `unverifiedDraft` 包
- WHEN 运行发布门禁
- THEN 门禁以非零码失败
- AND 失败信息列出违规包的 pack ID 与其 review status

### Scenario: 商店发布接受已审核内容

- GIVEN 一个商店发布构建，随包内容全部为 `reviewed` 且各自具备 reviewed-by 与 reviewed-at
- WHEN 运行发布门禁
- THEN 门禁以 0 退出
- AND `StrategyContentAvailability` 为 `.reviewedContentAvailable`

## Requirement: 一键验证

The system SHALL provide one command that verifies packages, app models, iPhone flow, iPad layout, and Release fixture exclusion.

### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift 和 XcodeGen
- WHEN 执行 `bash scripts/verify-m1a.sh`
- THEN PokerCore、StrategyContent 和 TrainingDomain 测试通过
- AND APP 单元测试通过
- AND iPhone 与 iPad UI 测试通过

## 设计阶段需决断的点

以下问题影响架构，留给 `/harness-plan`：

1. **三种构建类别如何在 `Config/` 中落地。** 今天只有 `Debug.xcconfig` 与 `Release.xcconfig`，而 `scripts/check-m1b-release-secrets.sh:46-54` 硬编码了两配置假设。是新增第三套 xcconfig，还是用一个编译条件区分 dogfooding 与商店发布，决定了门禁的判定依据。
2. **复练调度状态存放位置。** `nextDueAt` 与 `intervalDays` 必须可读（见 spaced-repetition 的要求），但可以从事件历史确定性推导，也可以单独持久化。前者与「画像由完整事件确定性归约」一致且天然跨设备一致；后者更快，但要纳入同步与档案隔离。
3. **内容更新端点是否在本次启用。** `strategy-content-pipeline` 的客户端校验行为已经定义，服务端下发端点是否落在 M1C 范围内需要明确；若推迟，该能力的交付边界止于随包内置与本地校验。

## Impact

- **Code:**
  - `Packages/StrategyContent/` — `ReviewStatus` 增加 `unverifiedDraft`；manifest 增加 `reviewedBy`；校验与解码扩展
  - `Packages/TrainingDomain/` — 能力树节点掌握判定、复练调度、`TrainingPlanner` 优先级扩展与裁决顺序
  - 新增内容导入工具（求解器输出 → 策略包）与黄金回归
  - `PokerCoach/App/StrategyContentMetadata.swift` — `StrategyContentAvailability` 与全部披露文案
  - `PokerCoach/Features/Learn/` — 能力树界面（今天只有一个硬编码静态列表）
  - `PokerCoach/Features/Today/` — 诊断入口与计划原因展示
  - `PokerCoach/Features/Train/`、`Feedback/`、`Review/` — `unverifiedDraft` 披露与历史内容版本展示
  - `PokerCoach/Infrastructure/` — 内容更新的 HTTP 获取（不放进领域包）
  - `PokerCoach/App/AppDependencies.swift` — 首次走通 `reviewedContentAvailable`
  - `Config/` 与 `scripts/check-m1b-release-secrets.sh` — 第三种构建类别与内容审核状态门禁
  - `PokerCoach/Resources/` 与 `project.yml` — 随包内置内容的资源条目
  - `Server/` — 可选内容分发端点（若启用更新通道）
- **Docs:** `docs/standards/strategy-content.md` 的审核状态表需增加 `unverifiedDraft` 行，并把「Release 可用」一列拆为「dogfooding 可用」与「商店发布可用」；必需元数据增加 `reviewedBy`；展示规则增加 `unverifiedDraft`。`docs/architecture/components.md:40` 把「内容分发」列为 M1B 已实现，与 `Server/internal/` 的实际内容不符，应一并订正。
- **Interfaces:** 新增内容包更新的 HTTPS 端点（若启用）；能力树与诊断为新增 UI 入口；导入工具为本地开发工具，不对外暴露。
- **Dependencies:** 无新增运行时依赖。`Contracts/training-event-upload-v1.json` 不变——见「已确定的设计约束」第 1 条。

## Risks

- **生成内容被误当作已审核策略** → 核心集由所有者逐表审核并记录 `reviewedBy`/`reviewedAt`；其余标 `unverifiedDraft` 并强制界面披露；商店发布门禁拒绝非 `reviewed` 内容。
- **掌握判定退化为恒假实现** → 五项信号各有独立的否定场景，另有一条五项齐备的正向场景断言 mastered；否则整个特性可以用 `false` 通过。
- **能力树节点与内容覆盖不匹配，导致节点永远无法掌握** → 无内容的节点显式标记并排除出计划与进度分母。
- **复练在小内容集下退化为重复同一题** → 明确「同类非同题」，内容不足时挂起该维度复练。
- **复现间隔无下限导致同一题在同一会话反复出现** → 阶梯与下限写入要求，答错退级不低于一天。
- **内容升级悄悄改变历史评分** → 升级必须运行黄金回归并逐条报告变化量。
- **导入工具产出不确定导致 checksum 漂移** → 要求跨进程、异工作目录、异哈希种子两次导入字节相同并等于签入的黄金 checksum。
- **改动事件契约会破坏跨语言字节冻结文件** → 节点归属从内容派生，事件契约不变。

## Non-Goals

- 不做锦标赛能力树、短码、Ante、ICM（属于 M3）。
- 不做连续牌局模拟与虚拟对手（属于 M2A）。
- 不做牌谱导入与场景构建（属于 M2B）。
- 不做订阅、权益与实际上架动作（属于 M4）；本次只交付发布门禁本身。
- 不由我单方面把生成内容标为 `reviewed`；`reviewed` 一律需要人工审核签字。
- 不做生成式教练文案；教练文本仍只组织已有结构化分析。

## Acceptance Criteria

1. 商店发布构建随包内置经审核签字的核心集内容，首次离线启动即可训练。内容来源与审核状态分开记录：模型产出的策略即便已人工审核也始终披露来源，`reviewedContentAvailable` 保留给求解器产出的内容。
2. 求解器导出可经导入工具产出通过全部语义校验的策略包；输出与输入逐条对应；跨进程两次导入字节相同并等于签入的黄金 checksum。
3. 内容升级运行黄金回归；跨越 quality 边界的变化使回归失败并逐条报告。
4. 初始诊断 12 题可完成、可跳过、可中断后继续；跳过后今日计划仍非空且维度均衡。
5. 学习页显示现金局能力树，节点归属由内容派生；无内容的节点显式标记且不计入进度分母。
6. 节点掌握需五项信号同时满足，且存在一条断言 mastered 的正向测试；五项各有独立的否定测试。
7. 复练出题与上次答错的场景不同；上次答对的维度不出现复练项；内容不足时该维度复练挂起。
8. 复现间隔按 1/3/7/14/30 阶梯前进与退级，下限为 1 天，`intervalDays` 与 `nextDueAt` 可读。
9. 任何由 `unverifiedDraft` 内容生成的界面都显示「未经策略审核」，且该文案与「开发演示数据」不同。
10. 发布门禁：商店发布构建在存在 `testFixture` 或 `unverifiedDraft` 内容时失败、在内容全为 `reviewed` 时通过；dogfooding 构建携带 `unverifiedDraft` 时通过。
11. 内容升级后，既有训练事件记录的 pack ID 与 content version 不被改写，复盘仍显示当时的内容版本。
12. `Contracts/training-event-upload-v1.sha256` 未变更。
13. `bash scripts/verify-m1a.sh` 与 `bash scripts/verify-m1b.sh` 仍然通过。
14. `bash scripts/check-proposal-completeness.sh curriculum-m1c-adaptive-cash-20260810-01` 通过。
