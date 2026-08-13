---
name: tournament-pushfold-trainer-20260813-01
created: 2026-08-13
status: review_passed
---

# 需求提案：单挑 Push/Fold 训练（消费未审核锦标赛内容，dogfood/debug）

## Why

首批锦标赛 push/fold 内容已作为 `unverifiedDraft` 入库（20 包，1–20BB）。要让它产生
训练价值,需要一个可玩的训练面:发一手随机牌 → 英雄在某深度/位置面对 jam-or-fold →
按已导入内容的该手频率/EV 评分 → 反馈。因为内容是 `unverifiedDraft`,该功能**只在
debug/dogfood** 可用(store 构建不打包该内容),且界面**必须披露"未经策略审核"**。

## What Changes

### New Capabilities

- `tournament-pushfold-training` — 把 20 个 push/fold 内容包按频道打包(仅 debug/dogfood,
  store 排除),按深度加载,发随机 spot(深度×位置×手牌),用**既有 `DecisionScorer`**
  对该手 `rangeCell` 的频率/EV 评分,产生 `TrainingEvent`,复用既有反馈,全程披露未审核。

### Modified Capabilities

无。`m1a-release-safety` 的既有要求不变——store 仍只 `reviewed`;本切片只新增了一类
落在 dogfood/debug、被 store 排除的未审核内容,`check-release-content.sh` 与频道断言按
既有规则继续成立(`verify-m1c.sh` 三频道验证通过)。

## Capabilities Detail

### Capability: tournament-pushfold-training

- **打包(按频道)**:20 个 `tourn-hu-chip-ev-noante-*.json`(+`.sha256`)进
  `PokerCoach/Resources/`;`Config/Release.xcconfig` 的 `EXCLUDED_SOURCE_FILE_NAMES`
  追加 `tourn-hu-chip-ev-noante-*.json`(store 排除;dogfood 因自身重声明只排 Dev 包故
  保留;debug 无排除故保留)。`check-release-content.sh` 的 manifest 扫描作为兜底:
  即便漏了排除,store 也因 `unverifiedDraft` 失败关闭。
- **加载**:`TournamentPushFoldLoader`(基础设施)按深度从 bundle 读包并过
  `StrategyPackLoader`/校验器;列出可用深度;store 频道无包时返回空(功能入口消失)。
- **发牌与出题**:由种子确定的 RNG 发两张牌→映射 169 手类;选深度(1–20)与位置
  (SB open-jam;深度≥2 才有 BB call-jam);取对应包的对应 scenario。
- **评分**:查该手 `rangeCell` 的 `actionWeightsBasisPoints`/`actionEVs`,合成一个
  per-hand `DecisionScenario`(复制包 scenario,覆盖 `heroCards` 与 `options`),交
  **未改动的 `DecisionScorer`** 评分;据提交产生 `TrainingEvent`(scenarioID 关联包,
  走冻结契约)。
- **披露**:作答与反馈两屏都显示"未经策略审核"(复用 `StrategyContentMetadata`
  与 `FeedbackPresentation` 的 provenance);入口在「复盘」下(dogfood/debug 才出现)。

#### Requirement: 按频道打包未审核锦标赛内容

The system SHALL bundle the unverified tournament packs into debug and dogfood builds
and exclude them from the store build, and the release content gate SHALL continue to
pass for every channel (store carrying only reviewed content).

##### Scenario: store 构建排除未审核锦标赛内容

- GIVEN Release(store)配置构建
- WHEN 运行 `check-release-content.sh`
- THEN 产物内不含任何 `tourn-hu-*` 包,频道 `store` 仅见 `reviewed` 的 CoreStrategyPack,门禁通过
- AND `EXCLUDED_SOURCE_FILE_NAMES` 仍以 `DevStrategyPack.json` 打头(`check-m1b-release-secrets.sh` 的子串断言不破)

##### Scenario: dogfood 构建保留未审核锦标赛内容且门禁允许

- GIVEN Dogfood 配置构建
- WHEN 运行 `check-release-content.sh`
- THEN 产物含 20 个 `tourn-hu-*` 包,频道 `dogfood` 允许 `unverifiedDraft`,门禁通过

#### Requirement: 发牌、按手评分、产生训练事件

The system SHALL deal a deterministic random push/fold spot (depth × position × dealt
hand), score the hero's jam/fold (or call/fold) against that hand's range cell
frequencies and EVs using the existing scorer, and record a `TrainingEvent`.

