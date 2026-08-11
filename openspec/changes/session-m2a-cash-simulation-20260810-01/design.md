---
name: session-m2a-cash-simulation-20260810-01
status: designed
---

# 技术方案：M2A 现金局 Session 模拟

本文只写**审需阶段留下的四个决断**和它们带来的结构后果。proposal 已经把行为规格定死，这里不复述。

## 决断 1：`SpotSignature` 放在 PokerCore

### 问题

「局面等同」要同时看 Session 局面与 `DecisionScenario`。两条直觉路线都越界：

- 判定放进 `SessionSimulation` → 它得 `import StrategyContent`，而这个新包的定位是「不知道教学内容存在」的牌局引擎。
- 判定放进 `TrainingDomain` → 它得 `import SessionSimulation`，而 `SessionSimulation` 推进牌局时又要问「这个决策点值不值得记为可对照」，构成 `TrainingDomain ↔ SessionSimulation` 环。

`layering.md` 现有的层图里根本没有 `SessionSimulation` 的位置，这两条路线都是在图外走。

### 结论

在 `PokerCore` 定义 `SpotSignature`，两侧各自产出签名，比较是值比较。

```text
        ┌──────────────┐
        │  PokerCore   │  Card / BBAmount / TablePosition
        │              │  DecisionAction / BettingDecisionContext
        │  SpotSignature ← 新增
        └──────┬───────┘
               │ (被依赖)
      ┌────────┴─────────┬─────────────────────┐
      │                  │                     │
StrategyContent   SessionSimulation ← 新增   （无第三方）
      │                  │
      └────────┬─────────┘
               │  两侧各自 → SpotSignature
        ┌──────┴────────┐
        │ TrainingDomain│（只依赖 StrategyContent + PokerCore，不变）
        └──────┬────────┘
               │
        ┌──────┴────────┐
        │  App 层比较    │  SessionHand.signature == Scenario.signature
        └───────────────┘
```

`SessionSimulation` 只依赖 `PokerCore`。它不知道 `StrategyContent` 存在，也不知道「训练」是什么概念。

### 为什么 `SpotSignature` 属于 PokerCore 而不是别处

签名的五个分量全部是纯扑克事实，没有一个是教学概念：

| 分量 | 类型 | 来源 |
|---|---|---|
| `street` | `Street`（新增枚举，preflop/flop/turn/river） | 公共牌张数 |
| `heroSeatOffsetFromButton` | `Int` | 已有，`TablePosition` 的输入 |
| `handClass` | `HandClass`（新增） | 两张手牌 |
| `facing` | `FacingAction`（新增：`.unopened` / `.singleRaise` / `.reraise`） | 下注序列 |
| `stackBucket` | `StackBucket`（新增） | `BBAmount` |

`PokerCore` 的既有职责就是「牌、精确金额、合法行动和牌局规则」。把两张牌归类为 `AKs` 是牌的性质，不是教学的性质。

### `HandClass` 不是新发明

169 格记号已经在用：`RangeCell.handClass` 是 `String`。核对过 `CoreStrategyPack.json`，102 个取值全部合法（13 对子 / 57 同花 / 32 非同花，对子不带后缀）。

`PokerCore` 新增的是把它从字符串升级为类型：

```swift
public struct HandClass: Hashable, Sendable, CustomStringConvertible {
    public enum Suitedness: Sendable { case pair, suited, offsuit }
    public let highRank: Rank
    public let lowRank: Rank
    public let suitedness: Suitedness

    /// 从两张具体的牌归类。同一手牌两种给定顺序必须得到同一个值。
    public init(_ a: Card, _ b: Card)

    /// 从 169 格记号解析，供 StrategyContent 侧使用。
    public init?(notation: String)

    public var description: String   // 回到 "AKs" / "AKo" / "77"
}
```

**迁移策略：`RangeCell.handClass` 保持 `String` 不变。** 改它的类型会改变策略包的 JSON 编码，进而改变 `CoreStrategyPack.json` 的字节与 `.sha256`，触发内容门禁——为一次内部类型整洁付出重新签署内容的代价，不划算。`StrategyContent` 侧在需要签名时用 `HandClass(notation:)` 解析。解析失败在包校验时就报错，不留到运行时。

这条边界的测试义务：`HandClass(a, b).description` 与 `HandClass(notation:)` 必须往返一致，且对全部 169 个取值成立——不是抽样。

## 决断 2：Session 记录不跨设备同步

