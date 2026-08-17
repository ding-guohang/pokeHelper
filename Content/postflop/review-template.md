# 翻后 River 内容审核记录（Batch A · 待签署）

> 填写并提交本文件**不会**改变任何内容包的状态。把 `unverifiedDraft` 晋升为 `reviewed`
> 是一个独立、证据门控的操作：`promote-river-packs.py` 会校验具名审核记录、**重新运行**
> 证据门禁（字节可复现 + 独立最佳回应复核），只重标 manifest（不改一个频率/EV），并签发
> **新的 `contentVersion`**。任一缺失/不一致即失败关闭、不产出。

## 1. 被审内容
- 批次：`srp-checked-river-100bb`（`Content/postflop/spots/srp-checked-river-batch.json`）
- 覆盖：单挑 100bb 单加注底池，SB(BTN) 开 2.5bb、BB 跟，flop×/×、turn×/×，**BB(OOP) 河牌决策**
- 因两条街都过牌，河牌范围 = 翻前范围（未被下注收窄），输入透明可查
- 内容版本（被审）：`2026.08.17-srp-river.1`
- 拟晋升到的新版本：`__________`（须与被审版本不同）
- 8 个板面：干燥A高、对子干燥、同花、湿连、Broadway、低连、河牌完成同花、河牌配对

## 2. 来源与可复现性
- 求解器：`b-inary/postflop-solver@9d1509fe`（**AGPL-3.0-or-later**，仅构建期工具、不链入 app、不联网）
- 锁定输入 SHA-256（`source-lock.json`，25 个源文件 + Cargo.toml + LICENSE）：每次构建重核
- 工具链：rustc 1.97.1（`verify_toolchain` 校验）；`RAYON_NUM_THREADS=1` 保证跨机字节可复现
- `bash scripts/verify-postflop-river.sh` 重跑逐位一致：**是**（8 包 + sidecar + report 字节相同）

## 3. 独立验证（关键）
- `verify-river-exploitability.py` 用**与求解器零共享代码**的实现（从零 7 张牌评估器 + 树上最佳
  回应 + 精确终端记账）复算求解器的可利用度指标 `(mes_ev[0]+mes_ev[1])/2`
- 8 个板面全部通过，**最坏独立 BR 偏差 8.64e-07 筹码**（纯浮点噪声，非算法分歧）
- 每个板面可利用度 ≈ 0.44–0.49% 底池（阈值 ≤1% 底池，目标 0.5%）

## 4. 数值不变量
- 每手 rangeCells 频率 basis points 之和 = 10,000（校验器强制）
- EV 以整数 milli-BB 存储；筹码单位取 centi-BB
- 通过 `StrategyPackValidator`（5 张公共牌、下注树、合法行动、位置）无需扩展

## 5. 诚实的边界
- 这是 **checked-to-river**（过牌到河）局面，范围宽——干净可验证的第一批，但**不是**实战里
  最高频的"河牌前有下注"场景（那是 Batch B，需从 flop 求解）
- 范围是**标准参考** SRP 范围（写在 spot spec 里）；若与审核人自己的开池/防守范围不同，应替换后重跑
- AGPL 商用许可仍待法务确认（构建期只产数据的用法标准解读安全，但需具名法务签字）

## 6. 结论（由具名人类审核人填写）
- 审核人：`__________`（具名）
- 审核时间：`__________`（ISO8601）
- 决定：`approved` / `needs-revision`
- 说明：`__________`

> 签署 approved 后，运行：
> `python3 Content/postflop/promote-river-packs.py --baseline Content/postflop/packs
> --destination <新目录> --content-version <新版本> --review-record <你的记录.json>`