##### Scenario: 发确定 spot 并按手评分

- GIVEN 加载 10BB open-jam 包、固定种子发到英雄手牌 `AA`
- WHEN 英雄选择全下
- THEN 评分用 `AA` 的 `rangeCell`(raise 10000、EV +2978;fold EV −500):全下为最优、
  EV 损失 0、得分 100
- AND 若英雄选择弃牌,则 EV 损失 = `2978 − (−500)` milliBB、得分随之下降,`quality` 相应分级

##### Scenario: 完成一题产生训练事件

- GIVEN 一道 push/fold 题已作答
- WHEN 提交评分
- THEN 追加一个 `TrainingEvent`(`scenarioID` 关联该锦标赛包、`abilityDimension` 为
  push/fold、含完整 grade),走既有归约与冻结契约,不新增事件字段

#### Requirement: 全程披露未审核

The system SHALL disclose that the content is unverified on both the answering screen
and the feedback screen whenever the active pack's review status is `unverifiedDraft`.

##### Scenario: 作答屏披露未审核

- GIVEN 训练题来自 `unverifiedDraft` 锦标赛包
- WHEN 展示训练器作答界面
- THEN 显示"未经策略审核"披露(`StrategyContentMetadata.unverifiedDisclosure`)
- AND 反馈屏同样显示该披露

#### Requirement: 仅在内容可用时可达

The system SHALL show the push/fold trainer entry only when the tournament packs are
bundled (debug/dogfood), keeping it absent from the store build and not altering the
four core tabs.

##### Scenario: dogfood/debug 下入口出现,store 下消失

- GIVEN tournament loader 找到已打包的包(debug/dogfood)
- WHEN 打开「复盘」
- THEN 出现「单挑 Push/Fold 训练」入口(`review.tournamentPushFold`)
- AND store 构建无包时入口不出现;四个核心标签不变

## Impact

- **Code:** `PokerCoach/Resources/`(+20 包+sidecar)、`Config/Release.xcconfig`(排除)、
  `PokerCoach/Infrastructure/Content/TournamentPushFoldLoader.swift`、
  `PokerCoach/Features/TournamentTrainer/{ViewModel,View}.swift`、`AppDependencies`(注入)、
  `ReviewView`(入口)、`DecisionSessionView`(作答屏未审核披露)。测试:App 单测 + UI + 门禁。
- **Interfaces:** 复盘下多一个 dogfood/debug 训练入口;产生 `TrainingEvent`(既有契约);
  不改 `TrainingEvent`/契约/四标签。
- **Dependencies:** 复用 `DecisionScorer`、`FeedbackPresentation`、`eventStore`、
  `StrategyPackLoader`;无新第三方依赖。

## Risks

- **未审核内容误入 store**:→ `Release.xcconfig` 排除 + `check-release-content.sh` manifest
  兜底(store 见 `unverifiedDraft` 即失败);三频道门禁全测。
- **评分口径错**:→ 复用未改动的 `DecisionScorer`;按手 `rangeCell` 合成 scenario,
  钉死 `AA@10bb` 全下得分 100 / 弃牌 EV 损失 3478 milliBB。
- **未披露**:→ 作答屏补 `unverifiedDraft` 披露 + 反馈屏既有披露;UI 测试断言可见。
- **入口在 store 泄漏**:→ 入口 gated on loader 非空;store 无包→入口消失。

## Non-Goals

- 不做 ICM/多路/9-max/翻后训练;不把未审核内容标 `reviewed` 或送 store。
- 不改评分公式;不引入图表。
- 不做跨设备"锦标赛专属"报表(事件走既有归约即可)。

## Acceptance Criteria

1. Debug/Dogfood 构建含 20 个 `tourn-hu-*` 包并通过 `check-release-content.sh`;
   Release(store)构建排除它们且门禁通过;`check-m1b-release-secrets.sh` 仍通过。
2. VM 单测:固定种子发 `AA@10bb`,全下得分 100/EV 损失 0;弃牌 EV 损失 3478 milliBB。
3. 完成一题产生一个 `TrainingEvent`(scenarioID 关联锦标赛包,走冻结契约)。
4. 作答屏与反馈屏对 `unverifiedDraft` 均显示"未经策略审核"。
5. UI 测试:dogfood/debug 下复盘→「单挑 Push/Fold 训练」可达并显示披露。
6. `AdaptiveNavigationTests` 绿;`verify-m1c.sh`(含三频道门禁)通过;层禁通过。