不纳入 M2A。理由不是「工作量大」：

- 事件契约 `Contracts/training-event-upload-v1.json` 已冻结，proposal 承诺不动它。同步 Session 记录需要一份新的服务端 schema、一套新的幂等键、以及「两台设备同时续打同一 Session」的冲突语义——这三样都是独立的设计题。
- 学习相关的数据**已经**会同步：复盘里「重打」产生的是普通 `TrainingEvent`，走现有通路。换设备丢的是牌局回放，不是学习进度。

代价要说清楚：换设备看不到历史 Session。这写进 Non-Goals，不假装它不存在。

## 决断 3：对手行为表硬编码在 SessionSimulation，但带版本号

### 不随策略包交付

策略包的审核状态（`ReviewStatus`）与来源（`ContentOrigin`）是为**策略真值**设计的——某个局面下每个行动的频率与 EV，可以对着求解器核对。对手行为表不是策略真值，它是「一个虚构的对手会怎么打」，没有可核对的正确答案。把它塞进同一套审核流程，会让「reviewed」这个词同时表示两件不同的事。

### 但必须带版本号，且版本号进记录

这是审需之后新发现的洞，已补进 proposal：

Session 重放的确定性依赖三样东西——种子、发牌算法、**对手行为表**。前两样不变时改第三样，旧 Session 会静默重放出不同的牌，而「用记录重建得到逐手相同的牌」这条验收标准仍然通过（因为它在同一版本内测）。

所以：

```swift
public struct OpponentProfileTable: Sendable {
    /// 行为表版本。任何改变行动输出的修改都必须递增它。
    public static let version = "1"
    public static let profiles: [OpponentProfile] = [...]
}
```

`SessionRecord` 保存 `opponentProfileTableVersion`。重放时版本不符 → 明确告知，不声称一致。

这条规则本身需要一条测试守住：**行为表的黄金序列夹具与 `version` 常量绑定**，改了行为却没改版本号会让黄金序列测试变红，而不是让重放静默漂移。

## 决断 4：关键手选择分数

四个原因的判据与排序键：

| 原因 | 判据 | 排序键（降序） |
|---|---|---|
| `.deviation` | 局面被内容覆盖，且英雄行动在范围表对其手牌类别的权重 < 5000 基点 | 5000 + (10000 − 该行动权重) |
| `.allIn` | 该手出现过全下 | 4000 + 底池 centiBB |
| `.bigSwing` | 英雄筹码变化绝对值 ≥ 20BB（2000 centiBB） | 3000 + 变化绝对值 centiBB |
| `.bigPot` | 底池属于该 Session 底池最大的 5 手 | 2000 + 底池 centiBB |

`.deviation` 排在最上面，因为它是这张表里唯一带学习信号的一项。其余三项说的都是「这手牌决定了输赢」，那是方差；只有偏离说的是「这手你打得和内容不一样」，那是可以拿去练的东西。产品最高宗旨要求兼顾实战训练，实战部分的价值就落在这一项上。

**原先的 `.trainable`（1000 分，判据为「命中已安装内容」）已删除，因为它有两处错。** 其一，它永远选不进来：`.bigPot` 恒有 5 手候选、分数 ≥2000，所以只靠内容覆盖入选的手挤不进前五。其二，改用不含手牌类别的覆盖键之后，覆盖率从每手 0.7% 升到翻前约 83%，「是否被覆盖」不再有区分度——几乎每手都覆盖。真正有区分度的是**偏离多少**。

- 一手可能满足多个判据，取**分数最高**的那个作为展示原因。
- 取分数前 5，且至少取 3（不足 3 手时取全部）。
- 并列时按手牌序号升序——确定性 tie-break，不依赖字典序或 `hashValue`。

「艰难决策」被删掉了：它需要策略数据来判定难度，而 Session 手牌按设计约束 1 没有策略数据。留着它就是留一个算不出来的判据。

`.bigSwing` 实测在 300 个种子 × 30 手中一次都没有作为展示原因出现——20BB 的波动几乎总伴随全下，而 `.allIn` 的 4000+底池恒高于 `.bigSwing` 的 3000+变化量（变化量必小于底池）。它不是不可达（无全下的 20BB 波动可以构造），所以保留并在构造夹具上断言其规则，但不在真实 Session 上假装它会出现。

## 决断 5：频率报告的基准按 (位置, 面对情形) 取键

