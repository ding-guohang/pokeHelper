---
name: tournament-content-promotion-20260814-01
created: 2026-08-14
status: review_passed
---

# 需求提案：锦标赛内容晋升为 reviewed（具名审核 + 只重标不改内容）

## Why

首批 HU push/fold 内容以 `unverifiedDraft` 交付,并已备齐客观证据(独立 equity 重算逐项 0
偏差、可利用度交叉核对为 0、逐位可复现)。缺的是一个**故意的、证据门控的晋升路径**:
在**具名人工签署**后把内容标为 `reviewed`(才能上 store),且晋升**只改 manifest、绝不
改一个频率/EV**。这条路径与自动导入(永远只产 `unverifiedDraft`)分开,确保生成方不能
给自己盖章。

## What Changes

### New Capabilities

- `tournament-content-promotion` — `promote-tournament-packs.py`:校验完整审核记录(具名
  审核人、时间、批准、三项证据阈值),用**新内容版本**把导出重导入为 `reviewed` +
  `origin=solver` + 审核人/时间,并做黄金回归(reviewed 包的策略内容必须与 `unverifiedDraft`
  基线逐字节相等,仅 manifest 变化);任一缺失/不一致均失败关闭、不产出。

### Modified Capabilities

无。`strategy-import` 移除了"锦标赛内容必须 unverifiedDraft"的冗余守卫——`reviewed` 的
审核人要求由校验器强制,自动导入包装器不暴露 `reviewed`,`reviewed` 只经本晋升路径产出。

## Capabilities Detail

### Capability: tournament-content-promotion

#### Requirement: 只有完整审核记录才可晋升

The system SHALL promote tournament content to `reviewed` only when a review record
supplies a named reviewer, an ISO8601 review timestamp, an explicit `approved`
decision, and evidence meeting the objective thresholds (independent equity recompute
delta ≤ 1e-6, exploitability cross-check ≤ 0.02 BB, byte-reproducible), and SHALL fail
closed listing every missing item otherwise, writing nothing.

##### Scenario: 缺审核人/未批准/证据不达标被拒

- GIVEN 审核记录缺具名审核人,或 `decision != approved`,或 `exploitabilityMaxBB` 超阈值,
  或 `reproducible != true`
- WHEN 请求晋升
- THEN 以列出缺失项的错误失败,不产出任何 reviewed 包或校验和

##### Scenario: 完整记录通过校验

- GIVEN 审核记录含具名审核人、ISO8601 时间、`approved`、三项证据均达阈值
- WHEN 校验审核记录
- THEN 返回审核人与时间,校验通过

#### Requirement: 晋升只重标不改内容

The system SHALL, on a valid promotion, produce one `reviewed` pack per depth with a
new content version, `origin=solver`, and the reviewer/time recorded, and SHALL verify
by golden regression that each reviewed pack's strategy content (range cells, options,
explanations) is byte-identical to the `unverifiedDraft` baseline, failing if any
frequency or EV changed.

##### Scenario: 晋升产出 reviewed 且策略与基线逐字节一致

- GIVEN 完整审核记录、20 个导出、`unverifiedDraft` 基线包、新内容版本
- WHEN 执行晋升
- THEN 产出 20 个包,每个 `reviewStatus=reviewed`、`origin=solver`、带具名审核人/时间、
  新内容版本
- AND 每个 reviewed 包去掉 manifest 后与对应基线包逐字节相等(策略未被改动)
- AND 生成校验和与晋升记录;原子发布,失败不留残件

##### Scenario: 晋升试图改动策略被拒

- GIVEN reviewed 包与基线在任一手频率/EV 上不一致
- WHEN 黄金回归比对
- THEN 晋升失败并指出发生改动的深度,不发布

## Impact

- **Code:** 新增 `Content/promote-tournament-packs.py` + `Content/tournament/tests/test_promote_tournament_packs.py`;
  改 `Packages/StrategyTooling/Sources/strategy-import/main.swift`(移除冗余锦标赛守卫)。
- **Interfaces:** 新增本机晋升命令;不改运行时、不动四标签、不改契约。晋升产出的 reviewed
  内容是否随包/上架是后续构建配置决策,不在本切片。
- **Dependencies:** 复用 `strategy-import` 与 `StrategyPackValidator`(reviewed 需审核人)。

## Risks

- **生成方自我背书**:→ 晋升与自动导入分离;晋升需完整审核记录(具名 + 三项证据),校验器
  再要求 reviewed 必带审核人。
- **晋升偷改内容**:→ 黄金回归逐字节比对 reviewed 与 unverifiedDraft 基线,只允许 manifest 变化。
- **移除守卫削弱防线**:→ 校验器仍拒绝无审核人的 reviewed;自动包装器无 `reviewed` 入口;
  StrategyTooling 25 测试仍绿。

## Non-Goals

- 不替任何人做审核决定或代填审核记录(签署是人的职责)。
- 不把 reviewed 内容自动打进 store 或改变构建配置(后续)。
- 不改策略数字、不新增内容。

## Acceptance Criteria

1. 缺审核人/未批准/证据不达标/不可复现 → 晋升失败并列出缺失;不产出。
2. 完整记录 → 20 个 reviewed 包(`origin=solver` + 审核人/时间 + 新版本),去 manifest 后与
   `unverifiedDraft` 基线逐字节一致;有校验和与晋升记录。
3. 策略被改动 → 黄金回归失败,不发布。
4. `swift test --package-path Packages/StrategyTooling` 全绿(守卫移除无回归)。
