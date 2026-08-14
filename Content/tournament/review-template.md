# 锦标赛 Push/Fold 内容审核记录

> 填写并提交本文件**不会**改变任何内容包的状态。把 `unverifiedDraft` 晋升为
> `reviewed` 是一个独立操作；它必须签发新的 `contentVersion`、记录具名人类审核人与
> 时间，并重新运行黄金回归。本次为 AI 辅助的职业牌手视角复核，不能冒充具名人类签署。

## 1. 被审内容

- Change / 批次：`strategy-content-import-hu-pushfold-20260813-01`
- 覆盖：单挑，SB=0.5BB/BB=1BB，无 ante，rake=0，chipEV，深度 1–20BB
- 内容版本（被审）：`2026.08.13-hu-pf.1`
- 拟晋升到的新内容版本：`未分配（本次审核阻断，不签发新版本）`
- 实际覆盖：20 个深度、39 张表、6,591 个手牌行；1BB 仅 SB 决策，2–20BB 各含
  SB Open-Jam 与 BB Call-Jam

## 2. 来源与可复现性

- 求解器仓库 / commit：
  `b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`
  （BSD-2-Clause）
- 锁定输入 SHA-256（见 `source-lock.json` 与 `golden-manifest.json`）核对：
  **否（存在 fail-closed 缺陷）**
  - 当前缓存中 LICENSE、Cargo.lock、3 个 Rust 源文件和 equity binary 与锁值一致。
  - 锁定的 `Cargo.toml` 期望
    `386a67bcde9a4f8f791e562fce5d280d237d16a03f5d2fe3479fc282563bda1a`，
    当前缓存实际为
    `27ee25b3cd868bbb7e1e6940ee37c306e49a7e7eb27d223449235d71d1145d88`。
  - `generate-hu-pushfold.py` 在 `.verified` 只含正确 commit 时直接复用缓存，不重新计算
    锁定哈希；随后还会为导出二进制改写被锁定的 `Cargo.toml`。因此标记创建后的任意
    锁定文件变化都可能绕过门禁。
- `bash scripts/verify-tournament-content.sh` 重跑逐位一致：
  **是，但不足以证明缓存未被篡改**
  - 2026-08-14 重跑完成：20 个 normalized、20 个 export、20 个 pack、20 个 sidecar
    与 golden manifest 逐位一致；StrategyContent / StrategyTooling / Python 测试和
    package-layering 门禁通过。
  - 该命令使用上述持久缓存与 `.verified` 快路径，所以“逐位一致”只证明当前缓存能重现
    当前产物，不能证明脚本满足“锁定输入变化即失败”。
- 独立 equity 重算：`verify-equities.py` 于 2026-08-14 fresh 重跑通过；从零实现的
  7-card 评估器对 12 组代表性全下 matchup 做完整公共牌枚举，与锁定 equity 表对应
  12 项逐项一致，最大偏差 `0.00e+00`（阈值 `1e-6`）。证据见
  `equity-verify-report.md`。
  - 这是 **12 个 anchor** 的独立验证，不是 1,326 × 1,326 equity 矩阵的全量重算；
    不能写成“整张 equity 表逐项全部独立验证”。
- Rust 工具链锁定：**否**。manifest 记录 `rustVersion=1.56.0`，实际执行的是
  `rustc/cargo 1.97.1`，生成器未校验版本。
- 每深度 iterations 与 NashConv：全部在 10,000 iterations 冻结；最大 NashConv
  `2.1349537054904388e-7 BB/hand`，出现在 **17BB**。

