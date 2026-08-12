# 审需报告：session-m2a-cash-simulation-20260810-01

日期：2026-08-11
方式：读取现有 specs 与 docs 后，派两个窄范围 agent（可测试性、架构一致性）独立审，我逐条复核其论断，再据此重写 proposal。

## 结论

**初稿不通过，需重大修改。已按审出的问题重写，重写后有条件通过 —— 可进入 plan 阶段**，遗留四个设计点在 plan 阶段决断（见文末）。

初稿的问题不是措辞不严，是**两处与现网规格实打实的冲突**，外加一个 capability 的全部场景都能被常量实现骗过。

## 一、复核过的硬冲突

四条架构指控我逐条跑了代码和规格原文，全部成立：

| # | 指控 | 复核方式 | 结果 |
|---|------|---------|------|
| 1 | 短码场景会 trap 进程 | 读 `BettingDecisionContext.swift:15` | 成立。`precondition(amountToCall <= effectiveStack)`。初稿 proposal.md:84 的「面对 3BB 加注、英雄剩余 2BB」和 :133 的「剩余 3BB、需跟注 5BB」两个 GIVEN 都构造不出来 |
| 2 | 场景断言与实现相反 | 读 `legalActions()` 第 68-72 行 | 成立。`amountToCall == effectiveStack` 时 `.allIn` 分支被 `amountToCall < effectiveStack` 挡住，返回的是 `{.fold, .call(to:)}`。初稿断言 `{弃牌, 全下至 2BB}`，**对着正确代码是红的** |
| 3 | 合法行动真值被两处拥有 | `grep "^## Requirement" openspec/specs/cash-decision-domain/spec.md` | 成立。第 32 行已有「合法行动过滤」，而初稿未把 `cash-decision-domain` 列为 Modified |
| 4 | Session 评分与既有规格冲突 | 读 `explainable-decision-training/spec.md:3-20` | 成立。规格要求行动与信心**共同**提交才评分、且**在展示反馈前**持久化。初稿的 Session 评分两条都不满足 |

第 2 条最值得记一笔：它不是「场景写得含糊」，是场景写错了。这种缺陷在实现阶段的下场通常不是修实现，而是把断言悄悄改软。

## 二、可测试性：一个 capability 全线失守

`key-hand-review` 的三个场景，**没有一个能被下面这个实现打红**：

```swift
func keyHands(of s: Session) -> [KeyHand] { [KeyHand(s.hands[0], reason: "大底池")] }
```

`不超过 5 手` → 1 ≤ 5 过；`每一手显示其入选原因` → 硬编码字符串过；`不出现空列表` → 非空过。

更难堪的是初稿 Risks 段自己写着「关键手选择退化为『取前五手』→ 需要一条断言『相同 Session 换一种排序输入会选出不同的手』的测试」——**风险登记册点名了该写的测试，而规格里没有这条测试**。

其余高频缺陷型：

- **上界无下界**：`不超过 5 手`、`最多 2 + 2×对手数 + 5 张`——空集合与不发牌都满足。
- **同进程判确定性**：`两次求对手行动 / 两次行动相同`。`hashValue` 在进程内本来就稳定，`Set` 迭代序在进程生命周期内固定——这条测不出它想禁的那类 bug，而同一份 proposal 的发牌场景写对了（`在两个独立进程中`）。
- **来源不可断言**：`描述来自档案定义，不是运行时统计`——字符串没有出身，视图里硬编码即通过。
- **未定义术语**：`艰难决策`（且与「Session 不评分」自相矛盾——难度判定恰恰需要策略数据）、`结果大幅波动`（无阈值无单位）、`相对排序`（无键无方向）、`抽水`（全文仅此一处，若恒为 0 则守恒式塌成 `sum == 0`）、`对手数`（全文只在公式里出现过，从未固定）。
- **单向断言**：`集合中的每个行动都能被状态机接受` 只是 legal ⊆ accepted，反向从未断言，漏报合法行动无人发现。

## 三、重写的要点

### 主结构改动：Session 手牌一律不产生 TrainingEvent

初稿是「命中内容的手牌照常评分」。改为**都不评分**，命中的手牌在复盘里做**对照**（你打了什么 / 内容的频率是什么，明确标注不是评分），并提供「以训练模式重打」——重打走既有管线，出示行动与信心、反馈前落库。

这一刀同时解决五个问题：

1. 与「行动与信心共同提交」的冲突——重打时才要信心，连续打牌时不弹。
2. 与「反馈前持久化」的冲突——同上。
3. Session 事件混入画像——从构造上不存在，不靠过滤。
4. **迁移信号被喂反**——初稿只给命中内容（即已收录）的手牌计分，而迁移的定义就是在**没见过**的局面上发生。初稿会让 Session 满足一个它恰好证伪了的信号。
5. `learning-rules.md:12` 的「模拟验证」被掏空——对照就是验证（你的实战打法是否站得住），重打是把验证转成训练，闭环不再是空的。

### 消掉未定义项

