# EmoPlay 文档索引

EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写）仓库 `docs/` 的全部文档入口。
写作与维护规则见 [DOC-STANDARD.md](DOC-STANDARD.md)：数字必须实测、坏消息
必须单列、新文档必须登记进本索引。

## 规格（迁移工程的决策依据）

| 文档 | 一句话 |
| --- | --- |
| [SPEC.md](SPEC.md) | 迁移规格书：项目身份、技术决策、环境策略（宿主机零污染）、关键不变量、数据 schema、gate 命令、决策兜底规则 |
| [PORT-MAP.md](PORT-MAP.md) | mpv-emo (C++/Qt) → EmoPlay (Dart/Flutter) 文件级映射与测试用例对账表；MediaBrowser 已判定 N/A（§2） |
| [STRIP-LIST.md](STRIP-LIST.md) | Kazumi → EmoPlay 文件级处置清单：删番剧业务、留导航/设置/播放器骨架 |
| [UPSTREAM.md](UPSTREAM.md) | 上游来源记录：Kazumi 导入 commit、1.x 与 PiliPlus 只读参考 |

## 流程与交接

| 文档 | 一句话 |
| --- | --- |
| [DOC-STANDARD.md](DOC-STANDARD.md) | docs/ 写作与维护标准（三类底线、命名、骨架、提交前检查清单） |
| [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) | 过夜自动循环手册：轮次结构、停止条件、起始积压清单（当前待办的权威来源） |
| [HANDOVER.md](HANDOVER.md) | 交接现状：一句话现状、最近实质变更、最易踩的坑、接手第一步清单 |
| [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) | 迁移路线图：M0–M8 ✅+提交哈希、R1/R2 收尾轮次、未做项 ☐ 清单、验收标准与贯穿约定 |

## 更新记录（releases/，读者是用户）

| 文档 | 主题 |
| --- | --- |
| [RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md](releases/RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md) | 对账收网 R1：更新检查上线、CI 触发分支修复、画质控制器语义对齐；M1–M8 之前的变化见仓库根 [CHANGELOG.md](../CHANGELOG.md) |
| [RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md](releases/RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md) | 转绿补账 R2：CI 首跑红灯定位与修复（VA/VDPAU 运行库）、健壮性边界 11 用例、settings 语义 2 用例、i18n 骨架；30 文件 326 用例全绿 |

## 工作报告（reports/，读者是维护者与接手者）

| 文档 | 主题 |
| --- | --- |
| [WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md) | R1 对账收网：26 个 C++ 测试文件 ↔ 28 个 Dart 测试文件逐一对账、门禁实测（313 用例全绿 / analyze 0 告警 / debug build 通过）、CI 零 run 根因 |
| [WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md) | R2 转绿补账：CI 首跑红灯归因链（混合 push 触发 / libva 缺失）、门禁实测（30 文件 326 用例全绿）、路线图滞后数字修正 |

## 审计（audits/）

暂无。
