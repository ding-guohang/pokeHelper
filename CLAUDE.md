# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Poker Coach（仓库名 `porkHelper`）：原生 iPhone/iPad 德州扑克决策训练 APP。M1A 是可离线运行的现金桌训练纵向切片，已实现并进入最终评审收口；M1B（独立账号与同步）和 M1C（自适应课程）尚未开始。技术栈：SwiftUI、Swift 6.2.3、Xcode 26.2、XcodeGen、Swift Package Manager，无第三方运行时依赖。

## Commands

生成 Xcode 工程（改动 `project.yml` 或 target 结构后必须重新生成）：

```bash
xcodegen generate
```

运行单个 Swift 包的测试：

```bash
swift test --package-path Packages/PokerCore
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/TrainingDomain
```

运行单个 App 测试（`xcodegen generate` 之后）：

```bash
xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachTests/DecisionSessionViewModelTests

xcodebuild test -project PokerCoach.xcodeproj -scheme PokerCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:PokerCoachUITests/CashCoachHappyPathTests
```

完整验证（三个包测试 + App 单测 + iPhone/iPad UI 测试 + Release 模拟器构建 + fixture 排除断言 + `git diff --check`，任何步骤失败返回非零）：

```bash
bash scripts/verify-m1a.sh
```

iPhone/iPad destination 可分别用 `M1A_IPHONE_DESTINATION` / `M1A_IPAD_DESTINATION` 环境变量覆盖；iPad 默认自动探测 `iPad Pro 13-inch (M4)`，不存在时回退到 `(M5)`，两者都没有则报错而不是跳过。

检查工程骨架（`project.yml`、xcconfig、Package.swift 中的告警即错误设置是否齐全）：

```bash
bash scripts/check-project-shape.sh
```

本地运行 Debug fixture：`xcodegen generate` → 用 Xcode 打开 `PokerCoach.xcodeproj` → 选择 `PokerCoach` scheme + Debug + 一个 iPhone/iPad Simulator → Run。Debug 自动加载 `PokerCoach/Resources/DevStrategyPack.json`（`--reset-training-events` launch argument 可清空本地训练事件）。这个 fixture 只是确定性演示数据，未经扑克策略审核；任何由它生成的界面必须显示"开发演示数据"，且不得进入 Release（`verify-m1a.sh` 会断言 Release 产物不含该资源）。

## Architecture

### 分层与依赖方向（严格单向，违反即 bug）

```
SwiftUI View
  ↓ 绑定
Feature ViewModel / Presentation   (PokerCoach/Features/<Feature>/)
  ↓ 调用
TrainingDomain                     (Packages/TrainingDomain/)
  ↓ 读取
StrategyContent                    (Packages/StrategyContent/)
  ↓ 使用
PokerCore                          (Packages/PokerCore/)
```

- **PokerCore**：牌、精确金额（`BBAmount`/`EVAmount`）、合法行动、`BettingDecisionContext`。不依赖仓库内任何其他模块，不含教学文案、网络、存储或用户状态。
- **StrategyContent**：加载不可变策略包（`StrategyPack`、`DecisionScenario`、`StrategyPackLoader`、`StrategyPackValidator`）。使用 PokerCore 的类型，负责解码/校验/版本追溯。每个决策节点的行动频率总和必须严格等于 10,000 basis points。
- **TrainingDomain**：`DecisionScorer`、`TrainingEvent`、`TrainingEventStore`（及 M1A 实现 `FileTrainingEventStore`，JSON Lines 追加式）、`PlayerModelReducer`、`TrainingPlanner`。可读 PokerCore 与 StrategyContent，禁止依赖 SwiftUI、HTTP 或数据库实现。评分逻辑不得读取后续发牌或本手输赢结果。
- **SwiftUI App**（`PokerCoach/`）：View 只管布局/交互/无业务含义的显示状态；ViewModel 组合领域协议，但不得自行计算 EV、合法行动或能力分数。跨 Feature 复用且无业务状态的组件放 `PokerCoach/Shared/`。

**禁止的依赖方向**：`PokerCore → StrategyContent`、`PokerCore → TrainingDomain`、任何领域包 → SwiftUI 或具体 HTTP 客户端、View → 文件系统/数据库/同步 DTO、生成式文本 → `DecisionScorer` 输入。远端 DTO（M1B 引入）必须在基础设施层转换为领域类型后才能进入 TrainingDomain。