产品最高宗旨要求在诚实之外兼顾实战训练。职业工作流的关键一步是聚合频率而非单手，所以 M2A 加了 `session-frequency-report`。

两个必须写死的判据，都是核对内容包时发现的：

**基准的键是 (位置, 面对情形)，不是位置。** 核对 `CoreStrategyPack.json` 时发现 offset 5（CO）下有两个场景：`rfi-co` 未面对下注、`vs3bet-co-vs-btn` 面对 3bet。只按位置取基准会把 24.86% 和 9.05% 混成一个没有含义的数。这也正是 `SpotSignature.facing` 分量存在的理由，两处用同一个键。

**`facing` 必须由内容显式声明，不能反推。** 这是排期后核对数据才发现的，先前默认它可以从 `BettingDecisionContext` 推出来，不能：

| 场景 | pot | amountToCall | minimumRaiseTo |
|---|---|---|---|
| `rfi-utg` / `rfi-hj` / `rfi-co` / `rfi-btn` | 150 | 100 | 200 |
| `rfi-sb` | 150 | 50 | 200 |
| `vs3bet-co-vs-btn` | 1150 | 500 | 1250 |

「未面对下注」尚可用「底池仅有盲注」识别，但**单次加注与再加注无法区分**：跟注者投进底池的钱与加注者投进的钱在 `pot` 里没有区别，所以「加注了几次」这个信息在数据中不存在。任何按金额猜的规则对这六个场景能凑对，对后续内容会静默错桶。

Session 一侧没有这个问题——状态机精确知道加注次数。这是一处两侧不对称：签名的其余四个分量两边都能算，`facing` 只有 Session 侧能算，内容侧必须声明。

因此 `DecisionScenario` 需要新增 `facing: FacingAction`。代价要说清楚：这会改变 `CoreStrategyPack.json` 的字节与 `.sha256`，而该内容已由用户签为 `reviewed`。被改动的只是一个声明性元数据字段，用户审核过的频率与范围一个数都不变，且该字段的取值直接来自用户看过的场景标题（「CO 开池面对 BTN 3bet」）。即便如此，重新生成与重新签署必须让用户知情后再做，不能顺手带过——`ContentOrigin` 与 `ReviewStatus` 那套机制存在的意义就是不让内容的来源与审核状态被静默改写。

在用户确认之前，T14 的基准只能按场景 ID 分组，这对**已有的六个场景**是正确的，但对 Session 手牌无法用——那正是签名要解决的问题。所以这是 T14 的前置阻塞项。

**基准由内容算，不落成常量。** 算法：该 (位置, 面对情形) 范围表中非弃牌权重折算的组合数除以 1326。核对结果（用该算法从已发布包直接算出）：

| 位置 / 面对 | 场景 | 基准 |
|---|---|---|
| UTG 未面对下注 | `rfi-utg` | 15.60% |
| HJ 未面对下注 | `rfi-hj` | 19.82% |
| CO 未面对下注 | `rfi-co` | 24.86% |
| CO 面对 3bet | `vs3bet-co-vs-btn` | 9.05% |
| BTN 未面对下注 | `rfi-btn` | 46.33% |
| SB 未面对下注 | `rfi-sb` | 42.75% |

BB 没有场景——报告必须能显示「有实际频率、无基准」，不能因为查不到基准就隐藏该位置或填 0。

**漏洞容差 500 基点（5 个百分点）。** 规格原先只定了 30 次机会的阈值和结论措辞，没定多大的差距算漏洞——其唯一约束性场景是 23.67 个百分点的偏差，任何 ≥0 的容差都满足。容差取 0 会把每一个样本充足的行都列成漏洞，那份列表就不再是列表。500 基点已写进 proposal 的场景。

**样本阈值 30 次机会。** 6-max 一个位置每 6 手轮到一次，60 手 Session 只给约 10 次机会；p≈0.46 时 n=10 的标准误约 ±16 个百分点。低于阈值只报计数不下结论，且跨 Session 累计。这不是保守，是不教用户读噪声。

## 影响与不变量

### 新增

- `Packages/SessionSimulation/`——只依赖 `PokerCore`。发牌、对手行为表、Session 推进、结算。
- `PokerCore` 新增 `SpotSignature`、`HandClass`、`Street`、`FacingAction`、`StackBucket`。
- `PokerCoach/Features/Session/`——Session 界面、关键手复盘与频率报告。对照、「重打」与基准计算的桥接都在这一层，因为只有它同时看得到 `SessionSimulation` 与 `StrategyContent`。
- `PokerCoach/Infrastructure/Session/`——Session 与内容的桥接（`SessionContentMatcher`、`SessionRunCoordinator`）。记录的持久化本身在 `Packages/SessionPersistence/`：文件存储是具体实现，不进引擎包；而「第 7 手后终止进程」这条断言需要一个能被 SIGKILL 的进程，`Process` 在 iOS 上不可用，App 的测试目标放不下它。

