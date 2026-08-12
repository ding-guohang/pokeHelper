# 已知缺口

不是 bug 列表，是**已经查证、暂不修复、且必须在某个时点之前修复**的条目。每条记录为什么当时没修，以及什么事件会让它变成必须修。

写在这里的前提是：它已经被验证存在，不是猜测。修掉之后从本文件删除。

## 内容采纳后视图目录陈旧

- **内容：** `AppDependencies.adoptContent` 会换掉 `strategyProvider`、`localTrainingCatalog`、`installedContent` 与披露状态，但 Today 与 Review 在 SwiftUI 首次构建其 `@State` 视图模型时就捕获了目录副本。在此之后采纳的包，要等视图模型重建才生效。
- **为什么现在不修：** 该窗口今天不可达——`BundledOnlyContentSource.fetchCandidate()` 永远返回 nil，产品里不会发生采纳。让两个界面改从 provider 现算目录，会改动一批测试正在依赖的注入目录语义，代价不由现在这次修复承担。
- **什么时候必须修：** 接入真实更新源之前。加一个没人读的版次计数器不算修——那与「采纳了却什么都没装上」是同一类装饰。
- **同源扩散（M2B）：** Hand Lab 的内容匹配（`ImportedHandContentMatcher`）与补救训练（`HandLabView.makeRemediationSession`）都从 `BundledContentLoader.loadPreferredPack()` 现读随包的已审核包，而非 `dependencies.strategyProvider`——这是故意的（dev 构建的 provider 是无 `rfi-btn` 的演示包，分析/补救必须对着已审核内容判定）。发布构建启动时二者相等，故补救事件与直接训练事件的 `strategyPackID`/`strategyContentVersion` 一致；但一旦 `adoptContent` 可达并换了包，分析与补救仍读旧的随包内容，补救事件会记陈旧包号。接入真实更新源时，分析/补救的取包口径要与被采纳内容一并对齐。
- **发现时间：** 2026-08-11（M2B 补救切片扩散：2026-08-12）

## 历史条目的来源披露按 pack ID 解析，忽略内容版本

- **内容：** `installedContent` 以 pack ID 为键。同一个 pack ID 若在版本之间改变审核状态，早期版本下产生的历史事件会被按新状态披露。
- **相关约定：** [隐性约定](implicit-contracts.md) 的「历史训练固定内容版本」要求策略包升级不改写历史，历史事件保留原 pack ID 和 content version。事件本身确实带了 `strategyContentVersion`，是披露这一侧没有用它。
- **为什么现在不修：** 改为按 (packID, contentVersion) 取键之后，所有历史版本都会查不到而落到「内容来源未知」。哪一种更可取是产品判断——把已审核内容的历史标成来源未知，和把未审核内容的历史标成已审核，是两种不同的错——不适合在一次技术修复里默默选一个。
- **什么时候必须修：** 第二个内容版本上线之前。
- **发现时间：** 2026-08-11
