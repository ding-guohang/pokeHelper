# Capability: cash-session-run

## Requirement: 三种长度的 Session

The system SHALL run sessions of 15, 30 or 60 hands and SHALL record the seed, profile assignment, opponent profile table version and hand count so a session can be replayed hand for hand.

### Scenario: 完成一局 Session

- GIVEN 用户分别选择 15、30、60 手
- WHEN 打完全部手数
- THEN 三局都标记为完成
- AND 三局的 SessionHand 条数恰为 15、30、60
- AND 每条记录保存了种子、五个座位的档案指派、对手行为表版本与手数
- AND 三局都被标记为完成
- AND 三局各自用记录重新构造，都得到逐手相同的牌与逐个相同的对手行动

### Scenario: 行为表版本变化时拒绝静默重放

- GIVEN 一条记录的对手行为表版本与当前内置版本不同
- WHEN 用户重放该 Session
- THEN 系统不声称重放一致
- AND 明确告知该记录由另一版本的对手行为产生
- AND 仍可查看已保存的手牌记录

### Scenario: 中断后续打

- GIVEN 用户打到第 7 手后终止进程
- WHEN 再次打开该 Session
- THEN 从第 8 手继续
- AND 前 7 手的记录未被改写
- AND 第 8 至 15 手的牌与对手行动，与同种子不中断连续打完的 Session 的第 8 至 15 手完全相同

## Requirement: 英雄的每个决策都由用户作出

The system SHALL obtain every hero action in a session from the user, and SHALL NOT advance past a hero decision point without one.

### Scenario: 每个英雄决策点都停下来等用户

- GIVEN 一局进行中的 Session 走到英雄的决策点
- WHEN 用户尚未选择行动
- THEN 该手不推进，界面显示当前合法行动集合
- AND 记录中该手的行动数不增加

### Scenario: 记录里的英雄行动就是用户选的

- GIVEN 用户在一局 15 手 Session 中的每个英雄决策点作出选择
- WHEN 对局结束
- THEN 记录中每个英雄行动都等于用户当时选的那个
- AND 该 Session 至少有 15 个英雄决策点，否则断言空转

### Scenario: 没有暗中代打

- GIVEN 一局 Session
- WHEN 检查英雄座位的行动来源
- THEN 不存在任何路径由 `BaselineActionPolicy` 或任何对手档案代替英雄行动
- AND 频率报告与关键手复盘中标为「你的行动」的，只能是用户提交过的行动

## Requirement: Session 手牌不进入能力画像

The system SHALL NOT create a TrainingEvent from a session hand, whether or not its spot matches installed content.

### Scenario: 未命中内容的手牌不产生事件

- GIVEN 已安装内容非空，Session 中一手在翻前的位置与内容某场景相同，但有效筹码落在不同分桶
- WHEN 该手结束
- THEN 不产生 TrainingEvent
- AND 事件存储的条数不变
- AND 能力画像的样本量不变
- AND 该手仍出现在 Session 记录中

### Scenario: 命中内容的手牌同样不产生事件

- GIVEN Session 中一手在翻前与某已安装场景等同
- WHEN 该手结束
- THEN 不产生 TrainingEvent
- AND 事件存储的条数不变
- AND 由该手记录的英雄局面签名可重算出它是可对照的

### Scenario: 相邻分桶不算等同

- GIVEN 一手的街道、位置与面对的行动类别均与某场景相同，但有效筹码落在与该场景相邻的分桶
- WHEN 判定等同
- THEN 判定为不等同
- AND 由该手的签名重算出它不可对照

### Scenario: 翻后手牌不参与匹配

- GIVEN 一手打到翻牌之后，其翻前部分与某已安装场景等同
- WHEN 判定等同
- THEN 只有该手的翻前决策点被算作可对照
- AND 翻牌及之后的决策点都不被标记
