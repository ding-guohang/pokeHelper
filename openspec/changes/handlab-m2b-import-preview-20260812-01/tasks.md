---
name: handlab-m2b-import-preview-20260812-01
status: planned
---

# 执行计划：M2B 个人牌局实验室（第一切片：牌谱导入与冲突预览）

铁律沿用：先写测试并**观察它红**，再写实现。没见过红的测试与没有测试等价。每条依赖夹具的断言前置一条"夹具确实产出了东西"的自检。

## Capability 追溯

| Capability | Requirement | Scenario | Task |
|---|---|---|---|
| hand-history-import | 确定性解析为统一模型 | 附录 A 解析出与输入相符的模型 | T3 |
| hand-history-import | 确定性解析为统一模型 | 换算是大盲的函数 | T5 |
| hand-history-import | 确定性解析为统一模型 | 位置由按钮导出 | T3 |
| hand-history-import | 确定性解析为统一模型 | 逐街行动完整还原 | T3 |
| hand-history-import | 确定性解析为统一模型 | 跨进程规范序列化逐字节一致且等于黄金 | T6 |
| hand-history-import | 无法解析登记为冲突 | 附录 C 不受支持 | T4 |
| hand-history-import | 无法解析登记为冲突 | 附录 B 单字段冲突 | T4 |
| hand-history-import | 无法解析登记为冲突 | 附录 A 零冲突（成对） | T4 |
| hand-history-import | 无法解析登记为冲突 | 摊牌底牌读出/未摊记未知 | T4 |
| hand-history-import | 无法解析登记为冲突 | 非整除报冲突而非四舍五入 | T4 |
| import-conflict-review | 预览值等于模型值 | 预览值=模型值 | T10 |
| import-conflict-review | 预览值等于模型值 | 含冲突不可采纳 | T10 |
| import-conflict-review | 预览值等于模型值 | 修正后可采纳 | T10 |
| import-conflict-review | 预览值等于模型值 | 冲突定位到字段+行 | T10 |
| personal-hand-library | 版本化个人资源本地保存 | 取回与采纳者相等 | T7 |
| personal-hand-library | 版本化个人资源本地保存 | 重采纳保留旧版本 | T8 |
| personal-hand-library | 版本化个人资源本地保存 | 删除不影响其余 | T8 |
| personal-hand-library | 版本化个人资源本地保存 | 导入采纳不产生 TrainingEvent | T9 |

## 里程碑 A：PokerCore 地基

### T1 — `Street` 下沉到 PokerCore
`covers:` 全部（签名/模型的地基）

`Street`（preflop/flop/turn/river + `boardCardCount`）目前在 `SessionSimulation`。`HandHistory` 只能依赖 PokerCore，故把 `Street` 移到 `Packages/PokerCore/Sources/PokerCore/Street.swift`，`SessionSimulation` 改为引用 PokerCore 的 `Street`（删除本地定义，`import PokerCore` 已有）。

- 移动定义，不改 `rawValue`、不改 `boardCardCount` 语义。
- 若 `SessionSimulation` 有 `Street` 的测试，一并迁到 `PokerCoreTests` 或保留引用。

**红灯观察**：把 `Street.turn.boardCardCount` 改为 4→3 之类，`PokerCoreTests` 的往返/张数测试变红。
**兜底**：`bash scripts/verify-m2a.sh` 全绿（下沉零行为变化，`session-*` 黄金字节不变）。

## 里程碑 B：HandHistory 包

### T2 — 建包 + `ObservedHand` 模型 + `canonicalJSON`
`covers:` hand-history-import

新增 `Packages/HandHistory/`，`Package.swift` 只依赖 `../PokerCore`（仿 `SessionPersistence/Package.swift` 的 manifest 与 `-warnings-as-errors -strict-concurrency=complete`）。

新增类型（见 design.md）：`ObservedHand`、`ObservedSeat`、`HoleCards`、`ObservedStreet`、`ObservedAction`、`ActionKind`、`ObservedResult`、`HandSource`、`PokerSite`、`HandImportConflict`、`HandImportResult`。全部 `Sendable, Hashable, Codable`。

