---
name: poker-coach-m1a-cash-coach-20260806-01
created: 2026-08-06
status: archived
archived: 2026-08-07T09:52:31+08:00
---

# 需求提案：M1A 现金局教练纵向切片

## Why

产品需要先用一个可运行、可验证的纵向切片证明核心价值：用户能在 iPhone/iPad 完成一手 6-max 100BB 现金局决策，获得可信的专业反馈，并让该决策真实改变后续训练与复盘。这个切片同时建立后续账号同步、课程、模拟牌局和锦标赛可以复用的领域契约。

## What Changes

### New Capabilities

- `adaptive-native-shell` — 提供 iPhone/iPad 原生四入口框架和自适应导航。
- `cash-decision-domain` — 提供精确金额、牌、合法行动和静态现金局决策上下文。
- `versioned-strategy-content` — 加载并校验带来源、版本和审核状态的不可变策略包。
- `explainable-decision-training` — 接收行动与信心，依据 EV 损失生成专业且非结果导向的反馈。
- `local-learning-profile` — 本地持久化不可变训练事件，生成能力画像和今日训练优先级。
- `m1a-release-safety` — 隔离开发策略数据并提供 iPhone/iPad 一键验证。

### Modified Capabilities

无。`openspec/specs/` 当前没有已归档能力。

### Removed Capabilities

无。

## Capabilities Detail

### Capability: adaptive-native-shell

#### Requirement: 四个核心入口

The system SHALL provide the primary destinations 今日、学习、训练、复盘 in Simplified Chinese.

##### Scenario: iPhone 紧凑导航

- GIVEN 用户在 iPhone 或紧凑宽度窗口启动 APP
- WHEN 根界面完成加载
- THEN 系统显示包含今日、学习、训练、复盘的底部导航
- AND 训练入口使用黑桃标识

##### Scenario: iPad 多栏导航

- GIVEN 用户在 iPad 常规宽度窗口启动 APP
- WHEN 根界面完成加载
- THEN 系统使用侧边栏呈现四个核心入口
- AND 选择入口不会创建第二套领域状态

#### Requirement: 原生平台支持

The system SHALL build for iOS 18.0 and iPadOS 18.0 with Swift strict concurrency enabled.

##### Scenario: 两种设备构建

- GIVEN 已生成 Xcode 工程
- WHEN 分别执行通用 iOS Simulator 与通用 iOS 构建
- THEN 两个构建均成功
- AND 项目自有代码没有严格并发警告

### Capability: cash-decision-domain

#### Requirement: 精确扑克值

The system SHALL represent pot and stack amounts as integer centi-big-blinds, EV as integer milli-big-blinds, and strategy frequencies as integer basis points.

##### Scenario: 精确金额运算

- GIVEN 两个可相加的 centi-BB 金额和两个可相减的 milli-BB EV
- WHEN 领域层执行运算
- THEN 结果使用整数精确计算
- AND 领域真值不依赖浮点数比较

#### Requirement: 稳定牌面表示

The system SHALL parse and serialize a card using a stable two-character rank/suit code.

##### Scenario: 合法牌往返

- GIVEN 输入 `As`
- WHEN 系统解析后重新序列化
- THEN 结果仍为 `As`
- AND 点数为 Ace、花色为 Spades

##### Scenario: 非法牌拒绝

- GIVEN 输入 `1x`
- WHEN 系统尝试解析
- THEN 解析失败
- AND 不产生部分 Card 值

#### Requirement: 合法行动过滤

The system SHALL derive the available fold, check, call, bet, raise, and all-in actions from a stored betting decision context.

##### Scenario: 未面对下注

- GIVEN amount-to-call 为零，配置了两个低于有效筹码的下注尺度
- WHEN 系统计算合法行动
- THEN 包含 check、两个 bet 和 all-in
- AND 不包含 fold、call 或 raise

##### Scenario: 面对下注

- GIVEN amount-to-call 大于零并存在 minimum-raise-to
- WHEN 系统计算合法行动
- THEN 包含 fold、call、达到最小加注要求的 raise 和 all-in
- AND 低于 minimum-raise-to 的配置尺度被排除