### 顺带偿还

`Packages/TrainingDomain/Sources/TrainingDomain/FileTrainingEventStore.swift` 在这一步搬出领域包。它是具体存储实现，`layering.md` 第 3 条明确禁止领域包依赖数据库实现；协议 `TrainingEventStore` 留在领域包。见 [已知缺口](../../../docs/architecture/known-gaps.md)——那里记的「M2A 落 Session 记录持久化时一并做」就是这里。

**落点改为新包 `Packages/TrainingPersistence/`，不是 `PokerCoach/Infrastructure/`。** 本文原先写的是后者，执行时改了，理由是搬迁的测试：`FileTrainingEventStoreTests` 断言的是并发性质——两个活着的 store 交错追加不丢事件、陈旧 store 不覆盖被改坏的文件、时间戳相同时按 UUID 排序。它们是 swift-testing，搬进 App 的 XCTest 目标要重写，而在一次搬迁里重写并发测试正是覆盖率悄悄变弱的方式。搬包则一行断言都不用改。

### 必须不变

- `Contracts/training-event-upload-v1.json` 与其 `.sha256`。
- `CoreStrategyPack.json` 与其 `.sha256`——这是不改 `RangeCell.handClass` 类型的直接原因。
- `TrainingDomain` 的依赖集合：不新增对 `SessionSimulation` 的依赖。
- `layering.md` 的层图要更新，把 `SessionSimulation` 写进去；这是文档跟上现实，不是放宽规则。

## 测试策略

按缺陷类型而不是按模块组织，因为审需暴露的问题集中在几种固定的写法上：

| 缺陷类型 | 对策 |
|---|---|
| 常量实现骗过场景 | 每个 capability 至少一条断言「换一种输入会得到不同结果」；关键手那条已写进 proposal |
| 同进程测确定性 | 一律跨进程，或对照提交的黄金夹具。`hashValue` 与字典迭代序在进程内稳定，同进程重复调用测不出它们 |
| 上界无下界 | 集合断言一律给区间（3 到 5 手），不给「不超过 5」 |
| 单向断言 | 合法行动集合双向断言：集合内均被接受，集合外均被拒绝 |
| 恒真式 | 抽水恒为 0 写进 spec，让「筹码守恒」有内容；再加每层底池有赢家、发出额等于投入额、底池归零 |
| 断言被合法性蕴含 | 「没有任何一种档案在 20 个局面上给出同一个行动」不可证伪：面对下注与未面对下注的局面上没有任何单一行动同时合法，光合法性就蕴含了它。改为断言每种档案在 20 局面 × 50 种子上三类行动各出现至少一次 |
| 固定种子掩盖罕见形态 | 属性若声称对每一手成立，就要在足够多的手数上跑到它的罕见形态。「至少一名玩家增量为正」在单一种子的 30 手上是绿的，在 3000 手上有 130 手为假——全是合法的 walk 与平分，实现是对的、规格是错的 |
| 空集合满足断言 | 每条依赖夹具产出的断言前置一条「夹具确实产出了东西」的自检 |

最后一条是本次审需之后实测有效的：在 `DueNodeIDsTests` 里，`#expect(!expected.isEmpty, "夹具没有产生到期项")` 当场抓到夹具没触发到期条件——若没有它，两个空集合的 `==` 会绿着通过。

## 风险

- **`HandClass` 的 169 格往返** 是 `SpotSignature` 的地基。往返不一致会让等同判定在特定手牌上静默失效。对策：对全部 169 个取值做往返测试，不抽样。
- **`SessionSimulation` 被诱导去 import `StrategyContent`。** 实现「这个决策点可对照吗」时最省事的写法就是让引擎直接查内容。对策：把该判定完全放在 App 层，`SessionHand` 只携带 `SpotSignature`；包的 `Package.swift` 依赖列表就是防线，加一条 CI 检查断言它只依赖 `PokerCore`。
- **行为表改了忘记递增版本号。** 对策见决断 3：黄金序列夹具与版本常量绑定。
