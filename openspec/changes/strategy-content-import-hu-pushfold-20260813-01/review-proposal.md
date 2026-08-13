# 审需报告：strategy-content-import-hu-pushfold-20260813-01

## 检查结果

### 一致性检查

- [x] 通过

### 规格完整性

| Capability | Requirements | Scenarios | 状态 |
|---|---:|---:|---|
| `tournament-strategy-source-adapter` | 4 | 10 | OK |
| `tournament-strategy-content-import` | 3 | 7 | OK |
| `strategy-content-pipeline` | 5 | 13 | OK |
| `versioned-strategy-content` | 5 | 12 | OK |

### 关键审查结论

1. 首批覆盖已钉死为 HU、SB=0.5BB、BB=1BB、无 ante、rake=0、chipEV；Open-Jam
   覆盖 1–20BB，Call-Jam 覆盖 2–20BB。每个深度一个不可变内容包；1BB 仅含
   Open-Jam，避免制造 BB 已无剩余筹码时不存在的跟注决策。
2. 来源锁定为 BSD-2-Clause 的
   `b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`；商业平台仅接受
   用户合法手工导出的本地文件，不允许自动抓取。
3. 频率与每手每行动 EV 必须来自同一冻结平均策略快照；EV 在 combo 层应用 blocker 与
   reach 条件化，再以 `sum(numerator) / sum(denominator)` 聚合到 169 类，最后量化为
   milli-BB。
4. 收敛指标明确为求解器实际返回的 NashConv；若展示常规双人 exploitability，明确为
   `NashConv / 2`。
5. 新内容自动产出只能是 `origin=solver` + `reviewStatus=unverifiedDraft`；具名人工审核
   与新 content version 是后续独立晋升门禁。
6. 新增锦标赛 assumptions 与 range action EV 必须是向后兼容的加法变更，不改变现有
   schema-1 现金包语义。

### 可测试性

- 每个 Requirement 至少有一个 GIVEN/WHEN/THEN 场景。
- 来源哈希、覆盖数量、169 手牌、bps、条件 EV、零分母、确定性、原子失败、审核状态、
  旧包兼容均有可直接断言的验收条件。
- SB fold `-500` milli-BB 与可达 BB fold `-1000` milli-BB 提供了 EV 归一化不变量。
- proposal 无 TODO/TBD/未决占位符。

## 结论

- [x] 通过 — 可进入 plan 阶段
