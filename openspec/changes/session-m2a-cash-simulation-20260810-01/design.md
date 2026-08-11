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
| `.allIn` | 该手出现过全下 | 4000 + 底池 centiBB |
| `.bigSwing` | 英雄筹码变化绝对值 ≥ 20BB（2000 centiBB） | 3000 + 变化绝对值 centiBB |
| `.bigPot` | 底池属于该 Session 底池最大的 5 手 | 2000 + 底池 centiBB |
| `.trainable` | 该手翻前命中已安装内容 | 1000 |

- 一手可能满足多个判据，取**分数最高**的那个作为展示原因。
- 取分数前 5，且至少取 3（不足 3 手时取全部）。
- 并列时按手牌序号升序——确定性 tie-break，不依赖字典序或 `hashValue`。

「艰难决策」被删掉了：它需要策略数据来判定难度，而 Session 手牌按设计约束 1 没有策略数据。留着它就是留一个算不出来的判据。

## 决断 5：频率报告的基准按 (位置, 面对情形) 取键

产品最高宗旨要求在诚实之外兼顾实战训练。职业工作流的关键一步是聚合频率而非单手，所以 M2A 加了 `session-frequency-report`。

两个必须写死的判据，都是核对内容包时发现的：

**基准的键是 (位置, 面对情形)，不是位置。** 核对 `CoreStrategyPack.json` 时发现 offset 5（CO）下有两个场景：`rfi-co` 未面对下注、`vs3bet-co-vs-btn` 面对 3bet。只按位置取基准会把 24.86% 和 9.05% 混成一个没有含义的数。这也正是 `SpotSignature.facing` 分量存在的理由，两处用同一个键。

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

**样本阈值 30 次机会。** 6-max 一个位置每 6 手轮到一次，60 手 Session 只给约 10 次机会；p≈0.46 时 n=10 的标准误约 ±16 个百分点。低于阈值只报计数不下结论，且跨 Session 累计。这不是保守，是不教用户读噪声。

## 影响与不变量

### 新增

- `Packages/SessionSimulation/`——只依赖 `PokerCore`。发牌、对手行为表、Session 推进、结算。
- `PokerCore` 新增 `SpotSignature`、`HandClass`、`Street`、`FacingAction`、`StackBucket`。
- `PokerCoach/Features/Session/`——Session 界面、关键手复盘与频率报告。对照、「重打」与基准计算的桥接都在这一层，因为只有它同时看得到 `SessionSimulation` 与 `StrategyContent`。
- `PokerCoach/Infrastructure/Session/`——Session 记录持久化。

### 顺带偿还

`Packages/TrainingDomain/Sources/TrainingDomain/FileTrainingEventStore.swift` 在这一步搬到 `PokerCoach/Infrastructure/`。它是具体存储实现，`layering.md` 第 3 条明确禁止领域包依赖数据库实现；协议 `TrainingEventStore` 留在领域包。见 [已知缺口](../../../docs/architecture/known-gaps.md)——那里记的「M2A 落 Session 记录持久化时一并做」就是这里。

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
| 恒真式 | 抽水恒为 0 写进 spec，让「筹码守恒」有内容；再加赢家增量为正、底池归零 |
| 空集合满足断言 | 每条依赖夹具产出的断言前置一条「夹具确实产出了东西」的自检 |

最后一条是本次审需之后实测有效的：在 `DueNodeIDsTests` 里，`#expect(!expected.isEmpty, "夹具没有产生到期项")` 当场抓到夹具没触发到期条件——若没有它，两个空集合的 `==` 会绿着通过。

## 风险

- **`HandClass` 的 169 格往返** 是 `SpotSignature` 的地基。往返不一致会让等同判定在特定手牌上静默失效。对策：对全部 169 个取值做往返测试，不抽样。
- **`SessionSimulation` 被诱导去 import `StrategyContent`。** 实现「这个决策点可对照吗」时最省事的写法就是让引擎直接查内容。对策：把该判定完全放在 App 层，`SessionHand` 只携带 `SpotSignature`；包的 `Package.swift` 依赖列表就是防线，加一条 CI 检查断言它只依赖 `PokerCore`。
- **行为表改了忘记递增版本号。** 对策见决断 3：黄金序列夹具与版本常量绑定。
