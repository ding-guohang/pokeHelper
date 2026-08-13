---
name: handlab-m2b-scenario-builder-20260813-01
status: designed
---

# 技术方案：M2B 第四切片（手动场景构建器）

审需已把行为定死；这里写结构与决断。

## 结构
```
PokerCore: SpotSignature/HandClass/TablePosition/FacingAction/StackBucket/Card/DecisionAction
   │
HandHistory (仅依赖 PokerCore):
   ConstructedSpot  ← 新增：位置/两张牌/facing/筹码/行动 → signature()；自校验；Codable+canonicalJSON+identity
   │
HandHistoryPersistence (依赖 HandHistory):
   FileConstructedSpotStore  ← 新增：仿 FileHandLibraryStore，按 identity 分目录、版本追加
   │
App (Infrastructure/HandLab):
   ImportedHandContentMatcher: 抽出 classify(signature:action:) 核心（既有 HeroDecisionSignature 版转调）
App (Features/HandLab):
   场景构造界面 + 结果视图（覆盖对照 + 命中则复用第三切片补救入口）
```

## 决断
1. **ConstructedSpot 在 HandHistory**：`init(heroSeatOffsetFromButton:holeCardCodes:facing:effectiveStackCentiBB:action:)`（收两张牌的字符串码），校验顺序：牌可解析（否则 `.unparseableCard`）→ 两张互不相同（否则 `.duplicateCards`）→ 筹码为正（否则 `.nonPositiveStack`）→ 座位 `TablePosition(tableSize:6,heroSeatOffsetFromButton:)` 不抛（否则 `.seatOutOfRange`）。校验错误枚举 `ConstructedSpotError: Equatable`。`signature() -> SpotSignature`（street .preflop，各分量据算）。`Codable`；`canonicalJSON()`（sortedKeys/withoutEscapingSlashes，金额字段带单位）；`identity = SHA-256(canonicalJSON)`（复用 CryptoKit，仿 HandSource）。
2. **matcher 核心**：`func classify(signature: SpotSignature, action: DecisionAction) -> NodeCoverage`；既有 `classify(_ sig: HeroDecisionSignature)` 改为转调它（传 `sig.signature`、`decisionAction(from: sig.action)`）。翻前 guard 仍在核心里，构造 spot 恒 preflop 通过。
3. **存储**：`FileConstructedSpotStore`（actor，mirror `FileHandLibraryStore`）：`save/spots/spot(identity:)/versions(identity:)/version(identity:_:)/delete(identity:)`。
4. **补救复用**：命中 `covered(scenarioID,…)` 直接把 scenarioID 交给第三切片已有的 `makeRemediationSession`/训练入口——同一路径，普通 TrainingEvent。

## Capability 覆盖
| Capability | 落点 | 关键测试 |
|---|---|---|
| manual-scenario-builder | HandHistory `ConstructedSpot`、HandHistoryPersistence 存储、App matcher 核心+构造界面 | 两合法构造签名各异/确定性；四非法各因；covered=6234 据表/uncovered 成对；版本字节不变/双删；构造保存不产生事件；UI 可达 |

## 不变量
- `SpotSignature`/matcher 判定/训练管线/契约语义未变；matcher 抽核是加法（既有入口转调，行为不变）。
- `ObservedHand` 及其黄金未变；`check-package-layering.sh` 无需改（新类型留在两包内）。
- `bash scripts/verify-m2b.sh` 通过（含 m1a/m1c/m2a）。
