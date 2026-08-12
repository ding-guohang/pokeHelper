---
name: handlab-m2b-import-preview-20260812-01
status: designed
---

# 技术方案：M2B 个人牌局实验室（第一切片：牌谱导入与冲突预览）

本文只写审需留下的四个决断和它们的结构后果。proposal 已把行为规格定死，这里不复述。

## 模块结构

沿用 `SessionSimulation → SessionPersistence` 的既有形状（`docs/architecture/layering.md`）：

```text
        ┌──────────────┐
        │  PokerCore   │  Card / BBAmount / TablePosition
        └──────┬───────┘
               │ (被依赖)
        ┌──────┴───────────┐
        │   HandHistory    │ ← 新增，只依赖 PokerCore
        │  ObservedHand / PokerStarsParser / 冲突 / 规范序列化 / 身份
        └──────┬───────────┘
               │ (被依赖)
        ┌──────┴──────────────────┐
        │  HandHistoryPersistence │ ← 新增，只依赖 HandHistory + PokerCore
        │  版本化个人牌谱文件存储
        └─────────────────────────┘

App 层（唯一同时看得见解析、内容与事件存储的层）：
  PokerCoach/Features/HandLab/          导入、冲突预览、库界面
  PokerCoach/Infrastructure/HandLab/    HandImportCoordinator（持有 TrainingEventStore，只读不写）
```

`HandHistory` 不知道有文件系统、UI 或训练事件；解析是纯 `文本 → 模型 + 冲突` 的确定性函数。`HandHistoryPersistence` 看不见 `TrainingDomain`——写个人牌谱那条路径够不到 `TrainingEvent`，这是"个人牌谱不产生训练事件"的结构性一半；另一半由 App 层的隔离测试用真实协调器路径守住。

## 决断 1：统一牌谱模型 `ObservedHand` 独立定义，不复用 `SessionSimulation.PlayedHand`

架构复核确认 `PlayedHand`/`SessionHandRecord` 定长 6 人、英雄固定 0 号座、每座位底牌都被发牌填满（无"未知"）、抽水恒 0、无 ante/货币/原始文本，结构上不适配观察到的真实牌。`ObservedHand` 独立定义：

```swift
public struct ObservedHand: Hashable, Sendable, Codable {
    public let source: HandSource            // 原始文本 + 身份（SHA-256）
    public let site: PokerSite               // .pokerStars（本切片唯一取值）
    public let tableSize: Int                // 2...9
    public let buttonSeat: Int               // 0-based
    public let bigBlindCentiBB: Int          // 恒为 100（换算基准，显式记录以自证）
    public let seats: [ObservedSeat]         // 按座位号升序，count == tableSize
    public let streets: [ObservedStreet]     // preflop 起，长度 1...4
    public let result: ObservedResult        // 抽水、每座位净额、赢家
}

public struct ObservedSeat: Hashable, Sendable, Codable {
    public let seat: Int
    public let seatOffsetFromButton: Int     // TablePosition 的输入
    public let startingStackCentiBB: Int
    public let holeCards: HoleCards          // .known(Card, Card) / .unknown
}

public enum HoleCards: Hashable, Sendable, Codable {
    case known(Card, Card)
    case unknown
}

public struct ObservedStreet: Hashable, Sendable, Codable {
    public let street: Street                // PokerCore.Street（见 T1）
    public let board: [Card]                 // 张数与 street 一致
    public let actions: [ObservedAction]     // 仅"自主行动"，按发生顺序
}

public struct ObservedAction: Hashable, Sendable, Codable {
    public let seat: Int
    public let kind: ActionKind              // .fold/.check/.call/.bet/.raiseTo（不含强制下注）
    public let amountCentiBB: Int?           // nil for fold/check
}

// 盲注/ante 是强制下注，与自主行动分开，这样"翻前 6 个行动"无歧义。
public struct ForcedPost: Hashable, Sendable, Codable {
    public let seat: Int
    public let kind: ForcedPostKind          // .smallBlind/.bigBlind/.ante
    public let amountCentiBB: Int
}
public enum ForcedPostKind: String, Hashable, Sendable, Codable {
    case smallBlind, bigBlind, ante
}
```

`ObservedHand` 增一字段 `forcedPosts: [ForcedPost]`。straddle 不属这三种 kind，遇到即登记冲突（`field:"straddle"`），不建模。

`Street`（preflop/flop/turn/river，及其 `boardCardCount`）已在 `PokerCore`，但内嵌在 `SpotSignature.swift` 里（M2A 引入）。T1 已把它抽到独立文件 `PokerCore/Street.swift`，`SessionSimulation` 无需改动（它本就 `import PokerCore` 消费 `Street`）。`HandHistory` 直接用 `PokerCore.Street`。`session-*` 黄金字节不受影响（`rawValue` 未变）。

`bigBlindCentiBB` 恒为 100：模型把所有金额换算到以大盲为单位，大盲本身就是 100 centi-BB（1BB）。显式存它是为了让"换算按大盲进行"这件事在模型里自证，而不是散落在解析器里。

