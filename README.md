# Poker Coach

Poker Coach（仓库名 `porkHelper`）是一个原生 iPhone/iPad 德州扑克决策训练应用。已实现并归档的切片：

- **M1A** 可离线运行的现金桌训练纵向切片
- **M1B** 独立账号、设备会话与事件同步（Go + MySQL 服务端在 `Server/`）
- **M1C** 自适应现金局课程：随包交付的已审核翻前内容、初始诊断、能力树掌握判定、间隔复练与今日计划
- **M2A** 现金局 Session：种子确定发牌、可披露的确定性虚拟对手、可中断续打、关键手复盘与逐街回放、跨 Session 翻前频率报告
- **M2B** 个人牌局实验室（Hand Lab）：PokerStars 现金牌谱导入与冲突登记、节点粒度偏离分析、偏离补救训练、手动场景构建器、逐街回放与内容反事实
- **M3** 锦标赛地基（`TournamentEngine`：升盲结构、精确有理数 ICM 权益计算器、短筹码 push/fold 决策上下文）+ 首个消费真实锦标赛内容的 HU push/fold 训练器；HU push/fold 求解内容已具名人工审核晋升为 `reviewed` 并随所有频道（含 store）交付

每个切片有各自的验证脚本：`verify-m1b.sh` 会先跑 `verify-m1a.sh`；`verify-m1c.sh`、`verify-m2a.sh`、`verify-m2b.sh` 各自独立运行；`verify-tournament-content.sh` 是锦标赛内容的可复现性 + 回归门禁。

## 开发环境

- Xcode 26.2
- Apple Swift 6.2.3
- XcodeGen 2.45.4（通过 `xcodegen --version` 核对）

## 生成与验证

从仓库根目录生成 Xcode 工程：

```bash
xcodegen generate
```

从干净 checkout 运行完整 M1A 验证：

```bash
bash scripts/verify-m1a.sh
```

脚本依次运行三个 Swift 包测试、App 单元测试、iPhone UI 测试、iPad UI 测试、Release Simulator 构建与开发 fixture 排除断言，最后运行 `git diff --check`。任何步骤失败都会返回非零退出码。

默认 iPhone destination 是 `platform=iOS Simulator,name=iPhone 16 Pro,OS=latest`。iPad 会先选择可用的 `iPad Pro 13-inch (M4)`；当前 Simulator 没有 M4 时会自动使用同尺寸的 `iPad Pro 13-inch (M5)`，两者都没有时会明确失败，不会跳过 iPad 测试。脚本会在测试前打印实际选择。

可以用完整的 Xcode destination 字符串覆盖任一设备：

```bash
M1A_IPHONE_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
M1A_IPAD_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' \
bash scripts/verify-m1a.sh
```

## 本地运行 APP

先运行 `xcodegen generate`，在 Xcode 中打开 `PokerCoach.xcodeproj`，选择 `PokerCoach` scheme、Debug configuration 和一个 iPhone 或 iPad Simulator，然后 Run。如需清空本地训练事件，可在 scheme 的 Run arguments 中加入 `--reset-training-events`。

Debug 构建同时打包已审核的 `CoreStrategyPack.json` 和开发 fixture `DevStrategyPack.json`；`BundledContentLoader` 按可信度取用（Core 优先），fixture 只在没有更可信的包时才会被训练使用。

> 警告：Debug fixture 的策略仅是确定性开发演示数据，未经扑克策略审核，不是扑克建议。所有由 fixture 生成的页面必须显示“开发演示数据”；Dogfood 与 Release 构建不得包含该资源。

## M1B 验证

M1B 增加独立账号、设备会话与事件同步。服务端是 Go + MySQL 8.4+ InnoDB，源码在 `Server/`。

从干净 checkout 运行完整 M1B 验证：

```bash
bash scripts/verify-m1b.sh
```

