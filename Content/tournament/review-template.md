# 锦标赛 Push/Fold 内容人工审核记录（模板）

> 填写并提交本文件**不会**改变任何内容包的状态。把 `unverifiedDraft` 晋升为
> `reviewed` 是一个独立的、未来的操作,它必须签发**新的 `contentVersion`**、
> 记录审核人与时间,并跑黄金回归。本模板只是那次晋升所需的证据。

## 1. 被审内容

- Change / 批次:`strategy-content-import-hu-pushfold-20260813-01`
- 覆盖:单挑,SB=0.5BB/BB=1BB,无 ante,rake=0,chipEV,深度 1–20BB
- 内容版本(被审):`__________`
- 拟晋升到的新内容版本:`__________`

## 2. 来源与可复现性

- 求解器仓库 / commit:`b-inary/poker-cfr@a5347082007ba1eda7932ef2fe7fad43cb3be2a1`（BSD-2-Clause）
- 锁定输入 SHA-256（见 `source-lock.json` 与 `golden-manifest.json`）核对:是 / 否
- `bash scripts/verify-tournament-content.sh` 重跑逐位一致:是 / 否
- 每深度 iterations 与 NashConv（见 `golden-manifest.json`）:最大 NashConv `________` BB/hand

## 3. 独立参照与许可

- 用于交叉核对的独立 Nash push/fold 参照（来源、版本、是否公开可核对）:`__________`
- 商业平台数据仅经用户本地合法导出转换（若用到）:是 / 否 / 未使用

## 4. 抽样边界手核对

对若干边界深度与边界手(如 8–12BB 的 SB open-jam 阈值手、面对全下的 BB 跟注临界手)
逐一比对求解频率与参照,记录差异百分点:

| 深度 | 位置 | 手 | 求解频率 | 参照频率 | 差异 |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

## 5. 频率与 EV 不变量

- 每表 169 手齐全、每行 bps 和 = 10000:是 / 否
- SB fold EV 恒为 −500 milli-BB、可达 BB fold EV 恒为 −1000 milli-BB:是 / 否
- EV 与频率同源(同一均衡快照,snapshot 哈希一致):是 / 否

## 6. 结论

- 审核人姓名:`__________`
- 审核时间(ISO8601):`__________`
- 决定:通过晋升为 `reviewed` / 需修订 / 拒绝
- 说明:`__________`
