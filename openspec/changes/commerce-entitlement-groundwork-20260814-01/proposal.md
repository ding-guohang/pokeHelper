---
name: commerce-entitlement-groundwork-20260814-01
created: 2026-08-14
status: draft
---

# 需求提案：M4 商业化地基（权限机制 + 架构缝，无账号/无策略）

## Why

M4 需要订阅、权限、同意式分析与上架材料，但其中大部分**编码的是产品/商业决策**
（怎么收费、哪些功能付费、采集什么分析），不是我能替所有者决定的；StoreKit / App Store
Connect 还需要所有者的 Apple 账号。当前能安全、无争议交付的是**决策无关的机制与架构缝**：
一个纯领域的权限状态与解析器（不依赖 StoreKit/网络/持久化），以及把「策略真值」「学习闭环
不可付费墙」两条北极星约束**结构化**下来，好让未来的 StoreKit 基础设施层即插即用而不重构。

隐私事实底稿已单独交付（`docs/product/privacy-and-data-handling.md`）。

## What Changes

### New Capabilities

- `feature-entitlement-policy` — 新增纯领域包 `Packages/Entitlements/`（零依赖）：`EntitlementStatus`
  （free / subscribed(until) / inGracePeriod(until) / expired 的状态与到期判定）+ `EntitlementResolver`
  （给定状态、一组「受限功能键」和当前时间，判定某功能是否解锁）。**默认策略为空集**——不配置
  任何受限功能时，一切保持免费，行为与今日完全一致。StoreKit 收据/交易层留到基础设施层（需
  Apple 账号），本切片不做。

### Modified Capabilities

无。不改任何现有功能的可用性（默认全免费）。

## Capabilities Detail

### Capability: feature-entitlement-policy

#### Requirement: 权限状态与到期判定为纯领域逻辑

The system SHALL model subscription entitlement as a pure-domain `EntitlementStatus`
value with deterministic expiry/grace evaluation, depending on no StoreKit, network,
or persistence, and SHALL be `Sendable`.

##### Scenario: 生效订阅在到期前解锁

- GIVEN `EntitlementStatus.subscribed(until: T)` 且当前时间 `now < T`
- WHEN 判定访问是否有效
- THEN 有效

##### Scenario: 宽限期内仍有效

- GIVEN `EntitlementStatus.inGracePeriod(until: G)` 且 `now < G`
- WHEN 判定访问是否有效
- THEN 有效

##### Scenario: 过期或到期后失效

- GIVEN `EntitlementStatus.expired`，或 `subscribed(until: T)` 且 `now >= T`
- WHEN 判定访问是否有效
- THEN 无效

#### Requirement: 解析器按策略门控，默认全免费且核心不可门控

The system SHALL resolve access for a feature key given the entitlement status and a
policy (the set of gated feature keys), granting access to any key NOT in the gated
set unconditionally, and granting a gated key only when the entitlement status is
valid at the given time. An empty policy SHALL leave every feature unlocked.

##### Scenario: 未受限功能恒解锁

- GIVEN 策略的受限集合不含功能键 `K`
- WHEN 以任意 `EntitlementStatus`（含 free）解析 `K`
- THEN `K` 解锁

##### Scenario: 受限功能随状态开合

- GIVEN 策略的受限集合含功能键 `P`
- WHEN 以有效订阅解析 `P`
- THEN `P` 解锁
- AND 以 free / expired 解析 `P` 时 `P` 锁定

##### Scenario: 空策略保持现状

- GIVEN 空策略（未配置任何受限功能）
- WHEN 解析任意功能键
- THEN 全部解锁（行为与接入前一致）

## Impact

- **Code:** 新增 `Packages/Entitlements/`（源 + Swift Testing 测试）；`scripts/check-package-layering.sh`
  以空允许集登记该包（强制零依赖）；`scripts/check-project-shape.sh` 增加其 `-warnings-as-errors`
  计数断言。**不进 `project.yml`**——像 `StrategyTooling` 一样先作为独立 SPM 包用自己的测试门禁把关；
  等有真实功能消费它时（变现决策落地后）再链入 app target，避免此刻的投机接线。
- **Interfaces:** 无对外行为变化；不接入任何 UI 门控（默认全免费）。
- **Dependencies:** 无新增运行时依赖；`Entitlements` 依赖为空。

## Risks

- 过早抽象出错的权限模型 → 只做**决策无关**的最小核心（状态 + 到期 + 空策略解析器），受限功能
  键用不透明字符串键，不耦合 app 功能分类；具体「哪些功能付费/分层/定价」留作产品决策，不在本切片编码。
- 无意给学习闭环加付费墙 → 默认空策略；北极星约束（核心决策训练永远免费）写入 design 与测试。

## Non-Goals

- StoreKit / 收据校验 / 交易读取（基础设施层，需 Apple 账号）。
- 具体订阅层级、定价、哪些功能付费（产品决策）。
- 同意式分析/遥测的采集实现（另行提案；当前无任何分析）。
- 任何 UI 付费墙或功能门控接线。

## Acceptance Criteria

1. `swift test --package-path Packages/Entitlements` 全绿，覆盖上述全部 Scenario。
2. `scripts/check-package-layering.sh` 通过且断言 `Entitlements` 零依赖。
3. `scripts/check-project-shape.sh` 通过（含新包的告警即错误断言）。
4. 不改变任何现有功能可用性（默认空策略 == 全免费）。

## 待所有者决策（不在本切片编码）

- 变现模型：订阅 / 一次性 / 用量限制？分层？
- 哪些功能受限（受限功能键集合）——须遵守「核心决策训练闭环永远免费」。
- 是否引入同意式分析、采集口径（privacy-preserving，不含牌谱/PII）。
