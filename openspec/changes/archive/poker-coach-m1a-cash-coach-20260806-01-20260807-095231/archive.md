# 归档记录：poker-coach-m1a-cash-coach-20260806-01

## 基本信息

- Change ID：`poker-coach-m1a-cash-coach-20260806-01`
- 创建时间：2026-08-06
- 完成时间：2026-08-07
- 归档时间：2026-08-07T09:52:31+08:00
- 最终实现提交：`9179c21`
- 评审结论：通过，可归档

## 需求摘要

交付一个离线可运行的 M1A 现金局教练纵向切片：用户可在 iPhone/iPad 完成 6-max 100BB 现金局决策，提交行动与信心，获得基于 EV 的可解释专业反馈，并让不可变本地训练事件更新能力画像、今日训练和复盘。

## 技术方案摘要

- 使用 SwiftUI 原生支持 iPhone 与 iPad 自适应导航。
- 将稳定领域能力拆为 `PokerCore`、`StrategyContent`、`TrainingDomain` 三个本地 Swift Package。
- 使用带单位整数表达金额、EV 和策略频率。
- 使用带 checksum、版本、来源和审核状态的不可变策略包。
- 使用 append-only JSON Lines 训练事件建立本地优先的学习画像。
- Debug 提供明确标注的开发策略数据，Release 构建排除该资源。

## 规格变更摘要

全部为新增 Capability，无修改或删除：

| Capability | Requirements | Scenarios |
|---|---:|---:|
| `adaptive-native-shell` | 2 | 3 |
| `cash-decision-domain` | 4 | 7 |
| `versioned-strategy-content` | 3 | 6 |
| `explainable-decision-training` | 4 | 9 |
| `local-learning-profile` | 4 | 6 |
| `m1a-release-safety` | 2 | 3 |
| **合计** | **19** | **34** |

规格已合并到 `openspec/specs/<capability>/spec.md`，归档后主规格库为新的 Source of Truth。

## 验证摘要

- PokerCore：18 tests
- StrategyContent：25 tests
- TrainingDomain：21 tests
- PokerCoachTests：49 tests
- iPhone UI：1 test
- iPad UI：1 test
- Release simulator build：PASS
- Release 开发数据排除：PASS
- 规格合规：6/6 Capabilities、19/19 Requirements、34/34 Scenarios PASS

## 变更文件清单

实现范围共 94 个版本化文件，完整清单可由 `git diff --name-only fd5014c..9179c21` 复现，主要分组如下：

- 工程与构建：`.gitignore`、`project.yml`、`Config/`、`scripts/`
- 扑克领域：`Packages/PokerCore/`
- 策略内容：`Packages/StrategyContent/`
- 训练领域：`Packages/TrainingDomain/`
- App：`PokerCoach/`
- App 与 UI 测试：`PokerCoachTests/`、`PokerCoachUITests/`
- 项目文档：`README.md`、`docs/architecture/`、`docs/standards/testing.md`
- Change 工件：`proposal.md`、`design.md`、`tasks.md`、`review-proposal.md`、`review.md`、`archive.md`
