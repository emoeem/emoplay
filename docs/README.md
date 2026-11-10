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
| [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) | 迁移路线图：M0-M8 ✅+提交哈希、R1-R4 收尾轮次、未做项 ☐ 清单、验收标准与贯穿约定 |
| [EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md) | 3.0 路线图：现状四类盘点（保留/复用/重构/缺失）、四路参考项目借鉴映射（M3-M8 归组）、统一 MediaItem/PlaybackSession 数据模型、M3 播放器交互→M8 发布工程文件级任务书与机检验收 |
| [CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md) | 3.0 跨平台验证矩阵：Linux/Windows/macOS/Android 逐行测试步骤、预期、所需环境与负责人（实机行标「需用户」） |
| [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md) | media-kit fork 治理：Predidit/media-kit@83b7ca6 差异清单（native assets/自建 libmpv/OHOS/渲染增强）、季度同步与升级回归流程、上游 PR 策略 |
| [guides/BUILD_GUIDE.md](guides/BUILD_GUIDE.md) | 构建与发布手册：前置条件与可复制构建/打包命令、draft 发布流程（人工核对后 `gh release edit <tag> --draft=false`）、常见故障排查、已知限制 |

## 更新记录（releases/，读者是用户）

| 文档 | 主题 |
| --- | --- |
| [RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md](releases/RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md) | 对账收网 R1：更新检查上线、CI 触发分支修复、画质控制器语义对齐；M1-M8 之前的变化见仓库根 [CHANGELOG.md](../CHANGELOG.md) |
| [RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md](releases/RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md) | 转绿补账 R2：CI 首跑红灯定位与修复（VA/VDPAU 运行库）、健壮性边界 11 用例、settings 语义 2 用例、i18n 骨架；30 文件 326 用例全绿 |
| [RELEASE_2026-11-10_RED_LIGHT_ZEROING.md](releases/RELEASE_2026-11-10_RED_LIGHT_ZEROING.md) | 红灯清零 R3：CI 第二层红灯修复（libpulse + ldd 审计步一次列全缺口）、deb Depends 17 项经递归闭包审计、页签壳 i18n 第一页、媒体库响应性守卫 3 用例；32 文件 332 用例全绿，首绿待推送确认 |
| [RELEASE_2026-11-10_FIRST_GREEN_RELEASE.md](releases/RELEASE_2026-11-10_FIRST_GREEN_RELEASE.md) | 首绿发布 R4：CI 首绿达成（332/1 与预期一致）、v2.0.0-alpha 发布演练三跑打穿（macOS Kazumi.app 残留 / Windows 缺 yq / arm64 缺 ALSA / Windows 死 include 四红灯修复）、GitHub Release 公开 9 资产、mpv apply 半边 5 条 live 用例、音频设置页 i18n 第二页；33 文件 341 用例全绿 |
| [RELEASE_2026-11-10_PANEL_LOOK.md](releases/RELEASE_2026-11-10_PANEL_LOOK.md) | 面板观感 R5：播放页两处整页失效修复（快捷键焦点门禁 / Observer 短路）、字体定案（系统字体默认 + 显式 CJK 兜底 + 设置开关）、播放面板按 Kazumi 逐槽位重组、发布矩阵 9 job 超时 + Windows 版本单一来源；34 文件 342 用例全绿，CI 本窗口不可测 |
| [RELEASE_2026-11-10_HYGIENE_DELIVERY.md](releases/RELEASE_2026-11-10_HYGIENE_DELIVERY.md) | 卫生与交付形态 R6：AppImage 打包落地（linuxdeploy；amd64 产物与 runtime 本机实测，arm64 仅 CI 可验）、web 残留 / any×3 / screen_brightness_ohos 清账（审计 P2 卫生批次）、Kazumi 空态按钮 / 徽章 / 许可证 tile 样式对齐 + 3 守护用例、README 对账与截图占位；35 文件 345 用例全绿，CI 不可测、6 提交待推送 |
| [RELEASE_2026-11-10_PERF_AND_SETTINGS.md](releases/RELEASE_2026-11-10_PERF_AND_SETTINGS.md) | 性能实测与设置收尾 R7：设置 → 通用「恢复默认设置」落地（1.x 对账最后一项消账，库 / 历史 / 导入决策不动）、性能定量实测 ☐→✅（容器口径：热扫 125ms / 装载 1.7-2.2ms，判定不改代码）、tag 发布 draft 制 + BUILD_GUIDE §四流程、deb 注释库数口径考证；37 文件 355 用例全绿，CI 不可测、3 提交待推送 |

