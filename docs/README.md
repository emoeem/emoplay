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
| [RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md](releases/RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md) | M3 播放器交互 R9（3.0 首批施工）：章节导航（chapter-list JSON 形态实测 + 二分 + 底板面板 + PgUp/PgDn）、字幕管理（sid 真相源 / 外挂加载 / 关闭字幕 / 延迟 ±0.5s，C/V 键）、A-B 循环与逐帧步进（三态机 + L / `.` / `,` mpv 惯例键位）；M3-T2 进度条刻度半边与 M3-T0 拆分未做；44 文件 411 用例全绿（含 7 条真 libmpv live），CI 不可测、3 提交待推送 |
| [RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md](releases/RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md) | M4 媒体库升级 R10（3.0 第二批施工）：统一 MediaItem 模型 + 播放队列收编、ffprobe 元数据缓存（media_meta.json，命中零进程）、网格四分组（目录/年月/剧集/电影）、收藏集（favorites.json + 拖拽排序）、目录树侧栏、本地 NFO/海报/剧集分组用户增补（容错解析 + 四名海报约定 + SxxEyy 词边界分组 + media_nfo.json 双 mtime 失效，`<thumb>` 只记录不下载）；顺带清偿 M3-T0（player_item 1614→484 行）；54 文件 489 用例全绿，§7 schema 零触碰、CI 恢复可达、4 提交待推送 |
| [RELEASE_2026-11-10_M5_MUSIC_METADATA.md](releases/RELEASE_2026-11-10_M5_MUSIC_METADATA.md) | M5 音乐与在线元数据兜底 R11（3.0 第三批施工）：循环模式三态（behavior.playlistMode，默认 none=1.x 现状；列表循环刻意不走引擎 loop-playlist，回卷在应用层）+ music 队列面板、replaygain 三档（默认 off）+ gapless-audio=weak 预置（1.x 明文遗留项清偿，听感待人工验收）、歌词页首帧定位修复 + 翻译列 + 常驻迷你条、在线元数据兜底框架（M4-T7 五道门禁，总开关默认关 + media_online.json 负缓存，真实数据流待 TMDB key）；60 文件 539 用例全绿，§7 schema 零触碰、4 提交待推送 |
| [RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md](releases/RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md) | M6 插件安全 + M3-T1 帧预览 R12（3.0 第四批施工）：清单 size+sha256 缺一拒装 + 装前内容校验（确定性摘要，`.git`/符号链接除外）、plugin_audit.jsonl append-only 审计（拒绝也留痕，观察性）、destination 防穿越 fuzz（敌意 12 + 形似 4 + 符号链接两类）+ 操作白名单常量化、插件页 catalog 重组（三段式不变量 6 不动）、进度条帧预览第二解码实例（默认关，Haruna 语义，画面待 GUI 验收）、修掉带注释 mpv.conf 静默把注释当值致无声（用户报告）；63 文件 585 用例全绿，2 提交待推送 |

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
| [WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md](reports/WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md) | R9 M3 播放器交互（3.0 首批施工收网）：三施工提交逐项对账（章节导航 M3-T2 主体完成 / 字幕管理 sid 真相源 / A-B 循环 + 逐帧 mpv 惯例键位）、门禁实测（44 文件 411+1 全绿两遍同数 / analyze 0 / 7 条真 libmpv live 真跑 / 新用例 56 逐文件计数与套件差值闭环）、挂账三项（M3-T2 刻度半边 / M3-T0 拆分 1614 行 / 路线图勾选与快捷键分组未回填）、确认无问题清单（schema 零触碰 / 键位零冲突 / 空操作语义 / fork 探针随行）、下一步建议 6 条 |
| [WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md](reports/WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md) | R10 M4 媒体库升级（3.0 第二批施工收网）：四施工提交逐项对账（M3-T0 拆分 484 行达标 / M4-T0 模型与队列收编 / T2/T3/T5 分组收藏目录树 / T6 用户增补 NFO 海报剧集）、门禁实测（54 文件 489+1 全绿 / analyze 0 / 新用例 78 逐文件计数与套件差值闭环 / 1 skip 身份与夹具降级核实）、gh 恢复可达窗口的 CI 与 v2.1.0-alpha release 状态实测（11 资产）、路线图勾选回填在工作树核实、确认无问题清单（schema 零触碰 / 路线图验收下限全达标 / 收藏双向隔离 / 本地优先零网络）、下一步建议 6 条 |
| [WORK_REPORT_2026-11-10_M5_MUSIC_METADATA.md](reports/WORK_REPORT_2026-11-10_M5_MUSIC_METADATA.md) | R11 M5 音乐与在线元数据兜底（3.0 第三批施工收网）：四施工提交逐项对账（M5-T1 循环三态 + 应用层回卷 / M5-T2 replaygain+gapless / M5-T3 歌词迷你条 / M4-T7 联网兜底框架）、门禁实测（60 文件 539+1 全绿 / analyze 0 / 新用例 50 逐文件计数与套件差值闭环 / 1 skip 身份不变）、CI 与 v2.2.0-alpha release 状态实测（main 43101040926 ✓ / release 43101070581 ✓，公开 11 资产）、路线图勾选回填在工作树核实、确认无问题清单（schema 零触碰 / 验收下限全达标 / 未知值回落契约 / compatOptions 后写者胜）、下一步建议 5 条 |
| [WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md](reports/WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md) | R12 M6 插件安全 + M3-T1 帧预览（3.0 第四批施工收网）：五施工提交逐项对账（M6-T1 缺一拒装 + 装前校验 / M6-T2 审计留痕 / M6-T3 fuzz+白名单 / M6-T4 catalog 拆四件 / M3-T1 帧预览默认关）、compat 修复根因链（mpv.conf 行内注释当值致无声）、门禁实测（63 文件 585+1 全绿 / analyze 0 / 新用例 46 逐文件计数与套件差值闭环 / 1 skip 身份不变）、CI 本窗口 EOF 与推送态实测（origin/main = `07427f8`，ahead 2）、确认无问题清单（schema 零触碰 / 验收下限全达标 / 拒绝路径全留痕 / fuzz 断言打最深 / 行数守卫达标）、plugin_audit_test NUL 字节致 git 二进制挂账、下一步建议 5 条 |

## 审计（audits/）

| 文档 | 一句话说明 |
| --- | --- |
| [AUDIT_FULL_2026-11-10.md](audits/AUDIT_FULL_2026-11-10.md) | 全面检测：九条不变量逐条核实、五平台发布演练考古（第三红灯=arm64 ALSA）、P1/P2 问题清单（上帝类/CI timeout/双源/any×3/web 残留）、已核实无问题清单与修复顺序 |