| 深度 | Iterations | NashConv (BB/hand) | Snapshot SHA-256 |
|---:|---:|---:|---|
| 1 | 10,000 | 1.7759231585312563e-16 | `19406a09a44da3d1c52f5c84e0bc7346401e0404579eb303d154e11f4d1af212` |
| 2 | 10,000 | 3.1891813731532714e-8 | `85ad18c6c23399c76c47c1a8c9ed017771c76474404bf92c6c7ad18c78c6145c` |
| 3 | 10,000 | 1.2663620747171977e-7 | `a741d8e83ff29debe90b23029d5c3e45c82ff9a6e37218bf57044805dbe4a3a8` |
| 4 | 10,000 | 6.00467914280145e-9 | `07c659c20f364a7cf3d53deea5515734a7c968ce1548189aff47681f01f5a264` |
| 5 | 10,000 | 8.922779224512789e-8 | `3be6c9bcfde67d39295b26af83c2b172bc241db81f96b79cfe5a2900b457f1c7` |
| 6 | 10,000 | 3.655325676171772e-8 | `59f7ecab309236973065de7c9e382653c8199207d0d81f9af7e5f89ee95b3818` |
| 7 | 10,000 | 1.0803658120200899e-7 | `7119c2d4057db0073c8f3c59eec704c0e2a69b83b3681026cf0d1132add58074` |
| 8 | 10,000 | 1.260074242153547e-7 | `feec3dc28559e63969b09901f116c9b4c330e9d447452bb0395ab47dd7c29af3` |
| 9 | 10,000 | 3.601896939042781e-8 | `de89f3aa21fa5065c2859c2144802ae38cdfbddb9ac62d7a091dfeb0bc62233f` |
| 10 | 10,000 | 3.855556063303567e-8 | `2b40091e09503c81c310b40ef97aaa55ba20008faf00da24694fe965869138c1` |
| 11 | 10,000 | 6.408911978894594e-8 | `098a775e7ad1e13dc10c62518652b0fe8233e99161238683d0e1fff663e6e004` |
| 12 | 10,000 | 1.4356588640129786e-8 | `f0af66f4146b6ffeff14ff227b2cf3af20b832a43239e5e8120e4675467e70d6` |
| 13 | 10,000 | 2.73976717701796e-8 | `590efa4451d3db5c92f2b0eb8761de6dfd5d7712dd5ada68cfd3889faf98e1eb` |
| 14 | 10,000 | 3.3268184346235685e-8 | `34932c0d299373a8dfde36a19a7d93207baa502206bd3c8239b66ea5ff9863ea` |
| 15 | 10,000 | 6.837301796958073e-8 | `7cbc1556fb8646a3a9fc905d29ade68e2cb4d1f329efabb8f188f0943f754874` |
| 16 | 10,000 | 4.620781129949236e-8 | `a4c5e17e56a753c5118aa1ec92314cc7c00ee01167ef0896303e703fd7aa5cca` |
| 17 | 10,000 | 2.1349537054904388e-7 | `d75a7a0a13ad8ad93ecdec5f15a0408e9a25a6aaaf413bf914b52fe52086f6a8` |
| 18 | 10,000 | 5.1703957365534237e-8 | `b0dc781c05803864c1e6903c0b14084edc1ffdc47c7fcddd94641e29299e15b8` |
| 19 | 10,000 | 2.4456449115861645e-8 | `50bdb2bdbc83e4eb45ac8d6ee6fafb145ae2d2c36b88a52bdf5fae3526ec9164` |
| 20 | 10,000 | 4.585444512983372e-8 | `2046b484aaafe9edde95a3cf730ccf34d7133a568d5e573dcb87fc53f80e81ba` |

## 3. 独立参照与许可

- 独立最佳回应核对：`cross-check-exploitability.py` 于 2026-08-14 fresh 重跑通过，
  20 个深度均显示 `0.00000 BB/hand`，见 `cross-check-report.md`。
  - 该实现独立重算最佳回应，但复用锁定 equity 表；上面的 12-anchor 独立枚举为其提供
    额外旁证。
  - BB 增益在实现中按“面对 jam 条件下”归一化后与 SB root 增益相加，因此其合计口径
    不是严格等同于求解器的 root NashConv；本批次两项增益均近零，不影响定性结论。
