# Capability: tournament-pushfold

## Requirement: 有效深度的精确阈值判定

The system SHALL classify a short-stack push/fold spot by a caller-supplied big-blind threshold using exact integer arithmetic (no floor loss), and SHALL expose the floored effective depth for display, without endorsing any particular threshold.

### Scenario: 阈值判定精确且含等号边界

- GIVEN 有效筹码 `850`、级别 BB=`100`
- WHEN 分别以阈值 `10`、`8` 判定 `isAtOrBelow`
- THEN 阈值 `10` → `true`（`850 <= 1000`），阈值 `8` → `false`（`850 > 800`）
- AND 展示用 `effectiveBigBlinds` 为 `8`（`850 / 100` 向下取整；证明精确比较区别于 floor 后再比）

### Scenario: 等号边界计入（≤ 而非 <）

- GIVEN 有效筹码 `800`、级别 BB=`100`
- WHEN 以阈值 `8` 判定 `isAtOrBelow`
- THEN 结果为 `true`（`800 <= 800`，边界含等号；整数精确比较而非 floor 后再比）

### Scenario: 负阈值与阈值溢出被分别拒绝

- GIVEN 合法上下文（有效筹码 `1000`、BB=`100`）
- WHEN 以阈值 `-1` 判定 → 抛 `PushFoldError.negativeThreshold`
- AND 以阈值 `Int.max`（`Int.max × 100` 溢出）判定 → 抛 `PushFoldError.thresholdOverflow`
- AND 以合法阈值 `10` 判定能返回布尔（配对成功，防门禁永假）

## Requirement: Jam-or-fold 简化动作模型（内容无关）

The system SHALL present exactly the two options of the disclosed jam-or-fold model — fold, or jam committing the entire effective stack — as a caller-opted modeling restriction, and SHALL NOT assert which holdings jam, score any action, or claim the model is legally exhaustive or optimal.

### Scenario: 候选动作为弃牌与全下全部有效筹码

- GIVEN 有效筹码 `1200`、级别 BB=`100`
- WHEN 取 `options()`
- THEN 恰为 `[.fold, .jam(toChips: 1200)]`（全下提交全部有效筹码 `1200`）
- AND 与传入阈值无关（不同深度返回同一动作集，证明它是模型动作集而非深度相关推荐）

## Requirement: 输入校验

The system SHALL reject an ill-formed context on construction with distinct equatable errors.

### Scenario: 非正有效筹码与非正大盲被分别拒绝

- GIVEN 有效筹码 `0` 或负数（其余合法）→ 构造抛 `PushFoldError.nonPositiveEffectiveStack`
- AND 级别 `bigBlindChips == 0`（其余合法）→ 构造抛 `PushFoldError.nonPositiveBigBlind`
- WHEN 各自单独违规构造
- THEN 两种错误可判等且互不相同；各自去掉该违规后能成功构造
