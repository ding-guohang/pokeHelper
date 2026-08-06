# 架构知识库

## 项目信息

- **项目名称：** Poker Coach（仓库：porkHelper）
- **项目类型：** 绿地原生 iOS/iPadOS 教学 APP，包含独立同步后端
- **客户端技术栈：** SwiftUI、Swift 6.2.3、Xcode 26.2、XcodeGen、Swift Package Manager
- **服务端技术栈：** Go、PostgreSQL、HTTPS 增量同步 API、对象存储
- **当前阶段：** M1A 离线现金局教练纵向切片已实现并进入最终评审收口；M1B 独立账号与同步尚未开始
- **源码入口：** SwiftUI APP 位于 `PokerCoach/`，领域包位于 `Packages/`，工程真值为 `project.yml`

## 模块结构

以下模块已建立稳定职责边界。这里不记录易过时的文件数量，实际结构以仓库和 `project.yml` 为准。

| 模块 | 路径 | 职责 |
|---|---|---|
| 产品设计与计划 | `docs/superpowers/`、`openspec/` | 产品真值、里程碑和可执行任务 |
| PokerCore | `Packages/PokerCore/` | 牌、精确金额、合法行动和牌局规则 |
| StrategyContent | `Packages/StrategyContent/` | 版本化课程、场景、频率、EV 和求解假设 |
| TrainingDomain | `Packages/TrainingDomain/` | 评分、训练事件、能力画像和每日计划 |
| SwiftUI App | `PokerCoach/` | iPhone/iPad 的今日、学习、训练和复盘体验 |
| Sync Backend | 后续 M1B 确定 | 独立身份、事件同步、内容分发和用户数据治理 |

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

## 活跃变更区域

| 文件/目录 | 风险评估 |
|---|---|
| `PokerCoach/Features/` | 中；必须保持展示层不重算领域真值 |
| `Packages/StrategyContent/` | 高；内容格式、校验和历史版本必须可追溯 |
| `Packages/TrainingDomain/` | 高；评分、事件和训练优先级属于稳定领域契约 |
| `docs/superpowers/specs/`、`openspec/changes/` | 中；产品真值和当前变更规格，修改必须经批准 |

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
