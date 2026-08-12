# 审需报告：handlab-m2b-import-preview-20260812-01

日期：2026-08-12
方式：派两个窄范围 agent（可测试性、架构一致性）独立审，逐条对代码与文档复核其论断，再据此重写 proposal。

## 结论

**初稿不通过，需重大修改。已按审出的问题重写，重写后有条件通过——可进入 plan 阶段。** 初稿的架构判断全部成立（复核通过），问题集中在可测试性：几乎每个 scenario 都能被一个退化实现骗过，且没有任何一段具体牌谱被提交，解析断言全对着测试作者临时编造的输入。

## 一、架构一致性：全部复核成立

逐条跑了代码，初稿的架构假设无一落空：

| 项 | 复核 | 结果 |
|---|---|---|
| 复用 `Card`/`BBAmount`/`TablePosition` | 读 `Packages/PokerCore/Sources/PokerCore/{Card,Amounts,TablePosition}.swift` | 成立。`TablePosition(tableSize:heroSeatOffsetFromButton:)` 的 `labelsByTableSize` 覆盖 2–9 人，覆盖 PokerStars 现金全桌型；`BBAmount` 是整数 centiBB 包装 |
| 不复用 `SessionSimulation.PlayedHand` | 读 `SessionRunner.swift`、`SessionRecord.swift`、`TableRules.swift` | 成立且必要。模拟模型定长 6 人、英雄固定 0 号座、每座位底牌都由发牌填满（无"未知"）、抽水恒 0、无 ante/货币/原始文本——结构上不适配观察到的真实牌。仅边池（`PotAward`）是可表示的，其余皆缺 |
| 分层落点 | 读 `docs/architecture/layering.md`、`scripts/check-package-layering.sh` | 成立。解析→依赖 PokerCore 的新包、持久化→独立包，正是 `TrainingDomain→TrainingPersistence`、`SessionSimulation→SessionPersistence` 的既有形状 |
| 冻结契约与事件隔离 | 读 `Contracts/…v1.json`、`SessionRunCoordinator.swift`、`SessionEventIsolationTests.swift` | 成立。M2A 的隔离断言正是"协调器持有存储却不写、种非空存储、走真实路径断言前后条数不变"，本切片照搬这个形状是对的 |
| centi-BB 非整除边界 | CLAUDE.md 精确数据规则 | 成立。BB 不整除时无法真值存储，"标为冲突而非四舍五入"是唯一与精确数据规则一致的选择 |
| `Modified Capabilities: 无` | 扫 `openspec/specs/`（22 个能力） | 成立。三个新能力与现有能力均不重叠，只以"不产生 TrainingEvent"附加保持既有语义 |

架构复核另留两条**实现期必须做、初稿未写进验收**的项，已补进重写：

1. `check-package-layering.sh` 逐包枚举，新包不加进去就不被强制——重写补为验收标准 6。
2. 事件隔离断言要有意义，导入路径必须真的**持有**事件存储（仿 `SessionRunCoordinator`），否则退化为"够不到存储的类型"。重写把隔离场景改为同时断言"采纳成功、库条目 +1"。

## 二、可测试性：初稿几乎每条 scenario 都能被退化实现骗过

复核了 18 条指控，绝大多数成立。归类如下（括号内为重写对策）：

- **没有任何具体牌谱被提交。** 所有 "一段真实/受支持的 PokerStars 牌谱" 都让测试作者自己编输入，夹具可以被塑造成迎合实现的输出。（重写冻结附录 A–D 四段样例，每条 scenario 绑定具体输入与具体期望值。）
- **恒定实现通过。** 换算 scenario 只给一个数据点 → 硬编码 `{stack:10000,pot:300}` 就过；"分街记录行动"被零行动满足；"板面张数 0/3/4/5"被硬编码序列满足。（补第二换算例逼出函数性；补最小行动数与具体牌面/牌；断言具体动作序列。）
- **单向断言 / reject-everything。** "不受支持被拒绝"被"恒判不受支持"通过；"矛盾字段被标冲突"被"恒报冲突"通过；"英雄底牌缺失记未知"被"全部记未知"通过。（每条补反方向：附录 A 必须解析成功且零冲突、摊牌底牌必须读出真值。）
- **成对 scenario 不共享输入，proxy 键可蒙混。** 初稿"清晰输入无冲突"与"矛盾字段有冲突"用两段不同的无约束输入，一个"看是否含某子串"的假检测器能同时过。（重写让附录 B = 附录 A **仅差一行**，冲突集合必须恰为那一行；任何全局常量或无关代理键都无法同时通过 A 与 B。）
- **恒真 / 空集。** "冲突数目等于无法解析字段数"在干净牌上恒真（0=0）；"其余牌谱不受影响"在单条库里空真；"事件存储条数不变"对"什么都没导入"也成立。（改为绑定已知非零冲突数的构造牌；删除用双条库；隔离场景加"库条目 +1"。）
- **未定义术语。** "版本""同一手""字段位置""可信标准化牌谱""受支持格式"全无定义。（新增"术语"节：版本=单调整数、身份=原文规范化 SHA-256、位置=行号、受支持=PokerStars NLHE 现金 2–9 人。）
- **同进程/不可测的确定性。** "两个独立进程""逐字节一致"没有定义被序列化的字节形态。（定义"规范序列化"=排序键 JSON，跨进程比对并等于提交的黄金夹具，仿 M2A 的 `session-seed42-30hands.txt`。）

## 三、重写后的规格完整性

| Capability | Requirements | Scenarios | 状态 |
|---|---|---|---|
| hand-history-import | 2 | 10 | OK |
| import-conflict-review | 1 | 4 | OK |
| personal-hand-library | 1 | 4 | OK |
| **合计** | **4** | **18** | — |

计数由脚本数出。4 个 Requirement 全含 SHALL，18 个 Scenario 全含 GIVEN/WHEN/THEN，全文无 TODO/TBD/待定；`Modified Capabilities: 无`，与现有 22 个 spec 无冲突。

## 四、留给 plan 阶段的决断

1. **规范序列化的确切形态**（字段名、嵌套、金额编码）——影响黄金夹具与跨进程测试；plan 期定死并提交附录 A 的黄金 `.model.json`。
2. **统一牌谱模型的抽水/边注/ante 表示**——本切片只需捕获抽水（附录 A 已用），ante/straddle 是否在 2–9 现金里出现要在 plan 期界定，超出的走"不受支持"。
3. **持久化落点**：独立 `HandHistoryPersistence` 包 vs App 基础设施层——沿用 `SessionPersistence` 先例倾向独立包；plan 期确认并同步进 `check-package-layering.sh`。
4. **导入协调器的归属**：持有事件存储的协调器放 `PokerCoach/Infrastructure/HandLab/`（仿 Session）。