### M1A → M1B 稳定契约

M1B（独立身份与同步）只能依赖以下类型且不得改变其语义，详见 `docs/architecture/m1a-module-boundaries.md`：

- `TrainingEvent`、`TrainingEventStore`、`FileTrainingEventStore`（`Packages/TrainingDomain/Sources/TrainingDomain/`）
- `StrategyPackManifest`（`Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift`）

`TrainingEventStore.allEvents()` 按 `occurredAt` 再按事件 UUID 稳定排序供 UI/归约使用；`events(after:)` 严格按 JSON Lines 追加顺序读取供增量同步使用 —— 即使设备时钟回拨，后追加事件仍必须出现在此前 checkpoint 之后。

位置表示（供 M3 锦标赛复用，见同一文档）：`SolverAssumptions.tableSize`（2–9 人）+ `DecisionScenario.heroSeatOffsetFromButton`（`0..<tableSize`，`0`=BTN 或 heads-up 的 BTN/SB，向后递推）。`StrategyPackValidator` 必须联合校验两者；新增场景不得引入自由文本位置或固定人数位置枚举。

### 精确数据规则

- 筹码/底池：整数 centi-BB。EV：整数 milli-BB。频率：basis points，节点内总和恒为 10,000。
- 浮点数只用于最终展示，绝不作为领域存储或比较的真值。
- 金额/频率/EV 的 JSON 字段名必须显式带单位。

### 策略内容规则

- `reviewStatus` 三态：`testFixture`（仅测试/演示，Release 禁用）、`reviewed`（Release 可用）、`retired`（历史保留，不用于新训练）。
- 已发布 pack 不可原地修改；新内容必须用新的 content version；`TrainingEvent` 永久记录生成时的 pack ID 与 content version。
- 生成式教练文本不得添加结构化数据（频率/EV/范围）中不存在的数字或结论。

## Testing

- Swift 包测试用 **Swift Testing**（`Packages/*/Tests/`），App 模型测试用 **XCTest**（`PokerCoachTests/`），端到端用 **XCUITest**（`PokerCoachUITests/`）。
- 每个测试使用固定 UUID、日期和发牌种子，不依赖执行顺序或全局状态。
- 测试专用 fixture 放对应目标的 `Support/`，不得成为生产 API 或进入 Release。
- 修复失败测试必须覆盖根因；不允许删除断言、放宽核心约束或只验证"不崩溃"来让测试通过。
- TDD 顺序：写失败测试 → 确认因缺失行为失败 → 最小实现 → 目标测试通过 → 跑受影响模块全部测试 → 提交。

## Conventions

- 类型/文件名 `UpperCamelCase`；变量/函数/属性 `lowerCamelCase`。
- Swift 严格并发检查；项目代码中的并发警告按错误处理。可跨 task 使用的领域类型必须显式 `Sendable`。
- 一个文件聚焦一个稳定职责；不按 Models/Views/Utils 横向堆积。
- 提交信息使用英文 Conventional Commits（`feat:`、`fix:`、`test:`、`docs:`）；每个 Harness task 形成可独立评审的小提交。
- 不提交 `.superpowers/` 工作区、派生数据、密钥或未脱敏牌谱；日志不得记录完整牌谱、认证头或密钥。

## Harness Workflow

本仓库使用 Harness 技能驱动的规格化工作流：`propose → review-proposal → plan → apply → review → archive`（对应 `/harness-propose`、`/harness-review-proposal`、`/harness-plan`、`/harness-apply`、`/harness-review`、`/harness-archive`；`/harness-workflow` 查看进行中 change，`/harness-knowledge` 检索/更新知识库）。任何代码变更意图应先经 `/harness-workflow` 分流，不要绕过它直接实现。

- `openspec/specs/`：当前生效的主规格（按能力域拆分：`cash-decision-domain`、`explainable-decision-training`、`local-learning-profile`、`versioned-strategy-content`、`adaptive-native-shell`、`m1a-release-safety`）。
- `openspec/changes/`：进行中和已归档（`archive/`）的变更记录。
- `docs/superpowers/specs/`：已批准的产品设计；`docs/superpowers/plans/`：实施路线和详细任务计划。
- `docs/architecture/`、`docs/standards/`、`docs/product/` 各自的 `index.md` 是对应知识域的入口。
