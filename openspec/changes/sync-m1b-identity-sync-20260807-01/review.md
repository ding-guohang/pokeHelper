# 评审报告：sync-m1b-identity-sync-20260807-01

四路并行评审（代码质量、规格合规、项目规范、安全专项）。结论：**不通过，需重大修改。**

## 为什么全绿的门禁没拦住

`verify-m1b.sh` 26 步全过，250+ 测试全绿，而这个 APP **没有一个用户能登录**。

根因是一句话：**每一侧的测试都用自己的替身，没有任何测试带着真实数据穿过 Swift↔Go 边界。** Go 侧用 Go 构造的请求测 Go，Swift 侧用 Swift 写的 stub 测 Swift，两边各自完美自洽。

tasks.md 第 514/521/524 行明确要求建 `PokerCoachTests/LiveServerSyncContractTests.swift` 与 `scripts/test-live-m1b.sh`——让模拟器跑真实的 Swift→Go→MySQL 回路，design.md 第 168 行还特意写了这条"不能用 golden fixture 替代"。**这两个文件没有被创建**，Task 13 却被标记完成。下面 P0-1 到 P0-4 全部会被那条回路在第一秒抓到。

## P0：产品级阻断（已实证确认）

| # | 缺陷 | 证据 |
|---|---|---|
| 1 | **无人能登录。** iOS `DeviceDescriptor` 带 `appVersion`，Go `auth.DeviceMetadata` 没有该字段，`decodeJSON` 启用了 `DisallowUnknownFields()` | 实测 `json: unknown field "appVersion"` → 400。Apple 登录同理 |
| 2 | **无事件能上传。** Swift `JSONEncoder` 把 UUID 编码为**大写**，`sync/validation.go` 要求小写 | 实测输出 `{"id":"ABCDEF00-..."}`。契约 fixture 用的 UUID 只含数字无 a–f，所以两侧的逐字节断言对大小写完全盲视 |
| 3 | **邮箱验证必失败。** 服务端 `verify-email` 返回 204 空体，iOS 却去解码 `SessionTokensDTO` | → `APIError.malformedResponse` |
| 4 | **重发验证邮件 404。** iOS 调 `/v1/auth/resend-verification`，服务端无此路由 | `grep resend Server/` 无结果 |
| 5 | **同步/档案隔离/本地删除全是死代码。** `makeSyncEngine`、`ActiveProfileController`、`ProfileLifecycleController`、`onAccountDeleted`、`activeProfile` 只在测试里被构造 | 上线后：事件只进 outbox 永不上传；账号 A/B 共用同一个 anonymous 档案（跨用户数据泄露）；选"同时删除本机记录"实际什么都不删 |

第 5 条最讽刺：台账里我自己诊断过服务端"没有组合根"并在 Task 11 修好了，却没把同样的检查用在 iOS 上。

## P0 连带：一次失败就永久卡死

`beginBatch` 无条件返回在途批次，`acknowledge` 只在 2xx 后调用，`synchronize` 里 upload 抛错就中止整轮。所以**任何一次 400 都会让该档案再也无法上传、也无法拉取**——没有毒批次逃生机制。缺陷 2 保证了这就是稳态。

## P1：安全（高危）

| # | 缺陷 | 攻击 |
|---|---|---|
| 6 | **未认证的永久账号锁定。** `Register`/`RequestPasswordReset` 无条件 `Consume` 的限流键，与 `Login` 的 `Check` 是同一个 HMAC 键 | 只需知道邮箱，6 个注册请求即可锁死受害者 15 分钟；受害者无法登录→无法清除→每 15 分钟重复即永久拒绝服务 |
| 7 | **`/v1/auth/reauth` 完全没有限流。** `account` 包零 throttle 引用 | 持有一个被盗 access token 即可全速爆破明文密码（把"会话被盗"升级成"密码泄露"）；每次调用 19 MiB Argon2，单会话即可打满 CPU |
| 8 | **`logOut()` 在 Keychain 故障时谎报成功。** `try?` 把错误吞成 nil，跳过撤销与清除，却无条件 `state = .anonymous` | 用户"退出登录"后把手机交给别人，下次 `restore()` 又自动登录回去 |
| 9 | Apple nonce 由客户端同时提供令牌与比对值，服务端不生成、不存储、不单次化 | 截获的有效 identity token 可在有效期内无限重放换取新会话（`exp` 严格无宽限把窗口压到约 10 分钟） |
| 10 | 注册/重置的 SMTP 同步投递造成时序侧信道 | 地址已占用走回滚（亚毫秒），未占用走完整 SMTP 会话（数百毫秒），构成干净的账号枚举 oracle |
| 11 | 令牌响应无 `Cache-Control: no-store`，客户端用共享 `URLSession.shared`（磁盘 `URLCache`，且进入设备备份） | 抵消了 Keychain-only 存储的设计意图 |

## P2：门禁本身的可靠性

12. **Release 密钥门禁的 3/4 条 marker 检查永远不可能命中。** `DEVELOPMENT_STRATEGY_FIXTURES` 是编译条件名，不会进二进制；`POKER_COACH_SMTP_PASSWORD` 只存在于 Go；`apple-identity-token` 只在 xctest bundle。我修好了 SIGPIPE 那个 bug，但**没有验证 marker 本身能否命中**——修复恢复了机制，却让三个空操作看起来在工作。唯一真正有效的是 `DevStrategyPack.json` 那条（已用反向测试验证）。

13. **`AnonymousAccountEntryTests` 不被任何门禁执行。** `verify-m1b.sh` 只列 `PokerCoachTests/*`，`verify-m1a.sh` 只跑另两个 UI 套件。它是"登录不阻断训练"的唯一证据。`verify-m1b.sh` 注释还声称"on both device families"，实际只用 iPhone destination。

14. 规格合规：56 个 Scenario 中 **25 COVERED / 30 WEAK / 1 UNCOVERED**。唯一未覆盖的是"超限批次"（`MaxBatchEvents`/`MaxBatchBytes` 零测试引用，且规格要求的 typed limit error 在代码里也是通用 `ValidationFailed`）。

## P3：规范违反

15. `AnyCodableValue` 把导出事件里的每个数字经 `Double` 往返，违反 `coding.md:16`"浮点数只用于最终展示"。当前量级（centi-BB/milli-BB/bp）都在 2^53 内不会损坏，但机制错误，且其文档注释谎称"keep exactly the shape the server stored"。对应测试 `testExportedEventsKeepTheServersShape` 的 fixture 里**一个数字都没有**。
16. `SystemAppleAuthorizationClient` 用 `@unchecked Sendable` 掩盖了真正无保护的可变状态（`continuation`、`rawNonce` 跨 async 与 delegate 回调无锁读写）。另两处 `@unchecked` 都有 `NSLock` 保护且注释说明，只有这处没有。
17. `e2e` 的 `pullAll` 用 `map[string]bool` 累积，**结构上无法检测重复事件**——而"每个事件只出现一次"正是它要证明的。

## 结论

- [ ] 通过 — 可归档
- [ ] 有条件通过
- [x] **不通过 — 需重大修改**

P0 全部修复并由真实跨语言回路验证之前，不得归档。
