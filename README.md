# Poker Coach

Poker Coach（仓库名 `porkHelper`）是一个原生 iPhone/iPad 德州扑克决策训练应用。M1A 提供可离线运行的现金桌训练纵向切片；完整 M1 还包括 M1B 独立账号与同步，以及 M1C 自适应课程。

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

## 运行 Debug fixture

先运行 `xcodegen generate`，在 Xcode 中打开 `PokerCoach.xcodeproj`，选择 `PokerCoach` scheme、Debug configuration 和一个 iPhone 或 iPad Simulator，然后 Run。Debug 会自动加载 `PokerCoach/Resources/DevStrategyPack.json`；如需清空本地训练事件，可在 scheme 的 Run arguments 中加入 `--reset-training-events`。

> 警告：Debug fixture 的策略仅是确定性开发演示数据，未经扑克策略审核，不是扑克建议。所有由 fixture 生成的页面必须显示“开发演示数据”；Release 构建不得包含该资源。

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

## 设计与路线

- [已批准的产品设计](docs/superpowers/specs/2026-08-06-texas-holdem-coach-design.md)
- [Poker Coach 实施路线](docs/superpowers/plans/2026-08-06-poker-coach-implementation-roadmap.md)
- [M1A 模块边界与 M1B 交接](docs/architecture/m1a-module-boundaries.md)