#### Requirement: 稳定行动 JSON

The system SHALL encode decision actions with an explicit action kind and unit-bearing target amount.

##### Scenario: 带金额行动

- GIVEN 行动是 bet 到 2.17BB
- WHEN 系统编码 JSON
- THEN JSON kind 为 `bet`
- AND `toCentiBB` 为 `217`

##### Scenario: 行动字段不匹配

- GIVEN fold/check 包含金额或 bet/raise 缺少金额
- WHEN 系统解码
- THEN 解码失败并返回 typed error

### Capability: versioned-strategy-content

#### Requirement: 策略包来源可追溯

The system SHALL load strategy packs that identify schema version, content version, review status, generated source, game assumptions, and decision scenarios.

##### Scenario: 合法策略包加载

- GIVEN 策略包 schema version 为 1、来源非空且场景完整
- WHEN loader 完成 checksum、解码和语义校验
- THEN 返回不可变 StrategyPack
- AND manifest 与场景中的求解假设可供反馈界面读取
- AND 场景使用 tableSize 与 heroSeatOffsetFromButton 表示可验证的 2–9 人桌位置

##### Scenario: checksum 不匹配

- GIVEN 下载内容的 SHA-256 与期望值不同
- WHEN loader 加载策略包
- THEN 在解码前拒绝内容
- AND 返回 checksum-specific typed error

#### Requirement: 决策节点语义校验

The system SHALL reject a strategy decision node that violates card uniqueness, legal-action, action uniqueness, or frequency-total rules.

##### Scenario: 频率总和错误

- GIVEN 一个场景的行动频率总和不是 10,000 basis points
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 错误包含场景 ID 和实际频率总和

##### Scenario: 非法行动进入策略

- GIVEN 策略选项包含 BettingDecisionContext 未提供的行动
- WHEN validator 校验
- THEN 策略包被拒绝
- AND 该内容不能进入训练流程

#### Requirement: 审核状态约束

The system SHALL distinguish `testFixture`, `reviewed`, and `retired` strategy content.

##### Scenario: 已审核内容缺少审核时间

- GIVEN review status 为 `reviewed` 且 reviewed-at 为空
- WHEN validator 校验
- THEN 策略包被拒绝

##### Scenario: 开发内容展示

- GIVEN APP 使用 `testFixture` 内容
- WHEN 用户查看训练或反馈
- THEN 界面明确显示“开发演示数据”
- AND 不把数据描述为已审核扑克建议

### Capability: explainable-decision-training

#### Requirement: 行动与信心共同提交

The system SHALL require both a legal action and one of guessing、unsure、very-sure confidence values before grading.

##### Scenario: 提交信息不完整

- GIVEN 用户未选择行动或信心
- WHEN 用户尝试提交
- THEN 系统不创建 TrainingEvent
- AND 显示中文提示“请选择行动和信心程度”

##### Scenario: 合法提交

- GIVEN 用户选择策略节点中的合法行动和信心
- WHEN 提交成功
- THEN 系统只执行一次确定性评分
- AND 在展示反馈前持久化一条 TrainingEvent

#### Requirement: 可解释 EV 评分

The system SHALL grade a selected action using its raw EV loss relative to the best listed action and the decision pot size.

##### Scenario: 最高 EV 行动

- GIVEN 用户选择最高 EV 行动
- WHEN 系统评分
- THEN EV loss 为 0 milliBB
- AND score 为 100
- AND quality 为 excellent

##### Scenario: 接近 EV 的混合行动

- GIVEN 用户选择频率大于零且只损失 20 milliBB 的第二行动
- WHEN 系统评分
- THEN 系统保留该行动的原始频率和 EV
- AND quality 为 acceptable
- AND 不把它描述为错误答案

##### Scenario: 策略节点外行动

- GIVEN 用户提交的行动不在该节点的策略选项中
- WHEN 系统评分
- THEN 评分失败并返回 `actionNotInStrategy`
- AND 不生成伪造频率或 EV

