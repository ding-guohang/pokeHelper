# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Poker Coach（仓库名 `porkHelper`）：原生 iPhone/iPad 德州扑克决策训练 APP。已实现并归档的切片：

- **M1A** 可离线运行的现金桌训练纵向切片；**M1B** 独立账号、设备会话与跨设备事件同步（Go + MySQL）；**M1C** 自适应现金局课程（随包已审核翻前内容、初始诊断、能力树掌握判定、间隔复练、今日计划）。
- **M2A** 现金局 Session（种子确定的 6-max 发牌、可披露的确定性虚拟对手、15/30/60 手可中断续打、关键手复盘与逐街回放、跨 Session 翻前频率报告）。
- **M2B** 个人牌局实验室（Hand Lab）：PokerStars 现金牌谱确定性导入与冲突登记、节点粒度偏离分析、偏离补救训练、手动场景构建器、逐街回放与内容反事实——五个切片全部归档。
- **M3** 锦标赛地基：新包 `TournamentEngine`（升盲/ante 结构、精确有理数 ICM 权益计算器、短筹码 push/fold 决策上下文，均内容无关）+ 首个消费真实锦标赛内容的 HU push/fold 训练器。HU push/fold 求解内容已经具名人工审核晋升为 `reviewed` 并随所有频道（含 store）交付。

技术栈：SwiftUI、Swift 6.2.3、Xcode 26.2、XcodeGen、Swift Package Manager，客户端无第三方运行时依赖；服务端是 Go + MySQL 8.4+ InnoDB，源码在 `Server/`。

## Commands

生成 Xcode 工程（改动 `project.yml` 或 target 结构后必须重新生成）：

```bash
xcodegen generate
```

运行单个 Swift 包的测试（现有 10 个包）：

