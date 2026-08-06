<!-- harness:setup:begin -->
## Harness 工作流

| 命令 | 用途 |
|---|---|
| `/harness-setup` | 初始化知识库与 OpenSpec |
| `/harness-propose` | 创建需求 proposal |
| `/harness-review-proposal` | 审核需求完整性 |
| `/harness-plan` | 设计方案和任务分解 |
| `/harness-apply` | 执行实现 |
| `/harness-review` | 代码评审 |
| `/harness-archive` | 归档完成变更 |
| `/harness-knowledge` | 管理项目知识库 |
| `/harness-workflow` | 查看工作流状态 |

## Superpowers

- 执行前检查适用 skill。
- 优先级：用户指令 > Superpowers skill > 默认行为。
- brainstorming、debugging 等流程 skill 先于实现 skill。
- 所有代码变更先经 Harness 工作流分流。

## 项目知识库

| 路径 | 内容摘要 |
|---|---|
| `docs/architecture/index.md` | SwiftUI、领域包和独立后端总览 |
| `docs/architecture/layering.md` | 分层与禁止依赖 |
| `docs/architecture/components.md` | 模块和稳定接口 |
| `docs/architecture/sync.md` | 本地优先的独立同步 |
| `docs/architecture/implicit-contracts.md` | 策略与评分隐性约定 |
| `docs/standards/index.md` | 编码、测试、内容和安全规范入口 |
| `docs/product/index.md` | 产品规则与产品真值入口 |
| `docs/superpowers/specs/` | 已批准产品设计 |
| `docs/superpowers/plans/` | 实施路线和详细计划 |
<!-- harness:setup:end -->

