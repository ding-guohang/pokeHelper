# 归档记录：sync-m1b-identity-sync-20260807-01

## 基本信息

- **Change ID：** sync-m1b-identity-sync-20260807-01
- **创建：** 2026-08-07
- **归档：** 2026-08-10
- **里程碑：** M1B 独立身份与同步
- **执行：** Task 1–3 由 Codex 完成（基线 `3e06a94`），Task 4–13 与评审返工由 Claude 完成
- **评审结论：** 有条件通过（见 `review.md`）

## 需求摘要

在不给 M1A 训练加登录墙的前提下，引入独立邮箱/Apple 账号、安全设备会话、本地优先的事件同步、账号数据权利，以及一键 M1B 验证。

## 技术方案摘要

- **服务端**：Go + MySQL 8.4 InnoDB。上传在单事务内按固定顺序执行——锁每用户序列行 → 比对幂等键与请求哈希 → 分配序列 → 持久化响应 → 提交。
- **会话**：32 字节不透明令牌，仅存 SHA-256；轮换与重放检测在同一行锁事务内完成，重放撤销整个会话族，consumed 行保留以维持可检测性。
- **客户端**：本地先写、可恢复 Outbox、单调 checkpoint 拉取；档案按账号隔离，首个登录账号认领匿名历史（目录改名，字节不变）。
- **跨语言契约**：`Contracts/training-event-upload-v1.json` 及其 SHA-256 由 Swift 与 Go 两侧逐字节断言。

## 规格变更摘要

- **新增 6 个 Capability**：independent-account-access (5/13)、secure-device-sessions (4/7)、local-first-event-sync (5/11)、mysql-sync-service (5/10)、account-data-rights (4/5)、m1b-verification (3/3)
- **修改 1 个**：local-learning-profile (5/7)，完整替换
- **删除**：无
- 合计 31 requirements / 56 scenarios 已合并入 `openspec/specs/`

## 验证

`bash scripts/verify-m1b.sh` 从干净检出通过：M1A 回归 → Go 静态检查与单测 → 隔离 MySQL 集成与双设备 E2E → iOS 单测 → iPhone/iPad UI → 真实 Swift→Go→MySQL 契约回路 → Release 密钥门禁 → `git diff --check`。

## 变更文件清单

 125 files changed, 17256 insertions(+), 46 deletions(-)

按目录：

      15 Server/internal/httpapi
      15 PokerCoachTests
       9 Server/internal/mysqlstore
       9 PokerCoach/Infrastructure/Auth
       7 Server/internal/session
       7 Server/internal/auth
       7 PokerCoach/Infrastructure/Sync
       5 Server/internal/sync
       5 PokerCoach/Infrastructure/Profiles
       5 PokerCoach/Features/Account
       4 Server/internal/appleauth
       4 Server/internal/account

## 归档时接受的已知缺口

见 `review.md` 文末。P0 与 P1 全部修复并有反向验证；P3 的 5 条按决定留待后续，其中导出的 `Double` 往返与 `SystemAppleAuthorizationClient` 的无保护可变状态应在 M1C 前处理。
