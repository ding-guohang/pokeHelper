# Capability: imported-hand-signatures

## Requirement: 从导入牌谱确定性导出英雄决策点签名

The system SHALL derive, for every hero decision in an `ObservedHand`, a `SpotSignature` whose street, hero seat offset, hand class, facing action, and stack bucket are computed from the recorded hand alone, deterministically.

### Scenario: 附录 A 的四个英雄决策点签名逐街钉死

- GIVEN 第一切片附录 A 的 `ObservedHand`（英雄 BTN、底牌 `Ah Kd`，翻前加注至 300、翻牌下注 400、转牌过牌、河牌下注 800）
- WHEN 导出英雄决策点签名
- THEN 恰得到 4 个签名，`street` 依次为 preflop、flop、turn、river
- AND 四个签名的 `handClass` 均等于 `HandClass(Card(code:"Ah")!, Card(code:"Kd")!)`，`heroSeatOffsetFromButton` 均为 0
- AND 四个签名的 `facing` 均等于 `FacingAction(priorRaiseCount: 0)`（每条街英雄行动前都无人加注）
- AND 四个签名的 `stackBucket` 依次等于 `StackBucket(effectiveStack:)` 对英雄该决策点剩余筹码求得的值：翻前 10000、翻牌 9700（翻前投入 300 后）、转牌与河牌 9300（翻牌再投入 400 后）——即 stackBucket 随街变化，不是常量

### Scenario: 面对情形由该决策前同街加注次数得出

- GIVEN 一手英雄在翻前面对恰一次加注后再行动的导入牌谱（附录 F，随本切片提交）
- WHEN 导出英雄该决策点的签名
- THEN 其 `facing` 等于 `FacingAction(priorRaiseCount: 1)`
- AND 与附录 A 的 `priorRaiseCount: 0` 成对：面对情形由英雄行动前同街的加注次数算出，而非任何固定值

### Scenario: 跨进程导出得到逐字节相同的签名序列并等于黄金

- GIVEN 附录 A 的 `ObservedHand`
- WHEN 在两个独立进程中各导出英雄签名序列并规范序列化一次（经 `hand-model-writer --signatures`）
- THEN 两次输出逐字节相同
- AND 两次输出逐字节等于随包提交的黄金夹具 `Tests/Fixtures/sample-ps-6max-nlhe.signatures.json`
