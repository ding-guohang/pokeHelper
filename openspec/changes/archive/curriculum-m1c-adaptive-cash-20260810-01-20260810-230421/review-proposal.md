# 审需报告：curriculum-m1c-adaptive-cash-20260810-01

日期：2026-08-10
方式：三个并行 agent（规格一致性 / 场景可测试性 / 架构与文档对齐）+ 机械结构检查

## 结论

**有条件通过 → 已修复后通过。** 首轮提案存在 3 类 CRITICAL 缺陷，均已在本轮修复并有机械门禁兜底。

## 首轮发现与处置

### CRITICAL 1 — Modified Capability 静默删除既有行为

归档时 proposal 的 Requirement 块**整块替换**主 spec。首轮我凭印象重写了两个 Modified Capability，导致以下已上线且被测试覆盖的行为将被删除：

| 丢失项 | 出处 | 后果 |
|---|---|---|
| Scenario `开发内容展示` | `versioned-strategy-content/spec.md:50` | `testFixture` 内容不再需要标注「开发演示数据」，而 `m1a-release-safety:12` 仍要求该标注 → 规格库自相矛盾 |
| Requirement `跨设备历史确定性归约` | `local-learning-profile/spec.md:61` | 被降级为 Scenario，丢掉「去重并集」的 SHALL 约束——这是 M1B 对该能力的全部贡献 |
| Scenario `远端事件进入画像` | `local-learning-profile/spec.md:65` | 丢掉「相同 event ID 重复拉取不改变结果」这条画像层幂等断言 |
| Scenario `已审核内容缺少审核时间` | `versioned-strategy-content/spec.md:44` | 被改名替换 |
| `高信心错误` 的「其他能力维度不受影响」 | `local-learning-profile/spec.md:37` | 维度隔离断言在全库无第二处 |
| `高信心弱项优先` 的「排序在相同输入下保持稳定」 | `local-learning-profile/spec.md:48` | 计划排序确定性 |
| `决策完成后刷新` 的「页面样本量…」「今日主训练可以指向该弱项」 | `local-learning-profile/spec.md:58-59` | 被换成模糊表述 |
| `损坏事件文件` 的 JSON Lines、`store 初始化`触发、`typed corruption error` | `local-learning-profile/spec.md:21-26` | JSON Lines 是 `m1a-module-boundaries.md:10-11` 定义 checkpoint 顺序的载重契约 |

**处置：** 两个能力从现有 spec 原文出发重建，新要求追加其后。新增
`scripts/check-proposal-completeness.sh` 做机械校验——按 (种类, 名字) 配对比对，
第一版只比名字，放过了「Requirement 降级为 Scenario」那条，正是让该缺陷肉眼不可见的
同一个盲点。已用修复前的提案做反例验证：报出全部 4 条。

### CRITICAL 2 — 验收条件自相矛盾，提案不可满足

三条同时成立不可能：

- Non-Goal：本次不产出 `reviewed` 内容
- 发布门禁：只有 `reviewed` 能随包发布
- AC 1：Release 必须内置内容并真实构造 `reviewedContentAvailable`

且 `docs/product/scope-and-milestones.md:26` 把「已审核内容」明确划给 M1C，而
`docs/standards/index.md` 规定已批准的产品设计优先于变更提案——单靠 Non-Goal 无法绕过。

**处置（用户决策）：** 内容分两档。核心集（6-max 100BB 翻前 RFI/3bet，公开成熟策略）
由仓库所有者逐表审核签字 → `reviewed`，manifest 记 `reviewedBy`/`reviewedAt`；
其余标 `unverifiedDraft` 并强制界面披露。M1C 因此能真正交付里程碑定义的「已审核内容」，
产品文档不需要修改。

### CRITICAL 3 — 新能力的场景清一色是负向的，空实现全绿

首轮 43 个场景中 19 个「弱」、5 个「不可测」。最要命的一条：