| 初稿 | 重写后 |
|------|--------|
| 「局面等同」六项全匹配，含连续量底池 | **只判翻前**；位置 + `RangeCell.handClass` 的 169 格记号 + 面对的行动类别 + 有效筹码分桶（边界在 spec 里枚举）。翻后匹配推 M2B——翻后手牌分类法本项目没有，也无求解器依据可造 |
| `对手数` 从未固定 | 6-max，英雄 + 5 对手，起始各 100BB，不补码不换座 |
| `抽水` 出现一次，无定义 | **M2A 恒为 0**，写进约束与 Non-Goals |
| `艰难决策`、`结果大幅波动` | 换成枚举 `.bigPot`/`.allIn`/`.bigSwing`/`.trainable`，各带可算判据（`.bigSwing` ≥ 20BB，`.bigPot` 须在底池前 5 名内） |
| 短码桌型 | Non-Goals 明确：短码只是 100BB 牌局中途的自然状态，不做短码桌型——消除与 M3 Non-Goal 的自相矛盾 |

### 补上反例与双向断言

- 加 `相邻分桶不算等同`、`翻后手牌不参与匹配` 两条反例——否则 match-everything 实现全绿。
- 加 `未命中内容的手牌不产生事件` 的 GIVEN 限定为「已安装内容非空且存在近似但不等同的场景」——初稿的 GIVEN 用空内容库最省事地满足，等同关系一次都跑不到。
- 合法集合改双向：集合内均可接受 **且** 集合外均被拒绝，再加形状约束（未面对下注时必含 check 与至少一个尺度）。
- 筹码守恒加下界：赢家增量严格为正、底池归零、30 手后六座位合计 600BB。
- 确定性一律跨进程 + 提交黄金记录。
- 加 `关键手不是「取前五手」`——把 Risks 段自己点名的那条测试写进规格。
- 加 `重打产生的事件与普通训练事件无从区分`——防止 Session 出身以字段形式渗进事件。

### 新增 Modified：cash-decision-domain

把「须跟注额由上游封顶到有效筹码、筹码用尽时的 call 即全下」写成规格，并整块携带该 capability 现有的四个 Requirement。这既消除真值双主，也把冲突 2 变成一条与实现一致的断言。

## 四、门禁验证

`check-proposal-completeness.sh` 在归档时会用 proposal 的块**整体替换** specs，所以两个 Modified capability 必须整块携带。除跑通外，另跑两条负例证明它真会拦：

```
--- 负例1：删掉 cash-decision-domain 的「非法牌拒绝」场景 ---
  - cash-decision-domain: Scenario "非法牌拒绝" is missing and would be deleted at archive
^ 门禁按预期拦下

--- 负例2：保留标题但掏空「合法行动过滤」的 SHALL ---
  - cash-decision-domain: Requirement "合法行动过滤" no longer states a SHALL,
    so archive would replace a binding requirement with prose
^ 门禁按预期拦下

--- 还原后复验 ---
modified capabilities preserve every existing requirement and scenario, none gutted:
cash-decision-domain, local-learning-profile
```

## 五、规格完整性

| Capability | Requirements | Scenarios | 状态 |
|------------|-------------|-----------|------|
| session-dealing | 2 | 6 | OK |
| virtual-opponents | 2 | 5 | OK |
| cash-session-run | 2 | 6 | OK |
| key-hand-review | 2 | 7 | OK |
| cash-decision-domain (Modified) | 4 | 8 | OK，整块携带 |
| local-learning-profile (Modified) | 6 | 15 | OK，整块携带 |
| **合计** | **18** | **47** | — |

计数由脚本数出，不是估的——这张表我第一版四行写错了（凭印象填 6/6/9/16，实为 5/7/8/15）。在一份指控「未经核对的数字」的报告里填未经核对的数字，正是本次要治的毛病。

同一次扫描另外确认：18 个 Requirement 全部含 SHALL，47 个 Scenario 全部含 GIVEN/WHEN/THEN，全文无 TBD/TODO/待定占位符。

## 六、留给 plan 阶段的决断

1. **`SpotSignature` 放哪一层。** 这是重写后**唯一未闭合的架构问题**。等同判定要同时看 Session 局面与 `DecisionScenario`：放 `SessionSimulation` 就得 import `StrategyContent`，放 `TrainingDomain` 就得 import `SessionSimulation`，两条都在 `layering.md` 的规则之外，且后者构成 `TrainingDomain ↔ SessionSimulation` 环。倾向定义在 `PokerCore`（它不依赖任何项目模块），两侧各出签名、App 层比较。plan 阶段确认后要同步更新 `layering.md` 的层图——目前 `SessionSimulation` 在图上根本没有位置。
2. **`SessionHand` 是否跨设备同步。** 纳入要扩服务端，不纳入则换设备看不到历史 Session。
3. **对手档案硬编码还是随内容交付。** 档案是策略形状的真值，与策略内容承担同一条披露义务；无论哪种都必须带版本号。
4. **关键手选择分数的权重与 tie-break。** 四个原因的排序键，并列时须确定性。