它先跑 `verify-m1a.sh`（M1B 不得让离线切片退化），再依次执行 Go 静态检查与单测、隔离 MySQL 上的集成与双设备端到端测试、iOS 账号与同步测试、Release 密钥门禁，最后 `git diff --check`。任何一步失败都返回非零。

集成测试需要本机可执行 `mysqld`（通过 `brew install mysql` 安装即可）。`scripts/test-server-mysql.sh` 会在临时目录里启动一个**独立的** mysqld，用 OS 分配的空闲端口和临时凭据，退出时由 trap 清理；它不会连接、修改或依赖任何既有的 MySQL 服务或 schema。

单独运行服务端测试：

```bash
cd Server && go test ./...                                    # 单元测试
bash scripts/test-server-mysql.sh go test -tags=integration ./...   # 集成与 E2E
```

### 本地运行服务

```bash
cd Server
POKER_COACH_ENV=development \
POKER_COACH_MYSQL_DSN='user:password@tcp(127.0.0.1:3306)/pokercoach?parseTime=true' \
go run ./cmd/api
```

生产环境额外要求以下变量，缺失时**启动直接失败而不是静默降级**：

| 变量 | 缺失后果 |
|---|---|
| `POKER_COACH_THROTTLE_SECRET`（64 位十六进制） | 每次重启都会重置全部登录限流窗口 |
| `POKER_COACH_APPLE_CLIENT_ID` | Apple 令牌的 audience 校验失去意义 |
| `POKER_COACH_SMTP_*` 全套 | 开发邮件器会把验证链接写进日志 |

APP 侧的服务地址由 Info.plist 的 `AccountServiceBaseURL` 指定，默认是本机开发地址。M1B 不含生产部署，上架前必须替换。

## M1C 验证

M1C 增加随包交付的已审核内容、初始诊断、能力树与掌握判定、间隔复练和今日计划，以及内容导入/回归工具链（`Packages/StrategyTooling/`）。

```bash
bash scripts/verify-m1c.sh
```

它跑四个 Swift 包测试（含 StrategyTooling）、App 单测、`PokerCoachUITests/M1CSurfaceTests`、核心内容的字节级重导入比对、三种 configuration 的构建，然后对内容门禁做双向验证：不仅确认合法产物通过，还用刻意构造的坏输入（未审核内容、缺失频道标记、改过 EV 的包、改名后的未审核包）确认门禁会拒绝。iPad 布局测试仍归 `verify-m1a.sh`。

### 三种构建频道

每个 configuration 把自己的频道写进 Info.plist 的 `PCContentChannel`，`scripts/check-release-content.sh` 从构建产物里读回该值决定允许哪些审核状态——不是由调用方传参：

| Configuration | 频道 | 允许的 `reviewStatus` |
|---|---|---|
| Debug | `debug` | `testFixture` / `unverifiedDraft` / `reviewed` |
| Dogfood | `dogfood` | `unverifiedDraft` / `reviewed` |
| Release | `store` | 仅 `reviewed` |

门禁按 manifest 而非文件名识别策略包，并校验包与随附的 `.sha256` 一致；缺少 `PCContentChannel` 时直接失败。

### 内容流水线

随包内容是 `PokerCoach/Resources/CoreStrategyPack.json`（`cash-6max-100bb-core`，6-max 100BB 翻前 RFI 与 3bet）。它**不能手工编辑**——`verify-m1c.sh` 会从导出重新生成并要求字节相同。修改内容的路径是：

```bash
python3 Content/build-core-export.py          # 由脚本内的范围表重建 Content/exports/core-6max-100bb.json（从仓库根目录运行）
swift run --package-path Packages/StrategyTooling strategy-import \
  --export Content/exports/core-6max-100bb.json \
  --content-version <新版本> --review-status reviewed --origin generativeModel \
  --reviewed-by '<审核人>' --reviewed-at '<ISO8601>' \
  --output PokerCoach/Resources/CoreStrategyPack.json

swift run --package-path Packages/StrategyTooling strategy-golden \
  --old <旧包> --new <新包> --cases <cases.json>   # 内容升级必须过黄金回归
```

