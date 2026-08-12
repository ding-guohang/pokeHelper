---
name: session-m2a-cash-simulation-20260810-01
status: planned
---

# 执行计划：M2A 现金局 Session 模拟

铁律沿用：先写测试并**观察它红**，再写实现。没见过红的测试与没有测试等价——本项目已经为此付过三次代价。

## Capability 追溯

| Capability | Requirement | Task |
|---|---|---|
| cash-decision-domain | 合法行动过滤（须跟注额封顶） | T2 |
| session-dealing | 发牌由种子完全确定 | T3 |
| session-dealing | 下注状态永远合法 | T4, T5 |
| virtual-opponents | 四种可披露的对手档案 | T6, T7 |
| virtual-opponents | 对手行动始终合法 | T6 |
| cash-session-run | 三种长度的 Session | T8, T9 |
| cash-session-run | Session 手牌不进入能力画像 | T10 |
| key-hand-review | 挑出值得复盘的手牌 | T11 |
| key-hand-review | 命中内容的关键手可对照与重打 | T12, T13 |
| session-frequency-report | 按位置累计并与内容基准对照 | T14 |
| session-frequency-report | 频率来自记录的手牌 | T14 |
| local-learning-profile | Session 手牌不写入事件 | T10, T13 |

## 里程碑 A：PokerCore 地基

### T1 — `HandClass` 与 169 格往返
`covers:` session-dealing / key-hand-review 的等同判定地基

新增 `Packages/PokerCore/Sources/PokerCore/HandClass.swift`。

先写测试 `HandClassTests`：
1. `枚举全部 169 个取值并逐个往返` — 由 13 个 rank 生成 13 对子 + 78 同花 + 78 非同花 = 169，对每个 `HandClass(notation:)` → `.description` → 再解析，三者一致。**不抽样。**
2. `两张牌的给定顺序不影响归类` — 对全部 1326 个具体组合，`HandClass(a,b) == HandClass(b,a)`。
3. `对子不带后缀` — 13 个对子的 `description` 长度为 2。
4. `非法记号被拒绝` — `"AKx"`、`"ZZ"`、`"A"`、`""`、`"AA s"` 全返回 nil。
5. `1326 个组合恰好落进 169 个类别，且各类计数为 6/4/12`。

红灯观察（已实测）：
- 把 `init(_:_:)` 的 suitedness 写死为 `.offsuit` → 测试 5 变红（169 个类别塌成 91 个）。测试 2 仍绿，因为该变异是对称的——预测时以为它会红，是我判断错了。
- 让 `init(notation:)` 用 `!=` 代替 `>` → 测试 4 变红（`KAs` 被接受）。
- 先判花色再判对子 → **不变红，且这是对的**：两张不同的牌同点数时必然不同花，两种写法对合法输入等价。这次变异证伪的是我写在代码里的一句注释，不是代码。

### T2 — 须跟注额封顶（cash-decision-domain 修改）
`covers:` cash-decision-domain / 合法行动过滤

`BettingDecisionContext` 的 `precondition(amountToCall <= effectiveStack)` **保持不变**——它是正确的，proposal 已改为与之一致。

新增测试 `BettingDecisionContextTests.筹码用尽时的跟注即全下`：
- `amountToCall == effectiveStack == 300` 时 `legalActions()` 恰为 `{.fold, .call(to: 300)}`
- 断言集合中**不含**独立的 `.allIn` 项

红灯观察：把 `.allIn` 分支的守卫从 `amountToCall < effectiveStack` 改成无条件，测试应变红。

### T3 — `SpotSignature` 及其分量
`covers:` 全部等同判定

新增 `Street`、`FacingAction`、`StackBucket`、`SpotSignature`。分桶边界照 proposal 枚举：`[0,2000) [2000,6000) [6000,12000) [12000,∞)`。

测试：
1. `分桶边界值归属明确` — 1999/2000/5999/6000/11999/12000 逐个断言落在哪个桶。
2. `相邻分桶不相等`。
3. `五个分量任一不同则签名不同` — 逐个分量改一处，断言不等（五条独立断言，不是一条）。

## 里程碑 B：SessionSimulation 包

### T4 — 建包与发牌
`covers:` session-dealing / 发牌由种子完全确定