先写测试 `CanonicalSerializationTests`：
1. `金额字段名带单位` — 对一个手搭的 `ObservedHand`，`canonicalJSON()` 的字符串含 `startingStackCentiBB`/`amountCentiBB`/`rakeCentiBB`/`bigBlindCentiBB`，不含无单位的 `stack`/`amount`。
2. `键有序且稳定` — 同一模型两次 `canonicalJSON()` 逐字节相同。
3. `身份是原文的规范化 SHA-256` — `HandSource(rawText:)` 对 `"a\r\nb"` 与 `"a\nb"` 得到相同身份（行尾规范化），对不同文本得到不同身份。

**红灯观察**：把 `canonicalJSON` 的 `.sortedKeys` 去掉 → 测试 2 在字段顺序不稳定的模型上可红（用含多字段嵌套的夹具）。

### T3 — `PokerStarsParser`：解析附录 A
`covers:` hand-history-import / 附录 A 解析、位置导出、逐街还原

提交夹具 `Tests/Fixtures/sample-ps-6max-nlhe.txt`（附录 A：6-max、$0.50/$1、按钮 1 号座、英雄 `Ah Kd`、打到河牌英雄下注被弃、Summary 抽水 $0.50）。

先写测试 `PokerStarsParseTests`：
1. `附录A解析出与输入相符的模型` — 断言 tableSize==6、hero offset==0、hero holeCards==`.known(Ah,Kd)`、bigBlindCentiBB==100、hero 起始筹码==10000、hero 翻前 `.raiseTo(300)`、翻牌 `.bet(400)`、翻牌 board==`[Ac,7h,2s]`、turn 追加 `Td`、river 追加 `9c`、rakeCentiBB==50。
2. `位置由按钮导出` — 六座位 `TablePosition(tableSize:6, heroSeatOffsetFromButton:offset).label` 依座位序为 `[BTN,SB,BB,UTG,HJ,CO]`。
3. `逐街行动完整还原` — 翻前 actions.count==6 且序列匹配 `[UTG fold, HJ fold, CO fold, BTN raiseTo 300, SB fold, BB call]`；river actions==`[BB check, BTN bet 800]`；全手行动总数==12。
4. 自检：`#expect(!model.streets.isEmpty)`。

**红灯观察**：把金额换算写成"直接取美元整数"→ 起始筹码断言（10000 vs 100）红；把 board 张数写死 `[0,3,4,5]` 不读牌 → board 具体牌断言红。

实现 `PokerStarsParser.parse(_ text: String) -> HandImportResult`：分行→识别 header（stakes、桌型、按钮座）→ seats→blinds/antes(post)→ HOLE CARDS→逐街 actions 与 board→ SUMMARY(rake)。金额 `centiBB = round?`——**不 round**：`amountCents * 100` 必须能被 `bigBlindCents` 整除，否则登记冲突（T4）。

### T4 — 冲突与不支持
`covers:` hand-history-import / 附录 C、附录 B、附录 A 零冲突、摊牌底牌、非整除

提交夹具：附录 B（`sample-ps-6max-nlhe-unknown-action.txt`，仅改英雄翻前动作动词一行）、附录 C（`sample-ps-tournament.txt`）、附录 D（`sample-ps-6max-rake-fraction.txt`，盲注 $0.03/$0.06、抽水 $0.01 不整除）。

先写测试 `HandImportConflictTests`：
1. `附录C不受支持` — `parse` 返回 `.unsupported(reason:, sourceLine:)`，`sourceLine` 指向锦标赛标识行；**不**返回 `.parsed`。
2. `附录B单字段冲突` — `.parsed(_, conflicts)`，`conflicts.count==1`，其 `sourceLine` == 附录 B 被改那一行的行号；该动作不被赋值。
3. `附录A零冲突（成对）` — `.parsed(_, conflicts)`，`conflicts.isEmpty`。断言注释点明与 2 成对：A、B 仅差一行。
4. `摊牌底牌双向` — 附录 A：hero==`.known(Ah,Kd)`（"恒未知"实现红）；未摊对手==`.unknown`（"照抄英雄牌"实现红）。
5. `非整除报冲突` — 附录 D 中不整除金额那行 → `conflicts` 含指向该行的 `field: "amount.*"`；模型无被 round 的值。
6. `straddle报冲突` — 一段含 straddle 行的构造文本 → `conflicts` 含 `field:"straddle"`。