```bash
swift test --package-path Packages/PokerCore
swift test --package-path Packages/StrategyContent
swift test --package-path Packages/TrainingDomain
swift test --package-path Packages/StrategyTooling
swift test --package-path Packages/SessionSimulation      # M2A 发牌 + 虚拟对手 + Session
swift test --package-path Packages/SessionPersistence
swift test --package-path Packages/TrainingPersistence     # FileTrainingEventStore（M2A 迁出领域包）
swift test --package-path Packages/HandHistory             # M2B 牌谱解析 / 观察手 / 构造 spot
swift test --package-path Packages/HandHistoryPersistence
swift test --package-path Packages/TournamentEngine        # M3 结构 / ICM / push-fold（内容无关）
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

完整验证 M1A（三个包测试 + App 单测 + iPhone/iPad UI 测试 + Release 模拟器构建 + fixture 排除断言 + `git diff --check`，任何步骤失败返回非零）：

```bash
bash scripts/verify-m1a.sh
```

iPhone/iPad destination 可分别用 `M1A_IPHONE_DESTINATION` / `M1A_IPAD_DESTINATION` 环境变量覆盖；iPad 默认自动探测 `iPad Pro 13-inch (M4)`，不存在时回退到 `(M5)`，两者都没有则报错而不是跳过。

完整验证 M1B（先跑 `verify-m1a.sh`，再跑 Go 静态检查与单测、隔离 MySQL 上的集成与双设备 E2E、iOS 账号与同步测试、Release 密钥门禁）：

```bash
bash scripts/verify-m1b.sh
```

集成测试需要本机可执行 `mysqld`；`scripts/test-server-mysql.sh` 会在临时目录启动一个独立实例，不触碰既有 MySQL。单独跑服务端：

```bash
cd Server && go test ./...
bash scripts/test-server-mysql.sh go test -tags=integration ./...
```

完整验证 M1C（四个包测试含 StrategyTooling + App 单测 + `PokerCoachUITests/M1CSurfaceTests` + 核心内容字节级重导入比对 + Debug/Dogfood/Release 三种构建 + 内容门禁的正反双向验证 + 冻结契约检查）：

```bash
bash scripts/verify-m1c.sh
```

它不包含 `verify-m1a.sh`（iPad 布局测试仍归后者），改动横跨切片时两个都要跑。

验证 M2A（模拟引擎、对手表、Session 记录、以及让引擎不知道教学内容存在的层边界；每个只能通过的门禁都对刻意构造的坏输入再跑一次）：

```bash
bash scripts/verify-m2a.sh
```

验证 M2B（牌谱解析器、冲突模型、版本化个人牌谱库，以及保证解析器不知道教学内容存在、导入手不会变成 `TrainingEvent` 的层边界；同样正反双向）：

```bash
bash scripts/verify-m2b.sh
```

锦标赛 HU push/fold 内容的可复现性 + 回归门禁（从锁定求解器在临时目录重生成归一批次、重校验、重建导出/包与黄金 manifest，与在库文件逐字节比对，再跑受影响 Swift 套件与包层门禁；需要 Rust 工具链和一次网络拉取锁定来源）：

```bash
bash scripts/verify-tournament-content.sh
```

检查工程骨架（`project.yml`、xcconfig、Package.swift 中的告警即错误设置是否齐全）：

```bash
bash scripts/check-project-shape.sh
```

本地运行：`xcodegen generate` → 用 Xcode 打开 `PokerCoach.xcodeproj` → 选择 `PokerCoach` scheme + Debug + 一个 iPhone/iPad Simulator → Run（`--reset-training-events` launch argument 可清空本地训练事件）。Debug 同时打包已审核的 `CoreStrategyPack.json` 和 `DevStrategyPack.json`，`BundledContentLoader` 按可信度优先取 Core，fixture 只在没有更可信的包时才被训练使用。这个 fixture 只是确定性演示数据，未经扑克策略审核；任何由它生成的界面必须显示“开发演示数据”，且不得进入 Dogfood/Release（`verify-m1a.sh` 与 `check-release-content.sh` 都会断言）。

改动随包策略内容（`PokerCoach/Resources/CoreStrategyPack.json` **不可手工编辑**，`verify-m1c.sh` 会重新导入并要求字节相同）：

```bash
python3 Content/build-core-export.py   # 从仓库根目录运行，重建 Content/exports/core-6max-100bb.json
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/core-6max-100bb.json \
  --content-version <新版本> --review-status reviewed --origin generativeModel \
  --reviewed-by '<审核人>' --reviewed-at '<ISO8601>' \
  --output PokerCoach/Resources/CoreStrategyPack.json
swift run --package-path Packages/StrategyTooling strategy-golden \
  --old <旧包> --new <新包> --cases <cases.json>
```

锦标赛 HU push/fold 内容走独立流水线（`Content/tournament/`）：`fetch-locked-source.py`/`generate-hu-pushfold.py` 从锁定的开源 CFR+ 求解器（`b-inary/poker-cfr`，BSD-2-Clause，hash 门禁）生成归一批次，`validate_hu_batch.py` + `verify-equities.py` + `cross-check-exploitability.py` 独立校验，`build-tournament-exports.py`/`import-tournament-packs.py` 产出 20 个 `origin=solver` + `reviewStatus=unverifiedDraft` 包（存 `Content/packs/`，作为可复现性锚点）。晋升为 `reviewed` 由 `Content/promote-tournament-packs.py` 完成：它校验完整审核记录（具名审核人 + ISO8601 + approved + 三项证据阈值）后用新内容版本重导入并做黄金回归，产物为 `Content/packs-reviewed/`。自动导入永不产 `reviewed`——生成方不能自我背书，晋升需人签署。

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

App Infrastructure                 (PokerCoach/Infrastructure/: Auth · Content · Network · Profiles · Sync)
  —— 实现领域协议、承载 HTTP/钥匙串/文件等具体技术，由 App/AppDependencies 注入；领域包不得反向依赖它
```

