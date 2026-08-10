# M1B 执行台账

本文件记录**无法从 tasks.md 或代码本身低成本重建**的状态：任务进度、偏离计划的决策及其理由、跨任务承接的遗留项。

它纳入版本控制是有意的。Codex 的同类台账在 `.superpowers/sdd/tasks/progress.md`，而 `.superpowers/` 被 gitignore，导致换执行者时其中的延期项只能靠人工重读捞回。台账放这里就不会再丢。

**接手方式**：读本文件 → 读 `tasks.md` 中下一个任务的小节 → `git log --reverse main..HEAD` 看提交信息中的决策说明。不需要任何对话历史。

## 进度

基线 `3e06a94`（Codex 完成 Task 1–3 并通过其自身评审）。

| 任务 | 状态 | 提交 |
|---|---|---|
| 1 Go 服务与 MySQL 迁移 | 完成（Codex） | `9569ffc`..`40241d2` |
| 2 注册与邮箱验证 | 完成（Codex） | `40241d2`..`df7386c` |
| 3 登录/重置/限流 | 完成（Codex） | `df7386c`..`3e06a94` |
| 4 轮换会话与设备管理 | 完成 | `ebde522` |
| — 数据库选型文档修正 | 完成 | `0df59d4` |
| 5 Apple 校验与显式关联 | 完成 | `3a8031e` |
| 6 iOS 账号契约与 Keychain | 完成 | `9fe7b74` |
| 7 Profile 隔离与认领 | 完成 | `eddd1d7` |
| 8 可恢复 Outbox | 完成 | `51e811f` |
| 9 服务端事务化同步 | 完成 | `ae48f1b` |
| 10 iOS SyncEngine 与收敛 | 完成 | `8d40593` |
| 11 服务端重认证/导出/删除 | 完成 | `847c160` |
| 12 iOS 设备/导出/删除/离线退出 | 完成 | `d8e9c35` |
| 13 双设备 E2E 与 Release 门禁 | 完成 | `2e6293c` |

tasks.md 的 checkbox 一律不勾选，与 Codex 的做法保持一致，避免两个执行者在同一文件上制造冲突。进度以本表为准。

一个提交无法记录自己的哈希，所以任务提交落地后由一个补记提交填入 SHA。

## 偏离计划的决策

计划是执行前写的，以下几处在对着真实代码实现时必须调整。每条都在对应提交信息里有完整说明。

### Task 5：`AppleService.Link` 不接受 `session.Principal`

计划写的是 `Link(context.Context, session.Principal, auth.AppleLinkInput)`。但 Task 4 的适配器让 `session` 依赖了 `auth`（实现 `auth.SessionIssuer`），`auth` 再反向 import `session` 就是**循环依赖，无法编译**。

改为 `auth` 定义自己的 `Principal`，由 httpapi 在边界转换。这与 Task 3 已确立的原则一致——tasks.md 第 220 行原文即要求 `auth.DeviceMetadata` 与 `auth.SessionTokens` 保持独立于 session 包。

### Task 5：Apple 令牌的 `exp` 不给时钟宽限

初版对 `exp` 和 `iat` 都放了 2 分钟宽限，被自己的测试抓出来。对 `exp` 宽限等于接受刚过期的凭据，白白拉长重放窗口；Apple identity token 本就短命。现在只对 `iat` 宽限（客户端时钟偏快是良性的），`exp` 严格执行。

### Task 5：新增两个错误码

`reauthenticationRequired`（HTTP 401）与 `identityConflict`（HTTP 409），并补进 `httpapi.writeAuthError` 的映射，否则会落入 500 分支。Task 5 的 covers 行包含 `account-data-rights/近期重新认证`，定义该语义在其范围内。

### Task 7：新增 M1A 安装迁移（计划未要求）

M1A 把事件日志放在 `Library/PokerCoach/training-events.jsonl`、身份放在 UserDefaults。改用 profile 目录后不迁移的话，**升级用户会打开一个空历史**。新增 `ProfileMigration`，用目录改名保证字节不变，并把 UserDefaults 身份写入 profile 记录，附 3 个测试。

### Task 7：`ProfileRecordFile` 与 actor 分离

启动是同步的（`AppDependencies.live()` 不是 async，改成 async 会波及 `AppBootstrap` 及其 273 行测试）。把文件读写逻辑抽成 `ProfileRecordFile`，actor 只负责串行化，同步启动路径与并发路径共用同一实现，不做两份。

### Task 9：请求体必须已是规范形式

服务端拒绝语义等价但编码不同的 body。接受它们会让同一批事件产生两个哈希，幂等重放随即失效。Go 侧重新编码后与收到的字节比对，不一致即 `validationFailed`。

## 跨语言字节契约

