---
name: handlab-m2b-scenario-builder-20260813-01
status: planned
---

# 执行计划：M2B 第四切片（手动场景构建器）

铁律：先写红测试再实现。依赖夹具断言前置"确有产出"自检。

## Capability 追溯
| Requirement | Scenario | Task |
|---|---|---|
| 确定性构造合法 spot 与签名 | 两个不同合法构造签名各异 | T1 |
| 确定性构造合法 spot 与签名 | 每种非法各因被拒 | T1 |
| 命中给对照与补救/未命中 uncovered | 命中给范围表权重并可补救 | T3,T4 |
| 命中给对照与补救/未命中 uncovered | 未命中记 uncovered 不编造不评分 | T3,T4 |
| 版本化保存，保存不产生事件 | 取回/重存字节不变/删除不影响其余 | T2 |
| 版本化保存，保存不产生事件 | 构造与保存不产生 TrainingEvent | T4 |

## T1 — ConstructedSpot（HandHistory）
`covers:` manual-scenario-builder
`Packages/HandHistory/Sources/HandHistory/ConstructedSpot.swift`：见 design 决断 1（校验错误枚举 Equatable、`signature()`、Codable、`canonicalJSON()`、`identity`）。
测试 `ConstructedSpotTests`（Swift Testing）：(1) 甲(offset0/Ah5h/未面对/10000)与乙(offset5/7c2d/面对1加注/1600)各自据算签名、四字段两两不同、同构造两次相等；(2) 四非法（Ah Ah / "Zx" / offset 6 / 0 筹码）各抛可判等的不同错误。**红灯**：`init` 忽略输入返回固定签名 → 甲乙不同断言红；不校验重复牌 → 重复牌断言红。

## T2 — FileConstructedSpotStore（HandHistoryPersistence）
`covers:` manual-scenario-builder
`Packages/HandHistoryPersistence/Sources/HandHistoryPersistence/FileConstructedSpotStore.swift`：mirror `FileHandLibraryStore`。
测试 `ConstructedSpotStoreTests`：保存甲取回逐字段相等；记 v1 `canonicalJSON` 字节→再存甲→版本 `[1,2]` 且 v1 字节不变；保存乙(身份不同)→删甲→剩乙内容不变。**红灯**：重存覆盖 v1 → 字节断言红；删除清库 → 剩乙断言红。

## T3 — matcher 核心 classify(signature:action:)
`covers:` manual-scenario-builder
`PokerCoach/Infrastructure/HandLab/ImportedHandContentMatcher.swift`：抽 `classify(signature:action:)`，既有 `HeroDecisionSignature` 版转调。
测试 `PokerCoachTests/ConstructedSpotMatchTests`：用 `HandLabContentFixture` 造覆盖某 (位置,面对,筹码) 且权重 6234 的内容；构造 spot 命中 → `.covered(S,6234)` 且 == `scenario.rangeWeightBasisPoints(...)`；空内容 → `.uncovered`（成对）。确认既有 `ImportedHandContentMatchTests` 仍绿（转调不改行为）。**红灯**：恒 covered → 空内容断言红。

## T4 — 构造界面 + 补救复用 + 隔离
`covers:` manual-scenario-builder
`PokerCoach/Features/HandLab/ScenarioBuilderView.swift`(+VM)：选 offset/两张牌/facing/筹码/行动 → `ConstructedSpot` → `classify(signature:action:)` → 命中显示范围表权重对照 + "练这个漏洞"（复用第三切片 `scenarioID` 训练入口）；未命中显示"无内容可对照"。保存经 `FileConstructedSpotStore`。
测试 `PokerCoachTests/ScenarioBuilderTests`：命中 spot 暴露补救 scenarioID==S、未命中不暴露；`ScenarioBuilderIsolationTests`：种非空事件存储，构造+保存不发起训练 → 事件不变；完成一道补救 → +1（普通事件）。**红灯**：保存写事件 → 不变断言红。

## T5 — UI 可达
`covers:` manual-scenario-builder
复盘→Hand Lab 增"构造场景"入口 → `ScenarioBuilderView`。`PokerCoachUITests/M2BScenarioBuilderSurfaceTests`：进入→构造一个命中 BTN 的 spot→见对照→（可选）点补救见训练界面。**红灯**：不接入→找不到入口。

## T6 — verify-m2b.sh
`covers:` 全部
UI 可达行加 `M2BScenarioBuilderSurfaceTests`；新包测试（ConstructedSpot/Store）随包循环自动跑，App 单测随 `-only-testing:PokerCoachTests` 自动跑。

## 不变量
- `SpotSignature`/matcher 判定/训练管线/契约/`ObservedHand` 黄金未变。
- `bash scripts/verify-m2b.sh` 通过。
