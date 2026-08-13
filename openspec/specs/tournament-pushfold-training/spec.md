# Capability: tournament-pushfold-training

## Requirement: 按频道打包未审核锦标赛内容

The system SHALL bundle the unverified tournament packs into debug and dogfood builds
and exclude them from the store build, and the release content gate SHALL continue to
pass for every channel (store carrying only reviewed content).

### Scenario: store 构建排除未审核锦标赛内容

- GIVEN Release(store)配置构建
- WHEN 运行 `check-release-content.sh`
- THEN 产物内不含任何 `tourn-hu-*` 包,频道 `store` 仅见 `reviewed` 的 CoreStrategyPack,门禁通过
- AND `EXCLUDED_SOURCE_FILE_NAMES` 仍以 `DevStrategyPack.json` 打头(`check-m1b-release-secrets.sh` 的子串断言不破)

### Scenario: dogfood 构建保留未审核锦标赛内容且门禁允许

- GIVEN Dogfood 配置构建
- WHEN 运行 `check-release-content.sh`
- THEN 产物含 20 个 `tourn-hu-*` 包,频道 `dogfood` 允许 `unverifiedDraft`,门禁通过

## Requirement: 发牌、按手评分、产生训练事件

The system SHALL deal a deterministic random push/fold spot (depth × position × dealt
hand), score the hero's jam/fold (or call/fold) against that hand's range cell
frequencies and EVs using the existing scorer, and record a `TrainingEvent`.

### Scenario: 发确定 spot 并按手评分

- GIVEN 加载 10BB open-jam 包、固定种子发到英雄手牌 `AA`
- WHEN 英雄选择全下
- THEN 评分用 `AA` 的 `rangeCell`(raise 10000、EV +2978;fold EV −500):全下为最优、
  EV 损失 0、得分 100
- AND 若英雄选择弃牌,则 EV 损失 = `2978 − (−500)` milliBB、得分随之下降,`quality` 相应分级

### Scenario: 完成一题产生训练事件

- GIVEN 一道 push/fold 题已作答
- WHEN 提交评分
- THEN 追加一个 `TrainingEvent`(`scenarioID` 关联该锦标赛包、`abilityDimension` 为
  push/fold、含完整 grade),走既有归约与冻结契约,不新增事件字段

## Requirement: 全程披露未审核

The system SHALL disclose that the content is unverified on both the answering screen
and the feedback screen whenever the active pack's review status is `unverifiedDraft`.

### Scenario: 作答屏披露未审核

- GIVEN 训练题来自 `unverifiedDraft` 锦标赛包
- WHEN 展示训练器作答界面
- THEN 显示"未经策略审核"披露(`StrategyContentMetadata.unverifiedDisclosure`)
- AND 反馈屏同样显示该披露

## Requirement: 仅在内容可用时可达

The system SHALL show the push/fold trainer entry only when the tournament packs are
bundled (debug/dogfood), keeping it absent from the store build and not altering the
four core tabs.

### Scenario: dogfood/debug 下入口出现,store 下消失

- GIVEN tournament loader 找到已打包的包(debug/dogfood)
- WHEN 打开「复盘」
- THEN 出现「单挑 Push/Fold 训练」入口(`review.tournamentPushFold`)
- AND store 构建无包时入口不出现;四个核心标签不变
