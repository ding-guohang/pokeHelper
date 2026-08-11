# 已知缺口

不是 bug 列表，是**已经查证、暂不修复、且必须在某个时点之前修复**的条目。每条记录为什么当时没修，以及什么事件会让它变成必须修。

写在这里的前提是：它已经被验证存在，不是猜测。修掉之后从本文件删除。

## 内容采纳后视图目录陈旧

- **内容：** `AppDependencies.adoptContent` 会换掉 `strategyProvider`、`localTrainingCatalog`、`installedContent` 与披露状态，但 Today 与 Review 在 SwiftUI 首次构建其 `@State` 视图模型时就捕获了目录副本。在此之后采纳的包，要等视图模型重建才生效。
- **为什么现在不修：** 该窗口今天不可达——`BundledOnlyContentSource.fetchCandidate()` 永远返回 nil，产品里不会发生采纳。让两个界面改从 provider 现算目录，会改动一批测试正在依赖的注入目录语义，代价不由现在这次修复承担。
- **什么时候必须修：** 接入真实更新源之前。加一个没人读的版次计数器不算修——那与「采纳了却什么都没装上」是同一类装饰。
- **发现时间：** 2026-08-11

## 历史条目的来源披露按 pack ID 解析，忽略内容版本

- **内容：** `installedContent` 以 pack ID 为键。同一个 pack ID 若在版本之间改变审核状态，早期版本下产生的历史事件会被按新状态披露。
- **相关约定：** [隐性约定](implicit-contracts.md) 的「历史训练固定内容版本」要求策略包升级不改写历史，历史事件保留原 pack ID 和 content version。事件本身确实带了 `strategyContentVersion`，是披露这一侧没有用它。
- **为什么现在不修：** 改为按 (packID, contentVersion) 取键之后，所有历史版本都会查不到而落到「内容来源未知」。哪一种更可取是产品判断——把已审核内容的历史标成来源未知，和把未审核内容的历史标成已审核，是两种不同的错——不适合在一次技术修复里默默选一个。
- **什么时候必须修：** 第二个内容版本上线之前。
- **发现时间：** 2026-08-11

## FileTrainingEventStore 位于领域包内

- **内容：** `Packages/TrainingDomain/Sources/TrainingDomain/FileTrainingEventStore.swift` 是一个 JSON Lines 文件存储实现，即具体存储实现，却与评分、画像、计划同处一个包。
- **相关约定：** [分层规则](layering.md) 第 3 条：TrainingDomain「不得依赖 SwiftUI、HTTP 或数据库实现」。协议 `TrainingEventStore` 留在领域包是对的，实现不是。
- **为什么现在不修：** 纯搬迁，196 行加三个测试文件，但触及 11 个使用方，其中多个测试文件当前有并发改动。在竞态里搬会把一次机械移动变成一次合并冲突。
- **什么时候必须修：** M2A 落 Session 记录持久化时一并做——那次本来就要在 Infrastructure 建存储，两处一起搬比分两次搬便宜。
- **发现时间：** 2026-08-11

## DecisionScenario 缺少 facing，签名两侧不对称

- **内容：** `SpotSignature.facing`（未面对下注 / 单次加注 / 再加注）在 Session 一侧由状态机精确给出，在内容一侧无法从 `BettingDecisionContext` 反推——跟注者与加注者投进底池的钱无从区分，「加注了几次」这个信息不在数据里。已核对 `CoreStrategyPack.json` 六个场景确认。
- **后果：** 频率报告的基准无法区分同一位置的不同面对情形（CO 未面对下注 24.86% 与 CO 面对 3bet 9.05%），而 design.md 决断 5 要求必须区分。
- **为什么现在不修：** 需要给 `DecisionScenario` 加 `facing` 字段，这会改变策略包字节与 `.sha256`，而该内容已由用户签为 `reviewed`。变动的只是声明性元数据、审核过的数字一个不变，但重新签署必须让用户知情——不让内容的审核状态被静默改写正是 `ReviewStatus` 与 `ContentOrigin` 存在的理由。
- **什么时候必须修：** M2A 的 T14（频率报告）之前。这是该任务的前置阻塞项。
- **发现时间：** 2026-08-11
