# 审需报告：sync-m1b-identity-sync-20260807-01

## 检查结果

### 一致性检查

- [x] 通过
- [ ] 有问题

### 规格完整性

| Capability | Requirements | Scenarios | 状态 |
|---|---:|---:|---|
| `independent-account-access` | 5 | 13 | PASS |
| `secure-device-sessions` | 4 | 7 | PASS |
| `local-first-event-sync` | 5 | 11 | PASS |
| `mysql-sync-service` | 5 | 10 | PASS |
| `account-data-rights` | 4 | 5 | PASS |
| `m1b-verification` | 3 | 3 | PASS |
| `local-learning-profile` | 5 | 7 | PASS |
| **合计** | **31** | **56** | **PASS** |

## 修复记录

首轮审需发现并已修复：

1. 数据导出补充当前 profile 的损坏历史原始备份，并明确不为导出自动上传。
2. 分页 checkpoint 只推进到本页最后一条实际返回事件，空页保持原值。
3. 相同幂等键对应不同 request hash 时返回 `idempotencyConflict` 且整批不写入。
4. 密码长度明确按 Unicode scalar 计算并覆盖多字节边界。
5. MySQL 同步 sequence 改为按用户锁行分配，避免 AUTO_INCREMENT 与事务提交顺序不同造成漏同步。
6. 增加 refresh token consumed/revoked 历史，支撑重放检测和 session-family 撤销。

## Modified Capability 检查

`local-learning-profile` 完整保留主规格中的 4 个 Requirements 和 6 个 Scenarios，仅做以下完整更新：

- “今日与复盘使用真实历史”扩展为 active profile 的本地与同步事件。
- 新增“跨设备历史确定性归约”及其 Scenario。

未删除或弱化既有行为。

## 架构与规范检查

- MySQL/InnoDB 变更与用户批准的 M1B 设计一致。
- HTTP、认证、Keychain 和 MySQL DTO 保持在 App Infrastructure 与 Go 服务边界。
- M1A 的 `TrainingEvent`、`TrainingEventStore`、`FileTrainingEventStore` 和内容版本语义不变。
- 密码、令牌、日志、设备会话、导出和删除符合 `docs/standards/security.md`。
- 损坏历史备份的导出与删除符合 `docs/architecture/implicit-contracts.md`。
- proposal 已要求把现有 PostgreSQL 文档真值统一更新为 MySQL/InnoDB。

## 可测试性检查

- 7/7 Capabilities 至少包含一个 Requirement。
- 31/31 Requirements 至少包含一个 Scenario。
- 56/56 Scenarios 均包含 GIVEN、WHEN、THEN。
- 未发现占位符、不可断言结果或剩余安全/同步歧义。

## 结论

- [x] 通过 — 可进入 plan 阶段
- [ ] 有条件通过 — 需修复以上问题
- [ ] 不通过 — 需重大修改
