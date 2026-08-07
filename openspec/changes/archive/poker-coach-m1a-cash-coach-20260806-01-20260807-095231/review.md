# 评审报告：poker-coach-m1a-cash-coach-20260806-01

## 代码评审结果

### 严重问题

无。

### 警告问题

终审发现并已修复：

1. 拒绝低于或等于跟注额的非法加注，并覆盖构造、解码和策略包校验。
2. checkpoint 增量读取改用 JSONL 追加顺序，避免设备时钟回拨造成漏同步。
3. 损坏历史改为用户显式触发“先备份、再重建”，普通重试不再形成永久循环。
4. 开发策略包补齐三个可加载场景，今日计划形成一个主练习和两个辅助练习。
5. 运行时训练目录与策略包同源，匿名本地身份按安装稳定复用。
6. 含空格目录可可靠重开，今日计划总时长稳定在 5–10 分钟。

交叉复审未发现新的 Critical 或 Important 问题。

## 规格合规检查

| # | Capability | Requirement | Scenario | 测试覆盖 | 状态 |
|---:|---|---|---|---|---|
| 1 | adaptive-native-shell | 四个核心入口 | iPhone 紧凑导航 | AdaptiveNavigationTests、iPhone UI | PASS |
| 2 | adaptive-native-shell | 四个核心入口 | iPad 多栏导航 | IPadLayoutTests | PASS |
| 3 | adaptive-native-shell | 原生平台支持 | 两种设备构建 | verify-m1a、Release build | PASS |
| 4 | cash-decision-domain | 精确扑克值 | 精确金额运算 | AmountTests | PASS |
| 5 | cash-decision-domain | 稳定牌面表示 | 合法牌往返 | CardTests | PASS |
| 6 | cash-decision-domain | 稳定牌面表示 | 非法牌拒绝 | CardTests | PASS |
| 7 | cash-decision-domain | 合法行动过滤 | 未面对下注 | BettingDecisionContextTests | PASS |
| 8 | cash-decision-domain | 合法行动过滤 | 面对下注 | BettingDecisionContextTests | PASS |
| 9 | cash-decision-domain | 稳定行动 JSON | 带金额行动 | DecisionActionTests | PASS |
| 10 | cash-decision-domain | 稳定行动 JSON | 行动字段不匹配 | DecisionActionTests | PASS |
| 11 | versioned-strategy-content | 策略包来源可追溯 | 合法策略包加载 | StrategyPackTests | PASS |
| 12 | versioned-strategy-content | 策略包来源可追溯 | checksum 不匹配 | StrategyPackTests | PASS |
| 13 | versioned-strategy-content | 决策节点语义校验 | 频率总和错误 | StrategyPackTests | PASS |
| 14 | versioned-strategy-content | 决策节点语义校验 | 非法行动进入策略 | StrategyPackTests | PASS |
| 15 | versioned-strategy-content | 审核状态约束 | 已审核内容缺少审核时间 | StrategyPackTests | PASS |
| 16 | versioned-strategy-content | 审核状态约束 | 开发内容展示 | Feedback/Today/Review tests、UI tests | PASS |
| 17 | explainable-decision-training | 行动与信心共同提交 | 提交信息不完整 | DecisionSessionViewModelTests | PASS |
| 18 | explainable-decision-training | 行动与信心共同提交 | 合法提交 | DecisionSessionViewModelTests | PASS |
| 19 | explainable-decision-training | 可解释 EV 评分 | 最高 EV 行动 | DecisionScorerTests | PASS |
| 20 | explainable-decision-training | 可解释 EV 评分 | 接近 EV 的混合行动 | DecisionScorerTests、Feedback tests | PASS |
| 21 | explainable-decision-training | 可解释 EV 评分 | 策略节点外行动 | DecisionScorerTests | PASS |
| 22 | explainable-decision-training | 评分与结果无关 | 相同决策不同后续结果 | DecisionScorer 类型契约 | PASS |
| 23 | explainable-decision-training | 专业反馈层级 | iPhone 专业反馈 | Feedback tests、iPhone UI | PASS |
| 24 | explainable-decision-training | 专业反馈层级 | iPad 专业反馈 | Feedback tests、iPad UI | PASS |
| 25 | explainable-decision-training | 专业反馈层级 | 剥削条件缺失 | FeedbackPresentationTests | PASS |
| 26 | local-learning-profile | 不可变本地训练事件 | 首次追加 | FileTrainingEventStoreTests | PASS |
| 27 | local-learning-profile | 不可变本地训练事件 | 重复事件 | FileTrainingEventStoreTests | PASS |
| 28 | local-learning-profile | 不可变本地训练事件 | 损坏事件文件 | Store/AppBootstrap recovery tests | PASS |
| 29 | local-learning-profile | 能力画像归约 | 高信心错误 | PlayerModel tests | PASS |
| 30 | local-learning-profile | 今日训练优先级 | 高信心弱项优先 | TrainingPlanner tests | PASS |
| 31 | local-learning-profile | 今日与复盘使用真实历史 | 决策完成后刷新 | Dashboard tests、iPhone UI | PASS |
| 32 | m1a-release-safety | 开发策略数据隔离 | Debug 训练 | Dev pack integration、UI tests | PASS |
| 33 | m1a-release-safety | 开发策略数据隔离 | Release 构建 | Release bundle exclusion | PASS |
| 34 | m1a-release-safety | 一键验证 | 从干净检出验证 | scripts/verify-m1a.sh | PASS |