## 工作报告（reports/，读者是维护者与接手者）

| 文档 | 主题 |
| --- | --- |
| [WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md) | R1 对账收网：26 个 C++ 测试文件 ↔ 28 个 Dart 测试文件逐一对账、门禁实测（313 用例全绿 / analyze 0 告警 / debug build 通过）、CI 零 run 根因 |
| [WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md) | R2 转绿补账：CI 首跑红灯归因链（混合 push 触发 / libva 缺失）、门禁实测（30 文件 326 用例全绿）、路线图滞后数字修正 |
| [WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md) | R3 红灯清零：CI 第二层红灯归因链（dlopen 只报第一层 / libpulse 缺失）、deb 依赖审计与打包实测、ldd 闭包覆盖验证（104 ⊂ 251 差集空）、门禁实测（32 文件 332 用例全绿） |
| [WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md) | R4 首绿发布：CI 首绿签名实测（42718530280 = 332/1）、发布演练三次跑归因链（四红灯逐层修复，第三次全绿发布）、GitHub Release 9 资产实测（字节数/prerelease 状态）、engine apply 对账与门禁实测（33 文件 341 用例全绿、build_runner 幂等、ldd 0 缺失） |
| [WORK_REPORT_2026-11-10_PANEL_LOOK.md](reports/WORK_REPORT_2026-11-10_PANEL_LOOK.md) | R5 面板观感：两处整页失效根因链（焦点门禁永假 / Observer && 短路）、楷体事故归因（M1 删字体 + fontconfig 猜错）、面板单文件重组（402 插入 / 485 删除）、门禁实测（34 文件 342 用例全绿 / analyze 0 / ldd 0 / 音频探针真跑）、CI 不可测窗口记录 |
| [WORK_REPORT_2026-11-10_HYGIENE_DELIVERY.md](reports/WORK_REPORT_2026-11-10_HYGIENE_DELIVERY.md) | R6 卫生与交付形态：审计 P2 卫生批次三项逐条对账、AppImage 产物与 runtime 实测（35,584,504 B / static-pie / help exit 0 / gitignore 覆盖）、门禁实测（35 文件 345+1 全绿 / analyze 0，与施工轮两次同数）、守护测试注释与 CI 现实不符项挂账（hardcoded-color grep 不存在）、CHANGELOG 一轮一节结构修复 |
| [WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md](reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md) | R7 性能定量实测：路线图 §4.1「性能实测」☐→✅（容器环境实测）。2000 文件夹具扫描吞吐（worker 热扫 125ms / 16000 files/s，直连遍历冷 160-179ms，进度回调实数 63 次）、首帧同步 IO 静态清单 + 2000 条目 library.json 装载 1.7-2.2ms（远低于 100ms 阈值，不改代码）、缩略图串行链 77-81ms/作业（并发重叠 0）；基准 skip-if-fixture-missing；**容器 Isolate 计时，非宿主基线**，GUI 首帧墙钟与真 ffmpeg 速率仍归 SPEC §9；门禁实测（36 文件 349+1 全绿 / analyze 0） |
| [WORK_REPORT_2026-11-10_PERF_AND_SETTINGS.md](reports/WORK_REPORT_2026-11-10_PERF_AND_SETTINGS.md) | R7 性能实测与设置收尾（轮级收网）：三施工提交逐项对账（路线图 §4.1 ✅、1.x 对账最后一项消账、draft 制全验待 tag run）、门禁实测（37 文件 355+1 全绿 / analyze 0，夹具在场基准段真跑）、路线图勾选滞后三处挂账、确认无问题清单（数据安全契约测试体核实 / CHANGELOG 一轮一节 / draft 制三处口径一致）、下一步建议 5 条 |

## 审计（audits/）

| 文档 | 一句话说明 |
| --- | --- |
| [AUDIT_FULL_2026-11-10.md](audits/AUDIT_FULL_2026-11-10.md) | 全面检测：九条不变量逐条核实、五平台发布演练考古（第三红灯=arm64 ALSA）、P1/P2 问题清单（上帝类/CI timeout/双源/any×3/web 残留）、已核实无问题清单与修复顺序 |