**红灯观察**：让冲突检测"恒报一条" → 附录 A 零冲突断言红；"恒不报" → 附录 B、附录 D 断言红。二者证明检测不是常量。

### T5 — 换算是大盲的函数
`covers:` hand-history-import / 换算函数性

先写测试 `AmountScalingTests.换算按各自大盲进行`：
- 取附录 A 与一段"大盲 $2、所有金额等比翻倍、其余逐字节相同"的文本（测试内由附录 A 文本做字符串替换生成，或提交为夹具）。
- 断言两者 hero 起始筹码均==10000、bigBlindCentiBB 均==100。
- 断言硬编码常量实现会在其一失败（通过两个不同美元额→同一 centi-BB 说明换算依赖声明的大盲）。

**红灯观察**：把换算写成 `dollars * 100`（无视大盲）→ $2 那份的起始筹码算成 10000×? 与 100BB 不符，红。

### T6 — 跨进程规范序列化黄金
`covers:` hand-history-import / 跨进程逐字节 + 黄金

新增可执行目标 `hand-model-writer`（仿 `session-transcript`）：读 `--fixture <path>`，`parse` 成功则打印 `ObservedHand.canonicalJSON()`，否则 stderr 报不支持并非零退出。加入 `Package.swift` 的 executableTarget 与 testTarget 依赖。

提交黄金夹具 `Tests/Fixtures/sample-ps-6max-nlhe.model.json`（附录 A 的 `canonicalJSON()`）。

先写测试 `CrossProcessDeterminismTests`：
1. `两个进程解析附录A得到逐字节相同的规范序列化` — 用 `Process`（macOS 测试，仿 SessionPersistence 的 `WriterBinary`）跑 `hand-model-writer` 两次，比对 stdout 字节相等。
2. `规范序列化等于提交的黄金` — stdout 字节 == 黄金夹具字节；不等时报首个差异位置并提示重新生成命令。

**红灯观察**：把黄金夹具改一个字节 → 测试 2 红并打印差异。

## 里程碑 C：HandHistoryPersistence 包

### T7 — 建包 + 采纳与取回
`covers:` personal-hand-library / 取回相等

新增 `Packages/HandHistoryPersistence/`，`Package.swift` 依赖 `../PokerCore` + `../HandHistory`。`FileHandLibraryStore`（actor 或 `@MainActor`，仿 `FileSessionRecordStore`）：`accept(_ hand: ObservedHand)`、`hands()`、`hand(identity:)`、`versions(identity:)`、`delete(identity:)`。目录按身份分，版本作追加记录。

先写测试 `HandLibraryStoreTests`：
1. `采纳后取回与采纳者逐字段相等` — `accept(A)` 后 `hand(identity: A.identity)` 的模型 `== A`，原文逐字节相同，身份 == A 原文规范化 SHA-256。
2. 自检：采纳前库为空、采纳后 count==1。

**红灯观察**：让 `hand(identity:)` 返回固定 stub → 相等断言红。

### T8 — 版本化与删除
`covers:` personal-hand-library / 重采纳保留旧版本、删除不影响其余

先写测试：
1. `再次采纳同一身份保留旧版本` — `accept(A)`；`accept(A)` 再次 → `versions(A.identity)` == `[1,2]`；版本 1 的 `canonicalJSON()` 与首次逐字节相同（未覆盖）。
2. `删除一手不影响其余` — `accept(A)`、`accept(B)`（B 身份不同）；`delete(A.identity)` → `hands()` 恰剩 B 且内容不变；A 与其原文移除。

**红灯观察**：把再次采纳写成覆盖（写回同一文件）→ 版本 1 字节断言红；把 delete 写成清库 → "剩 B"断言红。

## 里程碑 D：App 层

### T9 — `HandImportCoordinator` 与事件隔离
`covers:` personal-hand-library / 导入采纳不产生 TrainingEvent

`PokerCoach/Infrastructure/HandLab/HandImportCoordinator.swift`（`@MainActor`）：持有 `any TrainingEventStore` 与 `FileHandLibraryStore`，暴露 `importAndAccept(text:) -> ...`。**从不写事件存储**（设计注释仿 `SessionRunCoordinator`）。