- **PokerCore**：牌、精确金额（`BBAmount`/`EVAmount`）、合法行动、`BettingDecisionContext`、`Street`，以及 M2A/M2B 抽出的 `SpotSignature`/`HandClass`。不依赖仓库内任何其他模块，不含教学文案、网络、存储或用户状态。
- **StrategyContent**：加载不可变策略包（`StrategyPack`、`DecisionScenario`、`StrategyPackLoader`、`StrategyPackValidator`）。使用 PokerCore 的类型，负责解码/校验/版本追溯。每个决策节点的行动频率总和必须严格等于 10,000 basis points。
- **TrainingDomain**：`DecisionScorer`、`TrainingEvent`、`TrainingEventStore`（协议）、`PlayerModelReducer`、`TrainingPlanner`，以及 M1C 的 `DiagnosticBlueprint`、`CurriculumResolver`、`NodeMastery`、`RepetitionScheduler`。可读 PokerCore 与 StrategyContent，禁止依赖 SwiftUI、HTTP 或数据库实现。评分逻辑不得读取后续发牌或本手输赢结果。
- **TrainingPersistence**：`FileTrainingEventStore`（JSON Lines 追加式，M2A 从 TrainingDomain 迁出到此）。**SessionPersistence** / **HandHistoryPersistence**：Session 记录与个人牌谱/构造 spot 的版本化文件存储。
- **SessionSimulation**（M2A，仅依赖 PokerCore）：种子确定发牌、虚拟对手行为表、Session 状态机、关键手选择与频率报告。**HandHistory**（M2B，仅依赖 PokerCore）：`ObservedHand` 牌谱解析、`heroDecisionSignatures()`、`ConstructedSpot`——纯扑克事实，不知道教学内容存在。
- **TournamentEngine**（M3，仅依赖 PokerCore）：`BlindSchedule` 升盲/ante 结构、精确有理数 `Fraction` 与 `ICMCalculator`（Malmuth-Harville，只枚举入钱名次、溢出即抛不回退浮点）、筹码计原生的 `PushFoldContext`/`PushFoldOption`。全整数/有理、内容无关（不含范围/频率/求解器真值）。
- **StrategyTooling**（`Packages/StrategyTooling/`）：本机内容工具（`strategy-import`、`strategy-golden`），**故意不写进 `project.yml`**，绝不链接进 APP。
- **SwiftUI App**（`PokerCoach/`）：View 只管布局/交互/无业务含义的显示状态；ViewModel 组合领域协议，但不得自行计算 EV、合法行动或能力分数。跨 Feature 复用且无业务状态的组件放 `PokerCoach/Shared/`。内容下载、同步、认证等技术实现放 `PokerCoach/Infrastructure/`，不进领域包。四个核心标签在 M2A/M2B/M3 各切片中保持不变；Session、Hand Lab、锦标赛 push/fold 训练器等新入口都挂在「复盘」标签下。
- **Server**（`Server/`）：Go + MySQL 的账号与同步服务，独立部署，与领域包只通过 `Contracts/` 中冻结的事件契约交互。

**禁止的依赖方向**：`PokerCore → StrategyContent`、`PokerCore → TrainingDomain`、任何领域包 → SwiftUI 或具体 HTTP 客户端、View → 文件系统/数据库/同步 DTO、生成式文本 → `DecisionScorer` 输入。远端 DTO（M1B 引入）必须在基础设施层转换为领域类型后才能进入 TrainingDomain。

### M1A → M1B 稳定契约

M1B（独立身份与同步）只能依赖以下类型且不得改变其语义，详见 `docs/architecture/m1a-module-boundaries.md`：

- `TrainingEvent`、`TrainingEventStore`（`Packages/TrainingDomain/Sources/TrainingDomain/`；`FileTrainingEventStore` 实现自 M2A 起在 `Packages/TrainingPersistence/`）
- `StrategyPackManifest`（`Packages/StrategyContent/Sources/StrategyContent/StrategyModels.swift`）

`TrainingEventStore.allEvents()` 按 `occurredAt` 再按事件 UUID 稳定排序供 UI/归约使用；`events(after:)` 严格按 JSON Lines 追加顺序读取供增量同步使用 —— 即使设备时钟回拨，后追加事件仍必须出现在此前 checkpoint 之后。

