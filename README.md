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

## 设计与路线

- [已批准的产品设计](docs/superpowers/specs/2026-08-06-texas-holdem-coach-design.md)
- [Poker Coach 实施路线](docs/superpowers/plans/2026-08-06-poker-coach-implementation-roadmap.md)
- [M1A 模块边界与 M1B 交接](docs/architecture/m1a-module-boundaries.md)