先写测试 `PokerCoachTests/HandImportEventIsolationTests`（XCTest，仿 `SessionEventIsolationTests`）：
- 种入非空事件存储（≥1 条），记 before。
- 走协调器 `importAndAccept(附录A文本)`。
- 断言：采纳成功且 `libraryStore.hands().count` 增加 1（证明导入确实发生）；事件存储条数与内容 == before（不变）。
- 拒绝空存储捷径（种非空）与"什么都没做"捷径（断言库 +1）。

**红灯观察**：让协调器顺手写一条事件 → 事件不变断言红；让 `importAndAccept` 空实现 → 库 +1 断言红。

### T10 — 冲突预览与采纳门槛
`covers:` import-conflict-review 全部

`PokerCoach/Features/HandLab/HandImportPreviewPresentation.swift`（无业务计算，仅把 `ObservedHand` 映射为可显示值）+ `HandImportViewModel`（组合协调器/解析）。

先写测试 `PokerCoachTests/HandImportPreviewTests`：
1. `预览值等于模型值` — 附录 A：预览的每座位位置、BB 筹码、逐街行动、公共牌、结果逐项 == 模型对应值（hero 位置 BTN、起始 100BB、翻牌 `Ac 7h 2s`）。
2. `含未解决冲突不可采纳` — 附录 B 解析结果：`canAccept==false`，暴露冲突字段+行；库 count 不变。
3. `修正后可采纳` — 对附录 B 的冲突动作指定 `.raiseTo(300)` → 冲突清空、`canAccept==true`、采纳后库 +1。
4. `冲突定位到字段+行` — 构造两冲突牌谱 → 预览列出恰两条各带行号；附录 A 在同视图显示零条。

**红灯观察**：让 `canAccept` 恒 true → 断言 2 红；预览渲染空占位 → 断言 1（值相等）红。

### T11 — UI 可达
`covers:` import-conflict-review / personal-hand-library（真实构建可达）

`PokerCoach/Features/HandLab/` 的导入入口、预览、库列表 View；接入导航（`adaptive-native-shell` 的四标签或设置入口，按现有 shell 结构挂载）。

先写 `PokerCoachUITests/M2BSurfaceTests`：从 App 启动导航到"牌局实验室"，粘贴/载入附录 A 文本，看到标准化预览，采纳后在库中看到该手。

**红灯观察**：不接入导航 → UI 测试找不到入口，红。

## 里程碑 E：收口

### T12 — 分层门禁纳入新包
`covers:` 结构不变量

`scripts/check-package-layering.sh` 增加显式条目：`HandHistory` 只可见 `PokerCore`；`HandHistoryPersistence` 只可见 `HandHistory` 与 `PokerCore`，且看不见 `TrainingDomain`/`SessionSimulation`。

**反向失败路径**：临时给 `HandHistory/Package.swift` 加一条对 `SessionSimulation` 的依赖，跑门禁必须红；还原。

### T13 — `project.yml` 接入新包
`covers:` 可达性/构建

`project.yml` 的 App target 增加对 `HandHistory`、`HandHistoryPersistence` 的依赖；`xcodegen generate`；跑 `bash scripts/check-project-shape.sh`。

### T14 — `scripts/verify-m2b.sh`
`covers:` 全部

仿 `verify-m2a.sh`：生成工程 → 各包测试（含 HandHistory/HandHistoryPersistence）→ App 单测（含隔离/预览）→ `M2BSurfaceTests` 可达 → 分层门禁 + 反向失败路径 → 黄金 `.model.json` 字节比对 → 跑通 `verify-m1a.sh`/`verify-m1c.sh`/`verify-m2a.sh` 兜底。每道门禁必须有实测失败路径。

## 不变量（每个里程碑结束时复验）

- `Contracts/training-event-upload-v1.sha256` 未变更（本切片不产生事件）。
- `CoreStrategyPack.json` 与其 `.sha256` 未变更。
- `SessionSimulation` 的 `session-*` 黄金字节未变更（`Street` 下沉不改 `rawValue`）。
- `HandHistory` 不依赖 PokerCore 以外的项目包；`HandHistoryPersistence` 看不见 `TrainingDomain`。
- `bash scripts/verify-m2a.sh` 仍通过。