`Contracts/training-event-upload-v1.json` 是**字节冻结**的上传契约，摘要记在同名 `.sha256`，由 `Server/migrations/contracts_test.go`、`PokerCoachTests/Support/ContractEventFixture.swift` 与 `verify-m1c.sh` 三处断言。新增能力应通过 `scenarioID` 关联内容包求得，而不是往事件里加字段。

位置表示（供 M3 锦标赛复用，见同一文档）：`SolverAssumptions.tableSize`（2–9 人）+ `DecisionScenario.heroSeatOffsetFromButton`（`0..<tableSize`，`0`=BTN 或 heads-up 的 BTN/SB，向后递推）。`StrategyPackValidator` 必须联合校验两者；新增场景不得引入自由文本位置或固定人数位置枚举。

### 精确数据规则

- 筹码/底池：整数 centi-BB。EV：整数 milli-BB。频率：basis points，节点内总和恒为 10,000。
- 浮点数只用于最终展示，绝不作为领域存储或比较的真值。
- 金额/频率/EV 的 JSON 字段名必须显式带单位。

### 策略内容规则

- `reviewStatus` 四态：`testFixture`（仅测试/演示）、`unverifiedDraft`（内部自洽但无人核对过，必须在界面披露）、`reviewed`（可上架，必须带 `reviewedBy` + `reviewedAt`，校验器拒绝无审核人的 `reviewed`）、`retired`（历史保留，不用于新训练）。
- `origin`（`solver` / `generativeModel` / `fixture`）与 `reviewStatus` 是两件事：前者说真值从哪来，后者说有没有人检查过。人工审核不能把生成内容变成求解器产出——`generativeModel` + `reviewed` 的内容界面必须显示“非求解器产出，已人工审核”。
- 三种构建频道由各 configuration 写入 Info.plist 的 `PCContentChannel`，`scripts/check-release-content.sh` 从产物读回该值决定允许的审核状态：`debug` 三态皆可、`dogfood` 允许 `unverifiedDraft` 与 `reviewed`、`store` 只允许 `reviewed`。门禁按 manifest 而非文件名识别包，并校验包与随附 `.sha256` 一致；缺少频道标记直接失败。
- 已发布 pack 不可原地修改；新内容必须用新的 content version；`TrainingEvent` 永久记录生成时的 pack ID 与 content version。内容升级必须过 `strategy-golden` 黄金回归。
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

- `openspec/specs/`：当前生效的主规格（39 个能力域，按切片划分）：
  - M1A：`cash-decision-domain`、`explainable-decision-training`、`local-learning-profile`、`versioned-strategy-content`、`adaptive-native-shell`、`m1a-release-safety`
  - M1B：`independent-account-access`、`secure-device-sessions`、`local-first-event-sync`、`mysql-sync-service`、`account-data-rights`、`m1b-verification`
  - M1C：`strategy-content-pipeline`、`initial-diagnostic`、`adaptive-curriculum`、`spaced-repetition`
  - M2A：`session-dealing`、`virtual-opponents`、`cash-session-run`、`key-hand-review`、`session-frequency-report`、`training-progress-trend`
  - M2B（Hand Lab）：`hand-history-import`、`import-conflict-review`、`personal-hand-library`、`imported-hand-signatures`、`imported-hand-analysis`、`imported-hand-remediation`、`manual-scenario-builder`、`hand-lab-replay`
  - M3（锦标赛）：`tournament-structure`、`tournament-icm`、`tournament-icm-calculator`、`tournament-pushfold`、`tournament-pushfold-training`、`tournament-bubble-factor`、`tournament-strategy-source-adapter`、`tournament-strategy-content-import`、`tournament-content-promotion`
- `openspec/changes/`：进行中和已归档（`archive/`，见 `archive/index.md`）的变更记录。M1、M2A、M2B（五切片）、M3 各 change 均已归档，其 design.md、tasks.md 与评审记录留在归档目录里。
- `docs/superpowers/specs/`：已批准的产品设计；`docs/superpowers/plans/`：实施路线和详细任务计划。
- `docs/architecture/`、`docs/standards/`、`docs/product/` 各自的 `index.md` 是对应知识域的入口。