> 掌握判定只有否定场景，唯一一条正向场景（陌生场景迁移）的 GIVEN 含四个全书未定义的
> 术语，不可构造。因此 `isMastered` 恒返回 `false` 可以通过全部掌握相关场景——
> 而掌握判定正是 M1C 的产品命题本身。

同类空洞还有：更新通道只有拒绝路径没有采纳路径（`apply() { return }` 全通过）；
发布门禁只有失败路径没有通过路径（「一律 exit 1」全通过）；导入工具没有任何
「输出对应输入」的断言（返回硬编码常量包全通过）。

**处置：**

- 五项掌握信号全部量化写进 Requirement（样本 20；最近 10 次 ≥9 达标；最近 10 次内
  所有 `verySure` 作答达标；≥2 次到期复练均答对；3 个未作答过的 scenario ID 均达标），
  复用代码中已有的 `DecisionQuality` / `DecisionConfidence` 枚举与
  `PlayerModel.swift:80` 的高信心错误定义，不另造阈值。
- 新增「五项信号齐备时判定掌握」正向场景，五项各配独立否定场景。
- 补齐更新通道、发布门禁、黄金回归的正向路径。
- 导入工具补 N 对 N 的逐条对应断言与跨进程确定性（异工作目录、异时钟、异哈希种子）。
- 复现间隔改为显式阶梯 1/3/7/14/30，答错退级且下限 1 天，`intervalDays`/`nextDueAt` 可读。
- 诊断固定 12 题并声明蓝图，「收敛」换成可观测代理。

### IMPORTANT — 其余已处置项

| 问题 | 处置 |
|---|---|
| Why 中「`live()` 走 unavailable 分支」在 Debug 下不成立 | 改写为 Release 限定，并点明 Debug 靠 `developmentFixtureAvailable` 可跑 |
| `strategy-content.md:35` 的黄金回归强制要求被提案静默丢弃 | 新增「内容升级黄金回归」Requirement |
| 发布门禁散落三个 spec；M1A 只认识两种配置 | 用户决策：并入 `m1a-release-safety`，构建类别扩为三种 |
| 设计点「事件语义不得改变」误读 boundaries 文档 | 该条款 `:5` 限定写给 M1B；且已确定节点归属从内容派生，事件契约本就无需改动 |
| 改事件字段会破坏 `Contracts/` 字节冻结文件 | 同上；新增 AC 12 断言 `.sha256` 未变更 |
| 四个能力都改今日计划优先级，无裁决顺序 | Requirement 显式声明裁决顺序，并新增「高信心错误压过复练到期」场景 |
| pipeline 与 versioned-strategy-content 重复校验规则 | pipeline 侧改为断言导入产物通过既有 validator，不复述规则 |
| Impact 遗漏 `StrategyContentMetadata.swift`、Train/Feedback/Review、`Config/`、`project.yml` | 已补 |
| `components.md:40` 谎称 M1B 已实现内容分发 | 记入 Impact 的 Docs 段待订正 |

## 规格完整性

| Capability | Requirements | Scenarios |
|---|---|---|
| strategy-content-pipeline | 3 | 10 |
| initial-diagnostic | 1 | 3 |
| adaptive-curriculum | 3 | 11 |
| spaced-repetition | 2 | 5 |
| versioned-strategy-content（改） | 4 | 10 |
| local-learning-profile（改） | 6 | 13 |
| m1a-release-safety（改） | 2 | 6 |
| **合计** | **21** | **58** |

机械检查：无 0 场景的 Requirement；无缺 GIVEN/WHEN/THEN 的场景；无占位符；
`check-proposal-completeness.sh` 通过。

## 遗留

两条场景的 GIVEN 依赖设计阶段第 1 项（三种构建类别的落地方式）才能构造为测试：
`商店发布拒绝未审核内容`、`dogfooding 构建携带未审核内容`。这是显式依赖，不是缺陷，
`/harness-plan` 关闭该设计点后即可实现。
