# Capability: independent-account-access

## Requirement: 匿名离线连续性

The system SHALL allow a user without a remote account or active session to continue using deterministic training and local history.

### Scenario: 首次离线启动

- GIVEN APP 没有远端会话且网络不可用
- WHEN 用户启动 APP
- THEN 今日、学习、训练和复盘仍可进入
- AND 本地决策继续写入现有不可变 TrainingEvent 日志

### Scenario: 登录入口不阻断训练

- GIVEN 用户尚未登录
- WHEN 用户忽略账号入口并开始训练
- THEN 系统不强制展示登录墙
- AND 同步状态明确显示“仅保存在本机”

## Requirement: 邮箱密码注册

The system SHALL register a canonical email identity with a verified password policy and require email verification before remote synchronization.

### Scenario: 合法注册

- GIVEN 用户提交格式合法且未占用的邮箱以及 15–128 个 Unicode scalar、未命中弱密码列表的密码
- WHEN 服务端完成注册
- THEN 密码以带独立 salt 和参数的 Argon2id PHC 字符串保存
- AND APP 进入等待邮箱验证状态
- AND 未验证账号不能上传或下载训练事件

### Scenario: 不合规密码

- GIVEN 密码少于 15 个 Unicode scalar、超过 128 个 Unicode scalar 或命中弱密码列表
- WHEN 用户提交注册
- THEN 服务端拒绝注册并返回 typed validation error
- AND 系统不要求大小写、数字或符号组合规则

### Scenario: Unicode 密码长度边界

- GIVEN 密码包含由多个 UTF-8 字节表示的 Unicode scalar
- WHEN 客户端和服务端校验密码长度
- THEN 两端都按 Unicode scalar 而不是 UTF-8 字节计数
- AND 15 与 128 个 scalar 被接受，14 与 129 个 scalar 被拒绝

### Scenario: 邮箱枚举保护

- GIVEN 邮箱已经注册
- WHEN 未认证调用方再次请求注册或密码重置
- THEN API 返回与未注册邮箱不可区分的接受响应
- AND 日志不记录邮箱正文、密码或验证凭据

## Requirement: 邮箱验证与密码重置

The system SHALL use expiring, single-use email challenges for email verification and password reset.

### Scenario: 一次性邮箱验证

- GIVEN 用户收到仍在有效期内且未使用的验证凭据
- WHEN 用户提交正确凭据
- THEN 邮箱身份变为已验证
- AND 同一凭据再次提交被拒绝

### Scenario: 密码重置

- GIVEN 已验证用户完成有效的密码重置挑战
- WHEN 用户设置合规的新密码
- THEN 新密码替换旧密码
- AND 该账号的既有刷新会话全部失效

## Requirement: 邮箱密码登录

The system SHALL authenticate a verified email identity with a generic failure response and bind the installation profile to the remote user.

### Scenario: 成功登录并认领匿名历史

- GIVEN 当前安装有稳定 localUserID、deviceID 和尚未绑定的本地训练事件
- WHEN 已验证用户使用正确邮箱密码登录
- THEN 服务端创建该设备的独立会话
- AND 本地身份与历史绑定到远端用户但事件正文及 ID 不被改写
- AND 后续同步上传既有匿名历史

### Scenario: 通用登录失败

- GIVEN 邮箱不存在、尚未验证或密码错误
- WHEN 用户尝试登录
- THEN API 返回相同的认证失败语义
- AND 不泄露账号是否存在

## Requirement: Apple 登录与显式身份关联

The system SHALL authenticate Sign in with Apple credentials and map each verified Apple subject to one independent user.

### Scenario: 合法 Apple 登录

- GIVEN APP 获得带匹配 nonce 的有效 Apple credential
- WHEN 服务端完成签名、issuer、audience、expiry 和 nonce 校验
- THEN Apple subject 映射到稳定远端用户
- AND 当前安装的本地身份可按与邮箱登录相同规则绑定

### Scenario: 相同邮箱不自动合并

- GIVEN Apple 返回的邮箱与现有邮箱密码账号相同但用户未先认证现有账号
- WHEN 服务端处理 Apple 登录
- THEN 系统不依据邮箱自动合并身份
- AND 只有近期认证的账号持有者可以显式关联 Apple 身份

### Scenario: 无效 Apple credential

- GIVEN Apple credential 的签名、audience、expiry 或 nonce 任一无效
- WHEN 服务端验证凭据
- THEN 登录被拒绝
- AND 不创建用户、身份或会话
