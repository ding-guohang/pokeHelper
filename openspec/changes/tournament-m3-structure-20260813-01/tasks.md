---
name: tournament-m3-structure-20260813-01
status: planned
---

# 执行计划：M3 第一切片（盲注结构与筹码模型）

铁律：先写红测试再实现。

## Capability 追溯
| Requirement | Scenario | Task |
|---|---|---|
| 盲注级别表被校验且按手数递进 | 合法接受+级别查询(含两边界) | T1 |
| 盲注级别表被校验且按手数递进 | 七类非法各因被拒 | T1 |
| 锦标赛筹码整数、有效深度据算 | 同筹码更高级别更小深度 | T2 |
| 锦标赛筹码整数、有效深度据算 | 向下取整、0→0 | T2 |

## T1 — TournamentEngine 包 + BlindSchedule
`covers:` tournament-structure
新增 `Packages/TournamentEngine/`（`Package.swift` 仿 `Packages/SessionSimulation/Package.swift`，只依赖 `../PokerCore`，warnings-as-errors + strict-concurrency=complete）。
`Sources/TournamentEngine/BlindLevel.swift`：`BlindLevel`（见 design）。`BlindSchedule.swift`：throwing init 校验 + `BlindScheduleError`(Equatable，7 例) + `level(atHandIndex:handsPerLevel:)`（precondition handIndex>=0/handsPerLevel>=1，末级 clamp）。
测试 `BlindScheduleTests`（Swift Testing）：(1) 三级合法结构接受，手 0/9→L1、10→L2、19→L2、20→L3、100→L3（末级 clamp）；(2) 七类非法各抛可判等的不同 error，两两 `!=`。**红灯**：校验漏 `BB==0` → BB=0 断言红；level 查询恒返回 L1 → 边界断言红。

## T2 — effectiveBigBlinds
`covers:` tournament-structure
`Sources/TournamentEngine/TournamentChips.swift`：`func effectiveBigBlinds(chips: Int, level: BlindLevel) -> Int = chips / level.bigBlindChips`（precondition chips>=0）。
测试 `EffectiveDepthTests`：3000 在 L1(BB100)→30、在 L3(BB200)→15（成对，防忽略级别）；250 在 BB100→2（向下取整，非 3）；0→0。**红灯**：`chips/100` 硬编码忽略 level → 15 断言红。

## T3 — 分层门禁 + 文档
`covers:` 结构不变量
`scripts/check-package-layering.sh` 加 `echo "==> TournamentEngine may only see PokerCore"; check_manifest TournamentEngine PokerCore; check_imports TournamentEngine PokerCore`。更新 `docs/architecture/layering.md` 层图与依赖清单纳入 `TournamentEngine`。
**反向失败路径**：临时给 `TournamentEngine/Package.swift` 加对 `SessionSimulation` 的依赖，跑门禁必须红；还原。

## 不变量
- `TournamentEngine` 只依赖 PokerCore；不改现金评分。
- `swift test --package-path Packages/TournamentEngine` 绿；`bash scripts/check-package-layering.sh` 绿（含新条目）。
