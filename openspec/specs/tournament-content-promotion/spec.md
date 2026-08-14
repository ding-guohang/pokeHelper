# Capability: tournament-content-promotion

## Requirement: 只有完整审核记录才可晋升

The system SHALL promote tournament content to `reviewed` only when a review record
supplies a named reviewer, an ISO8601 review timestamp, an explicit `approved`
decision, and evidence meeting the objective thresholds (independent equity recompute
delta ≤ 1e-6, exploitability cross-check ≤ 0.02 BB, byte-reproducible), and SHALL fail
closed listing every missing item otherwise, writing nothing.

### Scenario: 缺审核人/未批准/证据不达标被拒

- GIVEN 审核记录缺具名审核人,或 `decision != approved`,或 `exploitabilityMaxBB` 超阈值,
  或 `reproducible != true`
- WHEN 请求晋升
- THEN 以列出缺失项的错误失败,不产出任何 reviewed 包或校验和

### Scenario: 完整记录通过校验

- GIVEN 审核记录含具名审核人、ISO8601 时间、`approved`、三项证据均达阈值
- WHEN 校验审核记录
- THEN 返回审核人与时间,校验通过

## Requirement: 晋升只重标不改内容

The system SHALL, on a valid promotion, produce one `reviewed` pack per depth with a
new content version, `origin=solver`, and the reviewer/time recorded, and SHALL verify
by golden regression that each reviewed pack's strategy content (range cells, options,
explanations) is byte-identical to the `unverifiedDraft` baseline, failing if any
frequency or EV changed.

### Scenario: 晋升产出 reviewed 且策略与基线逐字节一致

- GIVEN 完整审核记录、20 个导出、`unverifiedDraft` 基线包、新内容版本
- WHEN 执行晋升
- THEN 产出 20 个包,每个 `reviewStatus=reviewed`、`origin=solver`、带具名审核人/时间、
  新内容版本
- AND 每个 reviewed 包去掉 manifest 后与对应基线包逐字节相等(策略未被改动)
- AND 生成校验和与晋升记录;原子发布,失败不留残件

### Scenario: 晋升试图改动策略被拒

- GIVEN reviewed 包与基线在任一手频率/EV 上不一致
- WHEN 黄金回归比对
- THEN 晋升失败并指出发生改动的深度,不发布
