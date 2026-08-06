# 架构知识库

## 项目信息

- **项目名称：** Poker Coach（仓库：porkHelper）
- **项目类型：** 绿地原生 iOS/iPadOS 教学 APP，包含独立同步后端
- **客户端技术栈：** SwiftUI、Swift 6.2.3、Xcode 26.2、XcodeGen、Swift Package Manager
- **服务端技术栈：** Go、PostgreSQL、HTTPS 增量同步 API、对象存储
- **当前阶段：** 产品设计和 M1A 实施计划已批准，源代码尚未创建
- **源码入口：** M1A 将创建 `PokerCoach/` 与 `Packages/`

## 模块结构

以下是已批准的目标模块。文件数为初始化时的实际值。

| 模块 | 路径 | 当前文件数 | 职责 |
|---|---|---:|---|
| 产品设计与计划 | `docs/superpowers/` | 3 | 产品真值、里程碑和可执行任务 |
| PokerCore | `Packages/PokerCore/` | 0 | 牌、精确金额、合法行动和牌局规则 |
| StrategyContent | `Packages/StrategyContent/` | 0 | 版本化课程、场景、频率、EV 和求解假设 |
| TrainingDomain | `Packages/TrainingDomain/` | 0 | 评分、训练事件、能力画像和每日计划 |
| SwiftUI App | `PokerCoach/` | 0 | iPhone/iPad 的今日、学习、训练和复盘体验 |
| Sync Backend | 后续 M1B 确定 | 0 | 独立身份、事件同步、内容分发和用户数据治理 |

## 分层与依赖关系

```text
SwiftUI Features
  ↓ 依赖协议与展示模型
TrainingDomain
  ↓ 使用场景与精确扑克类型
StrategyContent → PokerCore

App Infrastructure
  ├─ 本地事件存储
  └─ M1B Remote Sync Client → Go API → PostgreSQL / Object Storage
```

依赖只能沿箭头方向。网络、认证和数据库 DTO 不得进入 PokerCore、StrategyContent 或 TrainingDomain。

## 高频变更区域

仓库只有两个初始化提交，当前变更集中在文档。

| 文件/目录 | 近期变更次数 | 风险评估 |
|---|---:|---|
| `docs/superpowers/specs/` | 2 | 中；产品真值，修改必须经用户批准 |
| `docs/superpowers/plans/` | 1 | 中；实施步骤与接口契约 |
| `.gitignore` | 1 | 低 |

## 关键依赖

- 当前没有第三方运行时依赖。
- XcodeGen 已安装，用于从 `project.yml` 生成 Xcode 工程。
- M1A 优先使用 Apple 平台和 Swift 标准库能力。
- 新增第三方依赖必须说明用途、替代方案、许可证和锁定版本。

## 相关文档

- [分层规则](layering.md)
- [模块与组件](components.md)
- [独立账号与同步](sync.md)
- [隐性约定](implicit-contracts.md)
- [已批准产品设计](../superpowers/specs/2026-08-06-texas-holdem-coach-design.md)
- [实施路线](../superpowers/plans/2026-08-06-poker-coach-implementation-roadmap.md)