#### Requirement: 评分与结果无关

The system SHALL produce a decision grade without consuming later runout, pot result, or winnings.

##### Scenario: 相同决策不同后续结果

- GIVEN 两次训练具有相同场景、行动和策略版本，但模拟后续结果不同
- WHEN 系统生成 DecisionGrade
- THEN 两次 grade 完全相同

#### Requirement: 专业反馈层级

The system SHALL show quality, raw EV loss, confidence calibration, all action frequencies, range information, structured reasoning, solver assumptions, source, version, and review status.

##### Scenario: iPhone 专业反馈

- GIVEN 用户在 iPhone 完成决策
- WHEN 反馈页面出现
- THEN 信息以单列可滚动层级显示
- AND 所有可用行动及其频率仍可查看

##### Scenario: iPad 专业反馈

- GIVEN 用户在 iPad 完成决策
- WHEN 反馈页面出现
- THEN 牌桌列与分析列同时可见
- AND 两列使用同一个 DecisionGrade

##### Scenario: 剥削条件缺失

- GIVEN 结构化内容没有 exploit condition
- WHEN 系统展示反馈
- THEN 不展示无依据的剥削建议

### Capability: local-learning-profile

#### Requirement: 不可变本地训练事件

The system SHALL persist each completed decision as an immutable, append-only event that includes event ID, local user ID, device ID, occurrence time, scenario ID, strategy pack ID, content version, ability dimension, submission, and grade.

##### Scenario: 首次追加

- GIVEN 本地事件存储为空
- WHEN APP 追加一个 TrainingEvent
- THEN 事件可按时间顺序读取
- AND 所有同步所需标识与评分字段均保留

##### Scenario: 重复事件

- GIVEN 存储中已经存在相同 event ID
- WHEN APP 再次追加该事件
- THEN 存储内容不重复
- AND 读取结果仍只有一条该事件

##### Scenario: 损坏事件文件

- GIVEN JSON Lines 文件的某一行无法解码
- WHEN store 初始化或读取
- THEN 返回包含行号的 typed corruption error
- AND 日志不输出完整事件正文

#### Requirement: 能力画像归约

The system SHALL derive each ability dimension from its immutable training events.

##### Scenario: 高信心错误

- GIVEN very-sure 决策被评为 improvable 或 blunder
- WHEN reducer 生成能力画像
- THEN 对应维度 high-confidence-error-count 增加
- AND 其他能力维度不受影响

#### Requirement: 今日训练优先级

The system SHALL rank training catalog items using weakness, high-confidence errors, and days since practice.

##### Scenario: 高信心弱项优先

- GIVEN bet-sizing 分数较低且有高信心错误，preflop-range 分数较高
- WHEN planner 生成三个今日项目
- THEN bet-sizing 项目排在第一位
- AND 排序在相同输入下保持稳定

#### Requirement: 今日与复盘使用真实历史

The system SHALL update Today and Review from the local event store after a completed decision.

##### Scenario: 决策完成后刷新

- GIVEN 用户完成一个 bet-sizing 场景
- WHEN 返回今日或进入复盘
- THEN 页面样本量和能力信息反映该事件
- AND 今日主训练可以指向该弱项

### Capability: m1a-release-safety

#### Requirement: 开发策略数据隔离

The system SHALL include the deterministic development strategy pack in Debug only and exclude it from Release resources.

##### Scenario: Debug 训练

- GIVEN APP 使用 Debug 配置启动
- WHEN 开发策略场景被加载
- THEN 用户可以完成纵向训练流程
- AND 所有相关页面显示“开发演示数据”

##### Scenario: Release 构建

- GIVEN APP 使用 Release 配置构建
- WHEN 检查生成的 APP bundle
- THEN `DevStrategyPack.json` 不存在
- AND 缺少已审核内容时显示“未安装已审核策略内容”

#### Requirement: 一键验证

The system SHALL provide one command that verifies packages, app models, iPhone flow, iPad layout, and Release fixture exclusion.

##### Scenario: 从干净检出验证