## 决断 2：抽水捕获、ante 捕获、straddle 判为冲突

- **抽水**：`ObservedResult.rakeCentiBB`，可非零（附录 A = 50）。这是与模拟牌最直观的区别。
- **ante**：作为 `ForcedPost(kind: .ante)` 记录（与盲注同列、不进自主行动流），`amountCentiBB` 为 ante 额。2–9 现金里 ante 少见但合法。（`ActionKind` 不含 `.post`，见决断 1。）
- **straddle / 其他 forced post 变体**：本切片不支持。解析器遇到 straddle 行登记冲突（`field: "straddle"`, `sourceLine: N`），不猜。理由：straddle 改变行动顺序与首个可操作位，正确建模需要额外规则，超出"前半段"。
- **未知行动动词**（附录 B）：登记冲突，`field` 标该动作，`sourceLine` 指该行。

## 决断 3：规范序列化 = 排序键 JSON

```swift
extension ObservedHand {
    public func canonicalJSON() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
```

与 `OpponentActionGolden.encodedJSON()` 同款。金额字段名一律带单位（`startingStackCentiBB`、`amountCentiBB`、`rakeCentiBB`、`bigBlindCentiBB`），符合精确数据规则"JSON 字段名必须显式带单位"。附录 A 的 `canonicalJSON()` 作为黄金夹具 `sample-ps-6max-nlhe.model.json` 提交；跨进程一致性由 `hand-model-writer` 可执行目标（仿 `session-transcript`）在两个进程各跑一次再比对字节守住。

## 决断 4：持久化落独立包，协调器落 App 基础设施层

- `HandHistoryPersistence`（只依赖 `HandHistory` + `PokerCore`）：`FileHandLibraryStore`，目录按牌谱身份（SHA-256）分，版本作为该目录下追加的记录。再次采纳同一身份 → 版本号 +1，旧版本文件不动。仿 `FileSessionRecordStore`。
- `HandImportCoordinator`（`PokerCoach/Infrastructure/HandLab/`）：持有 `any TrainingEventStore` 与 `FileHandLibraryStore`。采纳走它，它**从不写事件存储**——隔离断言因此是关于"一条够得到存储的路径"的断言，而不是关于一个够不到存储的类型的断言（仿 `SessionRunCoordinator` 的设计注释）。

`ObservedHand`/`HoleCards`/`ObservedResult` 与身份判定在 `HandHistory`；文件存储在 `HandHistoryPersistence`；两个新包都要显式加进 `scripts/check-package-layering.sh`（proposal 验收标准 6），否则分层规则只是声明。

## 冲突模型

```swift
public struct HandImportConflict: Hashable, Sendable, Codable {
    public let field: String       // 稳定的字段标识，如 "hero.action.preflop"、"straddle"、"amount.rake"
    public let sourceLine: Int      // 1 起的原文行号
}

public enum HandImportResult: Sendable {
    case parsed(ObservedHand, conflicts: [HandImportConflict])  // 含冲突时不可采纳
    case unsupported(reason: String, sourceLine: Int)           // 附录 C
}
```

采纳门槛：`case .parsed` 且 `conflicts.isEmpty`。用户在预览中修正一个被标字段（把附录 B 的未知动作指定为 `.raiseTo(300)`）→ 从 `conflicts` 移除该条 → 空则可采纳。"清晰输入零冲突"（附录 A）与"单字段冲突"（附录 B，与 A 仅差一行）成对，排除代理键退化。

## Capability 覆盖

| Capability | 落点 | 关键测试 |
|---|---|---|
| hand-history-import | `HandHistory`：`PokerStarsParser`、`ObservedHand`、冲突、`canonicalJSON`、`hand-model-writer` | 附录 A 解析、换算函数性（第二例）、位置导出、逐街还原、跨进程黄金、附录 C 不支持、附录 B 单字段冲突、A 零冲突、摊牌底牌双向、附录 D 非整除报冲突 |
| import-conflict-review | App `Features/HandLab` 预览 + `HandImportCoordinator` | 预览值=模型值、含冲突不可采纳、修正后可采纳、冲突定位到字段+行 |
| personal-hand-library | `HandHistoryPersistence`：`FileHandLibraryStore` + App 隔离 | 取回相等、重采纳保留旧版本、删除不影响其余、隔离（库+1 且事件存储不变） |

## 影响与不变量

### 新增
- `Packages/HandHistory/`、`Packages/HandHistoryPersistence/`。
- `PokerCoach/Features/HandLab/`、`PokerCoach/Infrastructure/HandLab/`。
- `scripts/verify-m2b.sh`（仿 `verify-m2a.sh`：包测试 + App 单测 + UI 可达 + 分层门禁 + 每道门禁的反向失败路径 + 黄金字节比对 + 跑通 verify-m1a/m1c/m2a 兜底）。

### 顺带改动（唯一动到既有代码处）
- `Street` 从 `SessionSimulation` 下沉到 `PokerCore`，`SessionSimulation` 改为引用 PokerCore 的 `Street`。语义不变，`session-*` 黄金不受影响；单列一步并跑 `verify-m2a.sh` 兜底。