未覆盖的 Scenario：无。6/6 Capabilities、19/19 Requirements、34/34 Scenarios 通过。

## 项目规范检查

| 规范 | 结果 | 说明 |
|---|---|---|
| 架构与分层 | PASS | 规则、内容、训练领域与 App Infrastructure 依赖方向正确 |
| Swift 与并发 | PASS | Swift 6 严格并发，项目警告视为错误 |
| 测试规范 | PASS | 包、App、iPhone/iPad UI 与 Release 门禁完整 |
| 策略内容 | PASS | 整数真值、版本校验、开发披露与 Release 隔离完整 |
| 隐私与安全 | PASS | 无联网越界；损坏历史备份不记录事件正文 |
| 产品范围 | PASS | 未提前引入账号、同步后端、锦标赛或订阅 |
| Git 约定 | PASS | `.superpowers` 未被跟踪，提交为小粒度 Conventional Commits |

## 辅助技能检查结果

本环境没有额外的 Swift lint、并发或国际化审计技能；已执行 Harness 内置三路评审。

## 验证证据

`bash scripts/verify-m1a.sh` 在最终 HEAD 退出 0：

- PokerCore：18 tests；
- StrategyContent：25 tests；
- TrainingDomain：21 tests；
- PokerCoachTests：49 tests；
- iPhone UI：1 test；
- iPad UI：1 test（当前环境使用同尺寸 M5 fallback）；
- Release simulator build：PASS；
- `DevStrategyPack.json` Release exclusion：PASS；
- `git diff --check`：PASS。

## 综合结论

- [x] 通过 — 可归档
- [ ] 有条件通过 — 需修复以下问题
- [ ] 不通过 — 需重大修改

## 评审知识捕获汇总

| # | 类型 | 内容 | 存储位置 | 状态 |
|---:|---|---|---|---|
| 1 | 架构 | runtime catalog 与 validated StrategyPack 同源 | docs/architecture/implicit-contracts.md | 已记录 |
| 2 | 身份 | 匿名本地身份按安装稳定，M1B 不重生已有身份 | docs/architecture/implicit-contracts.md | 已记录 |
| 3 | 数据恢复 | 损坏历史由用户显式触发，先备份原始字节再重建 | docs/architecture/implicit-contracts.md | 已记录 |
| 4 | 扑克规则 | 面对下注时加注目标严格高于跟注额 | docs/architecture/implicit-contracts.md | 已记录 |