`Contracts/training-event-upload-v1.json` 及其 `.sha256` 是 Swift 与 Go 之间的硬契约，**两侧都有逐字节断言**：

- Swift：`PokerCoachTests/FileOutboxStoreTests.testCanonicalEncodingMatchesTheSharedContractFixtureAndHash`
- Go：`Server/internal/sync/upload_test.go` 的 `TestCanonicalHashMatchesTheSharedContractFixture`

要求：键按字典序、无空白、时间为 UTC RFC 3339 毫秒精度带 `Z`。Go 侧靠**结构体字段按字母序声明**实现（`encoding/json` 按声明顺序输出）——重排 `sync.Event` 的字段会静默破坏所有幂等重试。

## 组合根

Task 11 补齐了 `httpapi/router.go` 与 `cmd/api/main.go`，服务现在可以真实启动。各 feature 仍各自持有构造器以保持独立可测，`NewRouter` 用 `firstMatch` 回落链把它们串起来（Go 的 `ServeMux` 无法直接合并）。

生产环境强制要求的环境变量（缺失即启动失败，不做静默降级）：

| 变量 | 缺失后果 |
|---|---|
| `POKER_COACH_MYSQL_DSN` | 生产必填（config 已有校验） |
| `POKER_COACH_THROTTLE_SECRET` | 缺失会导致每次重启重置全部限流窗口 |
| `POKER_COACH_APPLE_CLIENT_ID` | Apple 令牌的 audience 校验失去意义 |
| SMTP 全套 | 生产不允许回落到开发邮件器（否则验证链接会写进日志） |

## 测试替身集中在一处

`AccountAPI` 是个胖协议，每加一个操作，所有测试替身都会编译失败（Task 12 一次就打断了三个）。现在统一继承 `PokerCoachTests/Support/StubAccountAPI.swift`：基类给出中性实现，各测试只 override 自己要验证的方法。协议再扩展时只改这一个文件。

## 遗留项的决断（Task 13 已处理）

1. **auth 写接口接受非 JSON Content-Type —— 决定不强制。** 强制 `application/json` 主要防的是浏览器 simple request 类的 CSRF，而该风险来自 cookie 这种环境授权。本 API 只认 bearer 令牌，不存在环境授权，因此这项检查在这里几乎不增加安全性，却要改动全部写接口与其测试。若将来引入任何基于 cookie 的会话，此决定必须重新评估。
2. **X-Forwarded-For 测试的占位 IP —— 已修。** 原来用 `198.51.100.a` 这类非法地址，即使处理器开始信任该 header，测试也会因解析失败而通过，等于没在验证。现改为不同的合法地址。
3. **Retry-After 边界 —— 已补。** `internal/httpapi/retry_after_internal_test.go` 覆盖亚秒向上取整、零值下限为 1、整秒保持、含毫秒进位四种情况。并发重置令牌与注册 6/26 边界未补：现有并发测试已覆盖同类竞争路径（同一 refresh 令牌并发轮换、同一 Apple subject 并发首登），继续堆叠边际收益有限。
4. **`AccountServiceBaseURL` 默认指向 `https://127.0.0.1:8443`** —— M1B 不含生产部署（计划明确排除），Info.plist 的同名键可覆盖。**上架前必须替换。**
5. **按 profile 路由的覆盖范围** —— 事件存储、Outbox、sync state（checkpoint 与 acknowledgement）、corruption backups 均已随 profile 目录切换；pending revocation 存放在 Keychain 单一保管库中，按安装而非按 profile，因为它代表"这台设备待撤销的令牌"，与用哪个档案训练无关。

## 验证命令

M1B 全部门禁收敛到一条命令：

```bash
bash scripts/verify-m1b.sh
```

它按序执行 M1A 回归 → Go 静态检查与单测 → 隔离 MySQL 上的集成与双设备 E2E → iOS 账号与同步测试 → Release 密钥门禁 → `git diff --check`。

分步排查时可单独运行：

```bash
cd Server && go test ./... && go vet ./... && go vet -tags=integration ./... && gofmt -l .
bash scripts/test-server-mysql.sh go test -tags=integration ./...
bash scripts/verify-m1a.sh
bash scripts/check-m1b-release-secrets.sh --sources-only   # 跳过产物扫描，快
```

跑 `-run` 过滤时务必核对实际执行的用例数：本轮出现过一次 `-run Apple` 把测试名不含 "Apple" 的两个用例静默过滤掉的情况。

## 评审发现的产品级缺陷（已修）

四路并行评审独立收敛到同一结论：**门禁全绿，但没有一个用户能登录。** 详见 `review.md`。