### 必须不变
- `Contracts/training-event-upload-v1.json` 与其 `.sha256`（本切片不产生事件）。
- `CoreStrategyPack.json` 与其 `.sha256`（不碰内容）。
- `SpotSignature`/`session-*` 黄金字节（`Street` 下沉不改 `rawValue`）。

## 风险
- **`Street` 下沉波及 `SessionSimulation`** → 先做这一步并立即跑 `verify-m2a.sh`，确认零行为变化再继续。
- **PokerStars 格式变体** → 只认 2–9 NLHE 现金；header/桌型/盲注行任一不符即 `.unsupported`，附录 C 守住。
- **解析器静默猜测** → 附录 A/B 仅差一行的成对断言 + 附录 D 非整除报冲突；proxy 键无法同时通过。
- **隔离断言退化** → 协调器真持有事件存储，隔离场景加"库 +1"。

## 测试策略
- 包测试 Swift Testing；App 单测 XCTest；UI 可达 XCUITest。
- 附录 A–D 文本与附录 A 的黄金 `.model.json` 随包提交到 `HandHistory/Tests/Fixtures/`。
- 跨进程确定性用 `hand-model-writer` 双进程比对，绝不用同进程重复调用。
- 每条依赖夹具的断言前置"夹具确实产出了东西"的自检（仿 M1C/M2A 的空集防护）。

## 附录 A（钉死的样例，实现须逐字使用）

`Tests/Fixtures/sample-ps-6max-nlhe.txt`：

```
PokerStars Hand #240000000001:  Hold'em No Limit ($0.50/$1.00 USD) - 2026/01/15 20:00:00 ET
Table 'Andromeda' 6-max Seat #1 is the button
Seat 1: Hero ($100 in chips)
Seat 2: Villain2 ($100 in chips)
Seat 3: Villain3 ($100 in chips)
Seat 4: Villain4 ($100 in chips)
Seat 5: Villain5 ($100 in chips)
Seat 6: Villain6 ($100 in chips)
Villain2: posts small blind $0.50
Villain3: posts big blind $1
*** HOLE CARDS ***
Dealt to Hero [Ah Kd]
Villain4: folds
Villain5: folds
Villain6: folds
Hero: raises $2 to $3
Villain2: folds
Villain3: calls $2
*** FLOP *** [Ac 7h 2s]
Villain3: checks
Hero: bets $4
Villain3: calls $4
*** TURN *** [Ac 7h 2s] [Td]
Villain3: checks
Hero: checks
*** RIVER *** [Ac 7h 2s Td] [9c]
Villain3: checks
Hero: bets $8
Villain3: folds
Uncalled bet ($8) returned to Hero
Hero collected $14 from pot
*** SUMMARY ***
Total pot $14.50 | Rake $0.50
```

**期望模型（T3/T4/T5/T6 据此断言）：**

- `tableSize == 6`，按钮在 1 号座；`bigBlindCentiBB == 100`；每座起始筹码 `10000`。
- 座位按座号升序，`seatOffsetFromButton` 依次 `0..5`；`TablePosition` 标签依次 `[BTN, SB, BB, UTG, HJ, CO]`；英雄（1 号座）偏移 `0`（BTN），`holeCards == .known(Ah, Kd)`；2–6 号座 `holeCards == .unknown`。
- `forcedPosts`：`[{seat2, .smallBlind, 50}, {seat3, .bigBlind, 100}]`（不计入自主行动）。
- 自主行动，按街：
  - preflop（6）：`seat4 fold, seat5 fold, seat6 fold, seat1 raiseTo 300, seat2 fold, seat3 call 300`
  - flop（3），board `[Ac,7h,2s]`：`seat3 check, seat1 bet 400, seat3 call 400`
  - turn（2），board 追加 `Td`：`seat3 check, seat1 check`
  - river（3），board 追加 `9c`：`seat3 check, seat1 bet 800, seat3 fold`
  - 自主行动总数 `14`。
- `result.rakeCentiBB == 50`。
- **附录 B** = 上文**仅**把 `Hero: raises $2 to $3` 一行改为 `Hero: sprais $2 to $3`（无法识别的动词），其余逐字节相同 → 恰一条冲突，`sourceLine` 指向该行。
- **附录 C** = 一段 header 为 `Tournament` 的 PokerStars 锦标赛牌谱 → `.unsupported`。
- **附录 D** = 盲注 `$0.03/$0.06`（SB 50、BB 100 均整除），抽水 `$0.01`（`100/6` 无法整除为整数 centi-BB）→ 抽水金额行登记冲突。（$0.05 大盲下任何整分金额都能整除，凑不出非整除案例，故用 $0.06 大盲。）

`call 300` 记录该玩家该街投入后的到位额（BB 已投 100，跟注补到 300 与加注一致），与 `SessionSimulation` 的到位额约定一致；实现按此口径，`canonicalJSON` 的黄金以实现稳定后的实际字节提交。