新增 `Packages/SessionSimulation/`，`Package.swift` 只依赖 `PokerCore`。

确定性 RNG：明确实现一个 SplitMix64 或 PCG，**不用** `SystemRandomNumberGenerator`、不用 `hashValue`、不用字典迭代序。

测试：跨进程确定性（子进程跑同一段并比对）、同手内无重复牌、每手 2+10 张底牌与街道对应的公共牌数。

黄金夹具 `session-seed42-30hands.json` 在实现稳定后提交，并附生成脚本。

### T5 — 下注状态机与结算
`covers:` session-dealing / 下注状态永远合法

双向断言：集合内均被接受、集合外均被拒绝。结算断言：变化和为 0、赢家增量为正、底池归零、30 手后六座位合计 600BB。抽水恒为 0。

### T6 — 对手行为表
`covers:` virtual-opponents 两个 Requirement

`OpponentProfileTable.version` 常量；四个档案。黄金序列夹具与 version 绑定。20 个固定局面的可区分性夹具。

### T7 — 档案披露
`covers:` virtual-opponents / 四种可披露的对手档案

界面显示的数值逐字段等于定义；四档案两两不同；30 手后不变；披露文案与策略内容的披露是两条独立文案。

## 里程碑 C：Session 运行与记录

### T8 — Session 推进与三种长度
### T9 — 记录持久化、中断续打、行为表版本校验
`SessionRecord` / `SessionHandRecord` 与重放判定在 `SessionSimulation`；文件存储在新包
`Packages/SessionPersistence/`（只依赖 `SessionSimulation`）。存储进包而不是进
`PokerCoach/Infrastructure/`，是因为「第 7 手后终止进程」必须真的终止进程：测试拉起
`session-record-writer`，让它打完 7 手后对自己发 SIGKILL。`Process` 在 iOS 上不可用，
App 的 XCTest 目标放不下这条测试，而进程内的替身满足的是这句话的弱读法。

### T10 — 断言 Session 手牌不产生 TrainingEvent（含命中内容的情形）
断言在 `PokerCoachTests/SessionEventIsolationTests`，走 App 层的 `SessionRunCoordinator`
——它持有事件存储，所以「打完一整局都没写事件」是关于一条够得到存储的路径的断言，而不是
关于一个够不到存储的类型的断言。结构性的一半由 `scripts/check-package-layering.sh` 守：
`SessionPersistence` 看不见 `TrainingDomain`。

T10 是本里程碑的关键测试，不是附带项：整局打完后事件存储条数必须不变。

## 里程碑 D：复盘与报告

### T11 — 关键手选择
分数表见 design.md 决断 4。必含「同种子放大后五手底池会改变选择结果」。

### T12 — 逐街回放
### T13 — 对照与重打
重打产生的事件必须与今日训练产生的事件除 ID/时间/设备外逐字段相等。

### T14 — 频率报告
基准按 (位置, 面对情形) 取键；阈值 30；BB 无基准时仍显示频率；基准由内容算出而非常量。

## 里程碑 E：收口

### T15 — 分层文档与依赖门禁
更新 `docs/architecture/layering.md` 层图加入 `SessionSimulation`；加一条检查断言该包只依赖 `PokerCore`。

### T16 — `FileTrainingEventStore` 搬迁
从 `Packages/TrainingDomain/Sources/` 搬到新包 `Packages/TrainingPersistence/`（依赖 `TrainingDomain`）；协议留在领域包。搬包而不是搬进 App 目标，是为了让并发测试原样跑，理由见 design.md。见 `docs/architecture/known-gaps.md`。搬完从该文件删除对应条目。

### T17 — `scripts/verify-m2a.sh`
沿用 verify-m1c.sh 的形状。每一道门禁必须有实测的失败路径，不接受只跑通绿灯。

### T18 — UI 可达性
Session、关键手复盘、频率报告在真实构建中可达，有 UI 测试驱动。

## 不变量（每个里程碑结束时复验）

- `Contracts/training-event-upload-v1.sha256` 未变更
- `CoreStrategyPack.json` 与其 `.sha256` 未变更
- `TrainingDomain` 不依赖 `SessionSimulation`
- `bash scripts/verify-m1a.sh`、`verify-m1b.sh`、`verify-m1c.sh` 仍通过