根因是一句话：每一侧的测试都用自己的替身，**没有任何测试带着真实数据穿过 Swift↔Go 边界**。tasks.md 要求的 `LiveServerSyncContractTests` 与 `test-live-m1b.sh` 未被创建，那条回路本该在第一秒抓到下面全部四条。

| 缺陷 | 修复 |
|---|---|
| iOS 送 `device.appVersion`，Go 无该字段且 `DisallowUnknownFields` → 登录与 Apple 登录必返 400 | `auth.DeviceMetadata` 增加 `AppVersion` 并贯通到 `devices.app_version` |
| Swift 把 UUID 编码为大写，服务端只收小写 → 任何上传必被拒 | 服务端两种大小写都接受，`UUIDBytes` 归一化后入库 |
| `verify-email` 返回 204，iOS 却解码 token 对 → 验证必失败 | iOS 改为不解码；验证只确认地址，不签发会话 |
| `/v1/auth/resend-verification` 无服务端路由 → 404 | 新增该端点，枚举安全，并作废此前未消费的验证挑战 |
| `SyncEngine`、`ActiveProfileController`、`onAccountDeleted` 只在测试里被构造 → 上线后永不同步、账号共用同一档案、删除本机数据是空操作 | 新增 `SyncCoordinator` 组装三层，并由 `SyncCoordinatorTests` 断言**应用被装配**而非零件可用 |

配套：一次被服务端拒绝的批次原本会**永久卡死上传与拉取**（upload 先于 pull，抛错即中止），现在重试三次后隔离该批次，事件留在盘上并可上报。

## 评审发现的安全缺陷（已修）

| 缺陷 | 修复 |
|---|---|
| 注册与重置请求消费的是**登录**限流键 → 知道邮箱即可用 6 个未认证请求永久锁死账号，且受害者无法登录来清除 | 新增 `signup` 域，与登录预算分离；`TestSignupTrafficCannotLockTheOwnerOutOfLogin` 锁住该属性 |
| `/v1/auth/reauth` 完全没有限流 → 被盗会话可全速爆破明文密码，且每次 19 MiB Argon2 |`account.Service` 接入限流：哈希前先检查预算，失败计数，成功清零 |
| `logOut()` 用 `try?` 吞掉 Keychain 故障却谎报成功 → 下次启动自动登录回去 | 故障如实上报，状态不置为 anonymous |

## 修复记录：三个曾经形同虚设的检查

### Release 门禁的三条 marker 永远不可能命中

`DEVELOPMENT_STRATEGY_FIXTURES` 是编译条件名，不进二进制；`POKER_COACH_SMTP_PASSWORD` 只存在于 Go；`apple-identity-token` 只在 xctest bundle。我此前修好了 SIGPIPE 那个 bug，却没验证 marker 本身能否命中——**修复恢复了机制，却让三个空操作看起来在工作**。现改为可真实出现在 Swift 二进制里的 marker，并加了一条"扫描确实读到了内容"的自证断言。

### UI 套件从不被门禁执行，且只对 iPhone 成立

`AnonymousAccountEntryTests` 不在任何 `-only-testing` 列表里。纳入门禁后第一次在 iPad 上跑就失败了——它假设有 TabBar，而 iPad 用 `NavigationSplitView`。现已按布局适配并在两个机型上执行。

### 契约 fixture 对大小写完全盲视

`training-event-upload-v1.json` 原来的 UUID 只含数字，所以两侧的逐字节断言看不见大小写差异——这正是大写 UUID 能一路走到线上的原因。fixture 已换成含十六进制字母的标识符，并新增 `TestTheSharedContractFixtureExercisesHexLetters` 防止再次退化。

## 修复记录：两个曾经形同虚设的检查

### `strings | grep -q` 在 pipefail 下会把命中变成未命中

`scripts/check-m1b-release-secrets.sh` 初版用 `strings "$binary" | grep -Fq "$marker"` 扫描 Release 产物。`grep -q` 一旦匹配就立即退出，producer 收到 SIGPIPE，在 `set -o pipefail` 下整条管道返回 141——于是**真的扫到 marker 反而被判为没扫到**，那几条检查全部形同虚设。现改为先把 `strings` 输出捕获到变量再匹配。该门禁已用「故意破坏 Release 排除配置」的反向测试验证过确实会失败。

### 一个曾经形同虚设的安全测试

`TestVerifyRejectsATamperedSignature` 初版翻转签名 base64 的**末字符**。256 字节签名编码为 342 字符，末字符含 4 个填充位——当末字符恰为 `'A'` 时翻成 `'B'` 只改动填充位，解码回来是同一份签名，验签照常通过。该测试因此有概率**没有验证任何东西**，且表现为偶发失败。

现改为翻转解码后签名的首字节。同类断言若涉及 base64，一律应作用于解码后的字节。