- GIVEN 机器安装已批准版本的 Xcode、Swift 和 XcodeGen
- WHEN 执行 `bash scripts/verify-m1a.sh`
- THEN PokerCore、StrategyContent 和 TrainingDomain 测试通过
- AND APP 单元测试通过
- AND iPhone 与 iPad UI 测试通过

## Impact

- **Code:** 新增 `project.yml`、`Config/`、`Packages/PokerCore/`、`Packages/StrategyContent/`、`Packages/TrainingDomain/`、`PokerCoach/`、`PokerCoachTests/`、`PokerCoachUITests/` 和验证脚本。
- **Interfaces:** 新增四入口 SwiftUI 导航、现金局决策与专业反馈 UI；新增 `DecisionAction`、`DecisionScenario`、`DecisionScorer`、`TrainingEventStore` 等内部稳定契约。
- **Dependencies:** 使用现有 Xcode 26.2、Swift 6.2.3、XcodeGen 和 Apple 测试框架；M1A 不新增第三方运行时依赖。
- **Knowledge:** 遵循 `docs/architecture/` 分层、`docs/standards/` 编码/测试/策略内容规范和 `docs/product/` 学习规则。

## Risks

- 策略 fixture 被误认为真实扑克建议 → Debug 全链路标记“开发演示数据”，Release 排除资源。
- 浮点数或不稳定 JSON 破坏领域一致性 → 金额、EV、频率使用带单位整数并定义稳定行动 JSON。
- UI 绕过领域校验 → ViewModel 只展示 PokerCore 合法行动，评分只接受 StrategyContent 选项。
- 混合策略被简化为唯一答案 → 保存全部频率和 EV，接近 EV 的行动保持 acceptable。
- 本地事件损坏或重复 → 原子写入、事件 ID 幂等和行号错误测试。
- M1A 范围扩张到同步或完整课程 → Non-Goals 明确切分到 M1B/M1C。
- 模拟器或 Release 资源验证被遗漏 → 一键验证同时覆盖 iPhone、iPad 和 Release bundle。

## Non-Goals

- Apple/邮箱登录、独立 Go API、PostgreSQL 和跨设备同步；属于 M1B。
- 完整初始诊断、已审核现金局课程包和间隔复练内容运营；属于 M1C。
- 完整发牌、虚拟对手和 15/30/60 手现金局 Session；属于 M2A。
- 文本牌谱导入、场景构建和分支重放；属于 M2B。
- Ante、短码、Push/Fold、Rejam、赛事路线和 ICM；属于 M3。
- 订阅、权益、试用、分析和 App Store 上架；属于 M4。
- 真钱游戏、俱乐部、现金对战、社交动态、排行榜或第三方牌桌实时连接。
- 在 M1A Release 中发布未经扑克策略审核的生产内容。

## Acceptance Criteria

1. iPhone 使用四项 Tab 导航，iPad 使用四项侧边栏导航，并共享领域状态。
2. PokerCore 对牌、centi-BB、milli-BB 和合法行动的测试全部通过。
3. StrategyContent 拒绝 checksum、频率、重复牌、重复行动、非法行动和审核元数据错误。
4. DecisionScorer 保留原始 EV、频率和混合策略，且不读取 runout 或输赢。
5. 用户未同时选择行动与信心前不能提交；合法提交只产生一条训练事件。
6. 专业反馈在 iPhone/iPad 显示 EV 损失、全部行动频率、范围、推理、假设、来源和内容版本。
7. TrainingEvent 包含同步所需标识并按 event ID 幂等持久化。
8. 能力画像和今日计划会在决策后从真实本地事件更新。
9. Debug fixture 全链路显示“开发演示数据”，Release bundle 不包含该文件。
10. `bash scripts/verify-m1a.sh` 从干净检出完成包测试、APP 测试、iPhone/iPad UI 测试和 Release 验证。
11. 实现保持 `PokerCore ← StrategyContent ← TrainingDomain ← SwiftUI` 的允许依赖方向，网络和数据库 DTO 不进入领域包。
12. M1A 通过逐任务规格符合性与代码质量评审后方可标记完成。