已发布的 content version 不可原地修改，改内容必须给新版本。`strategy-import` 没有默认审核状态，也不会自己产出 `reviewed`——该状态要求具名审核人和审核时间。

内容的**来源**（`origin`）与**审核状态**（`reviewStatus`）分开记录：当前核心集由模型生成、由仓库所有者逐范围表审核，因此是 `origin: generativeModel` + `reviewStatus: reviewed`，界面据此披露“非求解器产出，已人工审核”。翻后内容不在 M1C 交付范围内。

## M2A / M2B 验证

M2A 加入现金局 Session（模拟引擎、虚拟对手、Session 记录），M2B 加入个人牌局实验室（牌谱解析、冲突模型、版本化个人牌谱库）。两个脚本各自独立运行，且每个只能通过的门禁都会对刻意构造的坏输入再跑一次——只会成功的门禁与永远成功的门禁无法区分。

```bash
bash scripts/verify-m2a.sh
bash scripts/verify-m2b.sh
```

M2A 保证模拟引擎不知道教学内容存在、Session 手牌不产生 `TrainingEvent`（只有复盘「重打」才走带信心的训练管线）；M2B 保证解析器不知道教学内容存在、导入手不会变成 `TrainingEvent`。新入口（Session、Hand Lab）都挂在「复盘」标签下，四个核心标签保持不变。

## 锦标赛内容验证

M3 的 `TournamentEngine` 是内容无关的地基（升盲结构、精确有理数 ICM、短筹码 push/fold 决策上下文），策略真值来自锁定的开源 CFR+ 求解器而非编造。HU push/fold 内容的可复现性 + 回归门禁：

```bash
bash scripts/verify-tournament-content.sh
```

它从锁定求解器（`b-inary/poker-cfr`，BSD-2-Clause，hash 门禁）在临时目录重生成归一批次、重校验、重建导出/包与黄金 manifest，并与在库文件逐字节比对，再跑受影响的 Swift 套件与包层门禁。需要 Rust 工具链和一次网络拉取锁定来源。

内容分两步落地：`Content/tournament/` 的流水线产出 20 个 `origin=solver` + `reviewStatus=unverifiedDraft` 包（存 `Content/packs/`，作为可复现性锚点）；`Content/promote-tournament-packs.py` 在校验完整审核记录（具名审核人 + ISO8601 + approved + 三项证据阈值）并做黄金回归后，用新内容版本晋升为 `reviewed`（存 `Content/packs-reviewed/`）。自动导入永不产 `reviewed`——生成方不能自我背书，晋升需人签署。当前随包的 20 个 HU push/fold 包已完成晋升，随 store 在内的所有频道交付，界面不再显示“未经策略审核”横幅。

## 设计与路线

- [已批准的产品设计](docs/superpowers/specs/2026-08-06-texas-holdem-coach-design.md)
- [Poker Coach 实施路线](docs/superpowers/plans/2026-08-06-poker-coach-implementation-roadmap.md)
- [M1A 模块边界与 M1B 交接](docs/architecture/m1a-module-boundaries.md)
- [M1B 身份与同步设计](docs/superpowers/specs/2026-08-07-m1b-identity-sync-design.md)
- [M1C 自适应课程设计](openspec/changes/archive/curriculum-m1c-adaptive-cash-20260810-01-20260810-230421/design.md)
- [M2A 现金局 Session 设计](openspec/changes/archive/session-m2a-cash-simulation-20260810-01-20260812-092232/design.md)
- [M2B 个人牌局实验室（导入切片）设计](openspec/changes/archive/handlab-m2b-import-preview-20260812-01-20260812-174946/design.md)
- [M3 锦标赛结构地基设计](openspec/changes/archive/tournament-m3-structure-20260813-01-20260813-140652/design.md)
- 当前生效的主规格在 [`openspec/specs/`](openspec/specs/)（39 个能力域），历史变更在 [`openspec/changes/archive/`](openspec/changes/archive/index.md)。
