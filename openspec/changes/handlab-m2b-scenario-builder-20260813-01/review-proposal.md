# 审需报告：handlab-m2b-scenario-builder-20260813-01

日期：2026-08-13
方式：可测试性与架构一致性两个 agent 独立审，逐条对代码复核，据此重写。

## 结论
初稿方向对但有可测试性弱点与两处架构不精确，已重写，重写后有条件通过——可进入 plan。

## 架构复核
- ConstructedSpot 可落 HandHistory（签名分量全在 PokerCore）——成立。
- matcher 现只接 `HeroDecisionSignature`：需抽 `classify(signature:action:)` 核心供构造 spot 复用（加法）。
- 版本化存储须并行 mirror `FileHandLibraryStore`；ConstructedSpot 须自带 Codable+规范编码+身份。
- **合法性**：PokerCore 不拒重复牌/非正筹码（`HandClass(Ah,Ah)=AA`、`BBAmount(centiBB:0)` 不报错），仅座位越界由 `TablePosition` 抛错——故 ConstructedSpot 自校验重复/可解析/正筹码。
- 分层 `check-package-layering.sh` 已覆盖两包；`Modified: 无` 成立。

## 可测试性（已在重写中修）
| 弱点 | 对策 |
|---|---|
| 单一合法输入，恒定签名可蒙混 | 加第二个不同合法构造，断言据算签名各字段不同 |
| covered 权重未钉/未据算 | 用 `HandLabContentFixture` 造非整值 6234，断言 == `scenario.rangeWeightBasisPoints(...)` |
| 重存"未被覆盖"太松 | 捕获 v1 规范编码字节、重存后比对不变 |
| 删除"其余不受影响"空真 | 双 spot，断言存活者逐字段不变 |
| 非法枚举不全、原因未断言、tableSize 未钉 | 四类非法各返回可判等不同原因；tableSize 固定 6；加"无法解析"项；去掉未测的"行动合法性"声明 |
| "无内容可对照"是 UI 串 | 绑定到 `NodeCoverage.uncovered`（可判等值） |

认可范本：covered/uncovered 成对、legal/illegal 成对、非空存储下 build/save 不产生事件且只有完成补救才 +1。

## 规格完整性
1 capability、3 requirements（全 SHALL）、6 scenarios（全 GWT），无 TODO；`Modified: 无`。

## 留给 plan 的决断
1. `ConstructedSpot` 字段与校验错误枚举（可判等）；规范编码与身份取法（仿 `ObservedHand.canonicalJSON`/`HandSource.identity`）。
2. matcher 核心抽取形态；App 构造界面落点与复用第三切片补救入口。