- 独立参照：
  [HoldemResources.net HeadsUp Push/Fold Nash Equilibrium](https://www.holdemresources.net/hune)，
  `No Ante`，两人 push-or-fold NLHE；SB 仅 jam/fold，BB 面对 jam 仅 call/fold。
- 参照原始数据：页面公开下载的未简化 0.05BB 步长 push/call CSV，ZIP SHA-256
  `650da7525b35e12adbc03df26d6690c30b583ff4b7d930156c104012a040ec9d`，
  ZIP 内文件日期 `2012-05-06`，审核访问日期 `2026-08-14`。
- 可比假设：HU、开局有效深度、SB=0.5BB/BB=1BB、无 ante、rake=0、chipEV、
  jam-or-fold，和被审批次一致。
- 许可边界：网页公开提供原始数据用于推导图表，但未标明再分发许可证；本次只做本地数值
  核对，不把 HRC 数据复制进产品或仓库。
- 商业平台数据仅经用户本地合法导出转换：**未使用**。

## 4. 边界手交叉核对

全量对 HRC 原始 CSV 比较了 6,591 个“深度 × 位置 × 手牌”频率：

- 6,591 / 6,591 的多数动作（频率是否 ≥50%）一致。
- 6,582 / 6,591 的频率差异不超过 1 个百分点。
- 4 项差异超过 5 个百分点，均为双方仍选择相同多数动作的混合边界牌；最大绝对差异
  11.55 个百分点。
- HRC 页面明确说明精确解包含大量混合频率，不同独立解及其离散化可能在边界牌上不同。
  这些差异不构成明显的范围方向错误，但应保留在审核证据中。

| 深度 | 位置 | 手牌 | 本批次频率 | HRC 频率 | 差异（百分点） |
|---:|---|---|---:|---:|---:|
| 3BB | SB Open-Jam | 85o | 84.45% | 96.00% | −11.55 |
| 3BB | SB Open-Jam | T2o | 41.02% | 35.00% | +6.02 |
| 6BB | SB Open-Jam | 63s | 0.96% | 6.00% | −5.04 |
| 8BB | SB Open-Jam | Q4o | 19.24% | 19.00% | +0.24 |
| 8BB | BB Call-Jam | Q7o | 52.82% | 53.00% | −0.18 |
| 10BB | SB Open-Jam | 43s | 71.15% | 72.00% | −0.85 |
| 10BB | BB Call-Jam | Q6s | 40.20% | 40.00% | +0.20 |
| 11BB | SB Open-Jam | 76o | 5.44% | 5.00% | +0.44 |
| 11BB | BB Call-Jam | K6o | 54.83% | 56.00% | −1.17 |
| 20BB | SB Open-Jam | Q5s | 87.47% | 76.00% | +11.47 |

职业牌手视角的范围形态检查：

- SB 加权 jam 率从 1BB 的 100.00% 随深度总体收紧到 20BB 的 40.23%；BB 加权
  call 率从 2BB 的 100.00% 收紧到 20BB 的 21.72%，方向合理。
- 8–12BB 的主要边界牌与 HRC 一致；10BB 的 43s jam、Q6s call 都表现为合理混合。
- 15BB 以上的 jam-or-fold 仍是该受限博弈的 Nash 解，不等于真实无限注牌局的完整最优
  策略；产品必须继续披露“全下/弃牌模型”，不能把它表述成所有实战场景都应直接全下。

## 5. 频率、EV 与哈希不变量

- 每表 169 手牌齐全、每行 bps 和 = 10,000：**是**
- 20 个深度 / 39 张表 / 6,591 行完整：**是**
- SB fold EV 恒为 −500 milli-BB、可达 BB fold EV 恒为 −1,000 milli-BB：**是**
- EV 与频率由同一 normalized snapshot 标识：**是（当前产物）**
- 独立最佳回应核对：**是**，20 个深度均显示 `0.00000 BB/hand`
- 独立 equity anchor 重算：**是**，12 / 12 最大偏差 `0.00e+00`
- normalized / export / pack / sidecar / golden manifest 哈希一致：**是**
- 全部 20 个 pack 保持 `origin=solver`、`reviewStatus=unverifiedDraft`，且 reviewer/time
  为空：**是**

注意：当前 validator 对“伪造非 fold EV 后重新计算无密钥 snapshot hash”的负向情形没有
充分门禁，因此“同一 snapshot 标识存在”不等于独立证明 EV 计算过程未被替换。

## 6. 阻断问题

### Critical

1. 修复来源缓存复验：每次生成必须重新核对所有锁定输入，或把导出补丁放在不修改锁定
   checkout 的独立构建目录；`.verified` 不能成为跳过哈希的永久通行证。
2. source lock / golden evidence 必须绑定本地导出补丁与生成器版本或 SHA-256，并实际验证
   所声明的 Rust 工具链。
3. 加强 normalized validator，使其验证 commit、license、盲注、ante、equilibrium、
   iterations、`exploitability = NashConv / 2`、行动 EV/频率 snapshot 绑定，而不只是验证
   可由被审文档自身重算的哈希。
4. M5 虽新增 `promote-tournament-packs.py`，但 `strategy-import` 已移除锦标赛
   `unverifiedDraft` 守卫；任何调用者仍可直接传 `--review-status reviewed`、任意非空
   reviewer/time，绕过 review record 与三项 evidence。`reviewed` 目前不是晋升路径的
   唯一可达结果。

### Important

1. 最终 pack 的 `generatedSource` 未绑定生成配置、批次哈希、snapshot、iterations 和
   NashConv；仅写了求解器 commit、深度和固定时间。
2. pack importer 自身接受不完整的 export 集合，不能独立保证恰好 1–20BB 全批次。
3. M5 晋升脚本已能用新 manifest 重导并比较全部非 manifest 策略内容，能阻止晋升时
   偷改 frequency/EV；“没有晋升 workflow”这一旧问题已修复。
4. 但晋升 evidence 仅信任 review JSON 自报的 `0.0 / 0.0 / true`，未运行或哈希绑定
   equity、exploitability、逐位重现报告及目标批次；`NaN` 也可绕过数值上限比较。
5. 晋升脚本未强制恰好 01–20BB、未验证 baseline 是签入的 golden `unverifiedDraft`，
   也未强制新 `contentVersion` 与 baseline 不同；promotion record 缺 baseline/export/
   evidence artifact 哈希。
6. 两个独立证据脚本尚未接入 `verify-tournament-content.sh`，静态报告漂移不会使主门禁
   失败。

## 7. 结论

- 审核人：`Codex（AI 辅助复核；职业牌手视角模拟；非具名人类策略审核人）`
- 审核时间：`2026-08-14T03:53:16Z`
- 策略数值结论：**通过**。收敛度极高，独立最佳回应核对近零、12 个 equity anchor
  精确一致、20 档范围形态合理，并与独立 HRC 原始 Nash 数据在多数动作上
  6,591 / 6,591 一致。
- 发布 / 晋升决定：**需修订**。在来源 fail-closed、validator 证据链、生成器/工具链锁定
  以及 M5 直达 `reviewed` / 自报 evidence 绕过修复前，不得把本批次晋升为 `reviewed`。
- 当前内容状态：继续保持 `unverifiedDraft`。
