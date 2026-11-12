# HANDOVER · EmoPlay 2.0 交接现状

| 项     | 值                                                                          |
| ------ | --------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-13 R12 M6 插件安全 + M3-T1 帧预览轮之后）                    |
| 日期   | 2026-11-13（最后实质性更新）                                                 |
| 适用版本 | git `3514db3`（R12 五提交 `757d130` / `0919ccc` / `07427f8` / `7b89bb0` / `3514db3`；前三提交已推送、后两提交待推送，本地 origin/main 跟踪引用在 `07427f8`；gh 本窗口 EOF，CI 与 release 状态不可复核，2026-11-13 文档窗口实测） |
| 相关   | [SPEC.md](SPEC.md)、[EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[docs/README.md](README.md)、[R12 工作报告](reports/WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md) |

## 现状一句话

M1-M8 迁移主流程、R1-R11 收尾与施工轮、R12 M6 插件安全 + M3-T1 帧预览轮
（M6-T1 清单 size+sha256 缺一拒装 + 装前内容校验、M6-T2 操作审计
plugin_audit.jsonl append-only、M6-T3 destination 防穿越 fuzz + 操作白名单、
M6-T4 插件页 catalog 重组、M3-T1 第二解码实例帧预览默认关、mpv.conf 行内
注释无声事故修复）全部完成：Kazumi 骨架上重建的 Flutter/mpv 本地播放器
功能对等（播放 / 本地媒体 / 媒体库 / 历史 / mpv 兼容导入 / 画质引擎 /
插件安全加固 / 11 类设置 + 在线元数据 / 更新检查），**v2.3.0-alpha 已发布**
（CHANGELOG 记「已发布」；gh 本窗口 EOF，资产态未复核）；本地 63 个测试
文件 585 用例 + 1 平台条件跳过全绿（R12 文档窗口实测，含真 libmpv live
用例；无 /tmp 夹具时 perf 基准段与音频探针按设计降级）、analyze 0 告警；
R12 后两提交待推送（ahead 2：`7b89bb0` / `3514db3`，推送后预期 CI 签名
**585 passed / 1 skipped**），版本仍 `2.3.0-alpha+2030000`（R12 在
CHANGELOG [Unreleased]，未 bump 未发版），3.0 施工按
EMOPLAY-3.0-ROADMAP 推进中（M3-T0/T1 ✅、M4 七任务全 ✅、M5 三任务全 ✅、
M6 四任务全 ✅，下一阶段 M7 诊断/测试，M3 残留 T2-T9 择机；TMDB 真实
联网数据流、replaygain/gapless 听感、帧预览画面三项目人工验收待用户）。

## 最近实质性变更（R12·M6 插件安全 + M3-T1 帧预览，2026-11-12 08:10 - 11-13 00:30 CST 施工 + 文档收网）

五个施工提交（`757d130` M6-T1/T2 清单完整性+审计、`0919ccc` M6-T3 fuzz+
白名单、`07427f8` mpv.conf 行内注释修复、`7b89bb0` M6-T4 catalog、
`3514db3` M3-T1 帧预览）+ 本轮文档收网。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md)
与[轮级工作报告](reports/WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md)。

- 清单资产完整性（M6-T1，`757d130`）：manifest 可选 sizeBytes+sha256
  全有全无对，缺一拒装且闸门在 install/replace-update 链**最前**（任何
  git 命令之前）；克隆内容先验后记（`PluginContentIntegrity`，摘要定义
  确定性：`.git` 剪枝、符号链接跳过、路径排序、`<hash>  <path>\n` 清单
  再整体 sha256），不匹配即删刚克隆的树；不声明字段 = 1.x 行为逐位不变。
- 操作审计（M6-T2，`757d130`）：`<appDataDir>/plugin_audit.jsonl`
  append-only JSONL（第 5 个独立 AppData 文件），plan/operation 两类
  事件、**拒绝也留痕**（busy / 已安装 / porcelain / 完整性拒绝同一出口）；
  观察性日志：写失败吞掉、损坏行跳过，从不阻断操作。
- 暴力面收缩（M6-T3，`0919ccc`）：destination 防穿越 fuzz 钉死
  （敌意语料 12 条 + 形似对照 4 条 + 符号链接两类，parse 拒绝 + 整目录
  fail-closed + git 零调用三段断言）；`allowedOperations` 白名单常量化
  （install/uninstall/update/check），未知动作默认拒绝。
- 插件页 catalog（M6-T4，`7b89bb0`）：Kazumi plugin_editor 范式，搜索 +
  全部/已安装/可更新过滤 + 详情页；plugins_page 577→485 行拆四件（全部
  <600 行）；三段式 UI 语义不变（不变量 6，过滤只变换视图）。
- compat 修复（`07427f8`）：带注释 mpv.conf 的行内 `#` 在 runtime 属性
  语境不是注释，字符串型选项静默把注释当值（audio-device =
  `auto # 此项用于…`，每会话无声，用户报告，两 alpha 可复现）；
  `MpvConfigParser.runtimeOptionValue`（`mpv_config_parser.dart:137`）
  复刻 mpv 文件语义，5 条回归测试取自报告人真实 conf 行。
- 帧预览（M3-T1，`3514db3`）：进度条 hover/拖动出帧图，第二 media_kit
  解码实例（Haruna MpvPreview 语义移植，属性集等价表
  `seekPreviewMpvProperties` 生产/断言共表）；激活门禁五条件同
  HProgressBar；hover 懒建 + 100ms 消抖；**隐藏即 pause 不拆**；开关
  `seekPreview` 默认关（Haruna kcfg 同默认，关闭零实例开销，实例数守卫
  锁定）+ 宽度 `seekPreviewWidth` 默认 200（滑杆 120-400）；属性集 live
  probe 2026-11-13 实测全过，**画面效果待 GUI 人工验收（SPEC §9）**。
- 本轮文档收网：R12 发布说明 + 轮级工作报告 + 本文件刷新 +
  docs/README.md 索引 + CHANGELOG `[Unreleased]` R12 节。**路线图
  M3-T1 与 M6 四任务的 ☐→✅+哈希回填已在工作树**（未提交，随本轮文档
  提交入库，勾选与五提交逐一相符）。
- 门禁实测（2026-11-13 文档窗口）：analyze 0 告警（7.6s）；63 文件
  **585 通过 / 1 平台条件跳过**全绿（1 skip =
  `mpv_profile_scanner_test.dart:217` Windows-only 探针；新增用例 46
  逐文件点数与全量差值 585-539 闭环；真 libmpv live 用例真跑）；gh
  本窗口 EOF（api.github.com 不可达），CI 与 release 状态不可复核；
  R12 前三提交已推送（origin/main = `07427f8`）、后两提交待推送
  （ahead 2）。

## 最近实质性变更（R11·M5 音乐与在线元数据兜底，2026-11-12 05:51-06:55 CST 施工 + 文档收网）

四个施工提交（`2115183` 循环/队列、`ec456b3` replaygain+gapless、
`a539866` 歌词升级+迷你条、`eb3b2bf` 联网兜底框架）+ 本轮文档收网。细节
与证据见 [发布说明](releases/RELEASE_2026-11-10_M5_MUSIC_METADATA.md) 与
[轮级工作报告](reports/WORK_REPORT_2026-11-10_M5_MUSIC_METADATA.md)。

- 循环模式三态（M5-T1，`2115183`）：`behavior.playlistMode` 三态
  （none/single/playlist，默认 none = 1.x 硬编码现状，settings.json 追加
  键 + 默认/往返用例随行）；单曲循环走引擎原生 loop-file，列表循环
  **刻意不开**引擎 `loop-playlist`（media_kit `open(Media)` 只装一个
  entry，引擎回卷会让 completed/eof 永不到应用层、队列无法续播），回卷
  在应用层：PlaybackSession 事实源 + `resolveQueueNextIndex`
  （`lib/music/music_queue.dart`）+ PlayerProgressPipeline 推进；music
  形态「播放队列」底板面板（复用 M3-T3 组件 + 循环模式头部），视频形态
  维持播放列表面板。
- 音频属性（M5-T2，`ec456b3`）：设置 → 音频「音频属性」分组：replaygain
  三档 off/track/album（默认 off = 1.x 现状（从未写过该属性），off 显式
  钉 mpv `'no'` 让审计表陈述意图）、`gapless-audio=weak` 钉为全局预置
  （mpv 默认已是 weak，shipped libmpv 回读实测；钉住 = 行为逐位一致 +
  防 fork 默认漂移）；1.x 明文遗留项清偿（mpv-emo docs/roadmap.md 遗留项）；
  **听感生效待 SPEC §9 人工验收**（属性层 live 用例只证明接受 + 回读一致）。
- 歌词与迷你条（M5-T3，`a539866`）：歌词页首帧定位修复（根因：此前只跟随
  lyricIndex 变化，歌词加载晚于首帧时第一行不定位）+ 滚动动画时长与距离
  成比例（120-420 ms 夹紧）+ 翻译列（同时间戳相邻行分组、行高常量滚动
  确定性）；常驻迷你条 `lib/pages/player/music_mini_bar.dart`（非播放页
  底部，竖屏 NavigationBar 之上 / 横屏 outlet 之下；视频条目同样适用，
  点击回播放页与点 tab 同一条 `_selectDestination` 路径）。
- 在线元数据兜底框架（M4-T7，`eb3b2bf`，2026-11-12 用户改向纳入）：
  五道门禁（总开关关 → 无 key → 本地 NFO 覆盖 → `media_online.json`
  缓存命中 → 才联网，每道都不发请求）；正命中与明确未命中落盘、传输失败
  **永不缓存**（网络恢复后可重试）；设置中心「在线元数据」分类（总开关
  **默认关** + TMDB key 掩码输入，settings.json 增 `online` 段）；NFO
  详情弹层「联网补全」动作 + badge 拓宽全部视频格子，七种结果优雅提示；
  可达性实测：api.themoviedb.org curl 0.83s / Dart HttpClient 1.04s，
  无效 key 恰返 HTTP 401；**真实联网数据流待用户填有效 TMDB key 后人工
  验收（pending）**。
- 本轮文档收网：R11 发布说明 + 轮级工作报告 + 本文件刷新 +
  docs/README.md 索引 + CHANGELOG R11 节（一轮一节，覆盖四个施工件）。
  **路线图 M4-T7 补哈希 / M5 三任务 ☐→✅+哈希的回填已在工作树**（未提交，
  随本轮文档提交入库，勾选与四提交逐一相符）。
- 门禁实测（2026-11-12 07:00 CST 文档窗口）：analyze 0 告警（5.3s）；60
  文件 **539 通过 / 1 平台条件跳过**全绿（1 skip =
  `mpv_profile_scanner_test.dart:217` Windows-only 探针；新增用例 50
  逐文件点数与全量差值 539-489 闭环；真 libmpv live 用例真跑；/tmp 夹具
  缺失时 perf 基准段按设计降级）；gh 本窗口可达：v2.2.0-alpha main run
  43101040926 ✓、release run 43101070581 ✓（release 已公开 11 资产）；
  R11 四提交未推送（ahead 4）。

## 最近实质性变更（R10·M4 媒体库升级，2026-11-12 03:14-04:50 CST 施工 + 文档收网）

四个施工提交（`c9245f8` M3-T0 拆分、`0da4a95` 统一模型 + 元数据缓存、
`25dd830` 网格分组 + 收藏 + 目录树、`5fedee0` 本地 NFO/海报/剧集分组
用户增补）+ 本轮文档收网。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md) 与
[轮级工作报告](reports/WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md)。

- 统一媒体模型（M4-T0，`0da4a95`）：`MediaItem`（基础字段对齐 §7 store
  语义，3.0 扩展槽可空且永不写回三份 JSON）+ `PlaybackSession`（播放页
  事实源，对外 playlist 接口不变，resume 语义仍归 PendingResumeSeek）+
  无损映射器（11 用例）；元数据缓存 M4-T4：两段 ffprobe 链 +
  `media_meta.json`，缓存键 sha1(path+mtimeMs) 与缩略图链同输入、命中
  零进程、无 ffprobe 优雅降级。
- 网格 / 收藏 / 目录树（M4-T2/T3/T5，`25dd830`）：SliverGrid + pinned
  分组头（初始目录/年月两种）、收藏集 `favorites.json`（条目=path+
  addedAt，渲染期 join 不复制 §7 数据，ReorderableListView 拖拽排序）、
  目录侧栏（`scanOptions` 派生，不加新扫描）。
- 本地 NFO/海报/剧集分组（M4-T6 用户增补，`5fedee0`）：手写容错 NFO
  解析（类型看根元素、坏字段跳过不崩）、海报四名约定（sidecar →
  poster → folder → fanart）、文件名 SxxEyy/1x02 词边界剧集三级分组、
  `media_nfo.json` 缓存（video+目录双 mtime 失效）、NFO 详情弹层；
  `<thumb>` URL 只记录不下载（本地优先，第 11 轮联网兜底已排期）。
- M3-T0 拆分清偿（`c9245f8`）：`player_item.dart` 1614 → **484 行**
  （验收线 <500），拆出 10 个职责文件全部 <600 行，纯搬移不改行为。
- 本轮文档收网：R10 发布说明 + 轮级工作报告 + 本文件刷新 +
  docs/README.md 索引 + CHANGELOG 顶部新增 `[Unreleased]` R10 节。
  **路线图 M3-T0/M4 六任务的 ✅+哈希回填已在工作树**（未提交，随本轮
  文档提交入库，勾选与四提交逐一相符），另含 §六改向注记：联网元数据
  排期第 11 轮（用户决策）。
- 门禁实测（2026-11-12 文档窗口）：analyze 0 告警（4.8s）；54 文件
  **489 通过 / 1 平台条件跳过**全绿（1 skip = `mpv_profile_scanner_test.dart`
  Windows-only 探针；10 个新测试文件逐个点数合计 78 = 489−411 账目闭环；
  /tmp 夹具缺失时 perf 基准段与音频探针按设计降级，live 用例真跑）；
  gh 恢复可达：R9 尾提交 `e9bf692` main run 43069268623 ✓，v2.1.0-alpha
  release run 43069322152 ✓（首跑 43068258121 缺 ffmpeg 失败后修复），
  release 已公开 11 资产；R10 四提交未推送（ahead 4）。

## 最近实质性变更（R9·M3 播放器交互，2026-11-11 08:20 - 11-12 00:52 CST 施工 + 文档收网）

三个施工提交（`f2b7754` 章节导航、`a8cb844` 字幕管理、`2e5d73d` A-B 循环 +
逐帧步进）+ 本轮文档收网。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md) 与
[轮级工作报告](reports/WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md)。

- 章节导航（`f2b7754`，M3-T2 主体）：`chapter-list` / `chapter` 属性读取链
  （JSON 形态实测 + 上界二分 + open 后 attach 可靠性）、底板章节面板
  （无章节优雅隐藏）、Page Up / Page Down 跳章（出货 libmpv 内嵌默认
  input.conf 的同位置建议绑定显式化）。路线图验收面的进度条章节刻度 /
  hover 标题 / 中键跳章未做，挂账。
- 字幕管理（`a8cb844`，施工件 B）：轨道切换 / 外挂字幕加载
  （srt/ass/ssa/vtt/sub）/ 关闭字幕 / sub-delay ±0.5s 步进 HUD。真相源是
  mpv `sid` 属性（fork 的 `Player.state.track.subtitle` 在 sub-add 后
  stale，探针记录在控制器头注释）；键位 C/V（mpv z/Z 不可用：keyLabel
  分发不区分 Shift + Z 被 Kazumi 倍速减占用）。
- A-B 循环 + 逐帧步进（`2e5d73d`，施工件 C）：ab-loop 三态机
  （B ≤ A 客户端拒绝守卫）+ L 键（1.x 经 Main.qml 转发落到 mpv 内置绑定
  的行为显式化）、frame-step / frame-back-step + `.` / `,`（fork 命令表
  strings 实测；frame-back-step 需 mpv ≥0.38）、控制条暂停态逐帧按钮、
  三态菜单项与 OSD HUD；键位守护测试 2 用例（keyLabel 身份 + 零冲突）。
- 测试侧修复（`a8cb844`）：`test/library_store_test.dart:364` 断言扫描
  静止态前补排水等待（链式扫描管线竞态），产品代码零改动。
- 本轮文档收网：R9 发布说明 + 轮级工作报告 + 本文件刷新 +
  docs/README.md 索引 + CHANGELOG 补 R9 节。R8（`3dcfb6a`）为纯文档轮
  （3.0 路线图 / 矩阵 / fork 治理），无独立发布记录。
- 门禁实测（2026-11-12 文档窗口）：analyze 0 告警（5.7s）；44 文件
  **411 通过 / 1 平台条件跳过**全绿（两遍全量同数；1 skip =
  `mpv_profile_scanner_test.dart:217` Windows-only 探针；7 条真 libmpv
  live 用例真跑，逐帧 live 17s；/tmp/perf 夹具缺失时基准段按设计降级）；
  CI 不可测（`gh run list` EOF）；R9 三提交未推送（ahead 3）。

## 最近实质性变更（R7·性能实测与设置收尾，2026-11-11 02:55-03:37 CST 施工 + 文档收网）

三个提交（`87b3760` 性能实测、`d971af0` 恢复默认设置、`0a3436c` draft 制
与打包注记）+ 本轮文档收网。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_PERF_AND_SETTINGS.md)、
[轮级工作报告](reports/WORK_REPORT_2026-11-10_PERF_AND_SETTINGS.md) 与
性能定量专报
[WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md](reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md)。

- 性能实测（`87b3760`）：路线图 §4.1 ☐→✅（容器环境实测口径）。2000 文件
  夹具扫描 worker 生产路径热扫 125ms（16000 files/s）、2000 条目
  library.json 装载 1.7-2.2ms（远低于 100ms 阻塞阈值，判定不改代码）、
  缩略图串行链 77-81ms/作业、并发重叠 0。基准
  `test/perf_scan_benchmark_test.dart` skip-if-fixture-missing（夹具
  `/tmp/emoplay-perf-lib` 由 `tools/gen_perf_fixture.sh` 生成，只在 /tmp，
  CI 无夹具时自动降级通过）。**容器 Isolate 计时，非宿主基线**。
- 恢复默认设置（`d971af0`）：设置 → 通用新增「恢复默认设置」操作项，
  EmoDialog 危险样式确认后 quality / behavior / music 三分区回 1.x schema
  默认（`lib/settings/emoplay_settings.dart:500`）；媒体库、观看历史与
  mpv 配置导入决策不动，恢复后各设置页经会话控制器 `reloadFromSettings`
  即时刷新。1.x 对账最后一项消账；通用设置页 i18n 第三页；新增 5 + 1
  守护用例（l10n 挂真实页面 + 语义测试断言库 / 历史文件逐字节不变）。
- draft 发布制（`0a3436c`）：release.yaml `Create release` 步
  `draft: true`，跑完是草稿，人工核对后 `gh release edit <tag>
  --draft=false` 公开（流程 BUILD_GUIDE §四，坑 8(d)）；**忘 publish 是
  新流程主要失效模式**。deb control 注释补库数口径考证（「115」孤例 →
  63 直连 NEEDED / 125 ldd 闭包 / 116 外部 / 3 个 dlopen-only）。
- 本轮文档收网：R7 发布说明 + 轮级工作报告 + 本文件刷新 +
  docs/README.md 索引 + CHANGELOG 补 R7 节。路线图勾选滞后三处挂账
  （AppImage ☐ 已落地 / i18n 清单缺通用设置页 / 对账残余 ☐ 已消账），
  本轮按惯例不动路线图，见[工作报告 §5](reports/WORK_REPORT_2026-11-10_PERF_AND_SETTINGS.md)。
- 门禁实测（03:40-03:41 CST 文档窗口）：analyze 0 告警（8.3s）；37 文件
  **355 通过 / 1 skipped** 全绿（夹具在场，基准段真跑）；CI 不可测
  （`gh run list` EOF）。

## 最近实质性变更（R6·卫生与交付形态，2026-11-11）

三个提交（`988122f` 卫生与依赖收敛、`e1a2df0` AppImage 打包、`b0e1a06`
打磨与 README 对账）。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_HYGIENE_DELIVERY.md) 与
[工作报告](reports/WORK_REPORT_2026-11-10_HYGIENE_DELIVERY.md)。

- AppImage 打包（`e1a2df0`）：`.github/scripts/package-appimage.sh`
  （linuxdeploy；amd64 extract-and-run 冒烟实测通过，arm64 仅 CI 可验），
  release.yaml 挂 `*.AppImage`。产物级复核（文档收网轮）：仓库根
  `EmoPlay_linux_v2.0.0-alpha_amd64.AppImage` 35,584,504 字节、
  `file` 判 static-pie、runtime `--appimage-help` exit 0、
  `.gitignore:62 *.AppImage` 覆盖。
- 仓库卫生与依赖收敛（`988122f`）：web/ 模板目录整体删除 + `.metadata`
  去 web 登记 + `analysis_options.yaml` 两条死排除清理 + 三处 `any` 钉
  版本（synchronized / material_color_utilities / path）+
  `screen_brightness_ohos` 移除（lib/ 零引用）；对应审计
  AUDIT_FULL_2026-11-10 §九-3「P2 卫生批次」。`connectivity_plus` 去留
  评估未决（`metered_network_service.dart:3` 在用）。
- Kazumi 对齐（仅样式层）：关于页「GPL-3.0 许可证」tile 从 Kazumi 仓库
  LICENSE 改指本项目（`about_page.dart:42`，Kazumi 同槽位本就链自家仓库）；
  首页 / 播放页 / 媒体库空态按钮从裸 `FilledButton` 换成已平移的
  `StateActionButton(.tonal)`（64×48 药丸，`state_presentation.dart`）；
  插件页「已定制」徽章改 `errorContainer` 容器对（旧硬编码深棕两主题下
  不可读，`plugins_page.dart:457`）、次要文案改 `bodySmall +
  onSurfaceVariant` 弱化。
- 新增守护测试 `test/kazumi_alignment_ui_test.dart`（3 用例：许可证 tile
  真链接断言经 UrlLauncherPlatform 假体捕获、首页 / 媒体库空态按钮 idiom；
  dev_dependency `url_launcher_platform_interface ^2.3.2` 为测试缝）。
  已知不符：其头注释称 CI 有 hardcoded-color grep 把关，实测两 workflow
  无此步（补步骤或修注释，见工作报告 §5）。
- README 对账：功能清单与实际对齐（设置行补更新检查）、构建依赖补
  `libasound2-dev`（ALSA 头，与 pr.yaml 装步一致）、发布产物表补 AppImage、
  新增「截图」占位说明（GUI 截图待桌面空闲窗口，不产占位假图）、上游
  声明逐项核实（Kazumi `7265274` / media-kit `83b7ca6…` / Anime4K MIT）。
- 文档收网（R6 文档轮）：R6 发布说明 + 工作报告 + 本文件刷新 +
  docs/README.md 索引登记 + CHANGELOG 结构修复（`b0e1a06` 曾把 R5 小节卷
  进 R6 节头下，已恢复「一轮一节」并补 R6 的 Removed / 验证小节）。
- 门禁实测：`flutter analyze` 0 告警；`flutter test` 35 文件
  **345 通过 / 1 skipped** 全绿（施工轮与文档收网轮两次实测一致）。Linux
  debug 构建未在 R6 重跑（无原生构建面改动，R5 实测仍为底数）。CI 不可测
  （api.github.com EOF，02:21 CST）。

## 最近实质性变更（R5·面板观感，2026-11-11 00:19-01:11 CST）

五个提交（`ec1c91e` / `aeda939` / `63d9f59` / `d446bb8` / `8ed84c4`）+ 本轮
文档收网。细节与证据见
[发布说明](releases/RELEASE_2026-11-10_PANEL_LOOK.md) 与
[工作报告](reports/WORK_REPORT_2026-11-10_PANEL_LOOK.md)。

- 播放页两处整页失效修复（`ec1c91e`）：快捷键门禁改 route.isCurrent +
  EditableText 语义（旧门禁守着一个永远没人聚焦的自建 Focus 节点）；
  壳层浮层的 Observer 补上订阅（`&&` 短路导致从不订阅），`pageCurrent`
  observable 由 ModalRoute.isCurrent 驱动。
- 字体定案（`aeda939` + `63d9f59`）：恢复内置 MiSans 后按 Kazumi
  useSystemFont 设计端到端落地：默认系统字体 + 显式 Noto Sans CJK SC
  兜底 + 设置「使用系统字体」开关（默认 true）；SPEC §1 字体行同步。
- 播放面板按 Kazumi@`7265274` 逐槽位重组（`d446bb8`，单文件 402 插入 /
  485 删除），取代上轮 PiliPlus 式手机 6 键行 + 底部更多面板；手机底条
  收敛为播放/暂停、下一集、进度+时间、全屏，宽控件进顶部「更多」菜单。
- 发布管线（`8ed84c4`）：九个 job 补 timeout-minutes；Windows 前置
  `choco install yq` 后恢复 `flutter-version-file: pubspec.yaml`（坑 8(c)
  的权宜转正，版本单一来源）。
- 诊断探针 `test/audio_probe_test.dart` 上线并真跑：pinned ao=pulse 可达
  宿主 pipewire-pulse（`AO: [pulse] 44100Hz stereo 2ch float`）；首趟
  default-ao 读数空串待查（见工作报告 §5）。
- 门禁实测：analyze 0 告警、34 文件 342 用例全绿（1 skip 维持）、Linux
  debug 构建通过、ldd 0 缺失；CI 不可测（api.github.com 两次 EOF）。

## 最近实质性变更（R5，2026-11-10 上午：移动端播放修复 + 手机媒体自动扫描）

手机三问题（横屏左侧 rail / 状态栏与控制条重合 / 无本地媒体自动扫描）+ 桌面
细节打磨。全部已验证：analyze 0 告警、341 用例全绿、Linux debug 构建与
Android `assembleDebug` 通过（模拟器视觉回归未跑：本机无 emulator 镜像且
dl.google.com 不可达）。细节与文件清单见 CHANGELOG.md 的 Unreleased 小节。

- 壳层全出血：`menu.dart` 在全屏播放与手机横屏播放中时隐藏 NavigationBar /
  NavigationRail（修「横屏左侧出现底部选项栏」）。
- 手机全屏接线：`PlayerPageController.setFullscreen` 平台分支，手机走
  `DisplayModeService`（此前已实现但从未被调用的旋转 + 沉浸式通道）。
- 播放面板：安全区 insets（`viewPadding`）、上下渐变遮罩、手机 6 按钮
  传输行 + 「更多」面板、锁定按钮状态切换（`player_item_panel.dart`）。
- 旋转自动全屏：`player_item.dart` `_syncOrientationFullscreen`（PiliPlus
  行为；PiP / 锁定跳过；dispose 兜底恢复系统栏）。
- 手机媒体自动扫描：`lib/services/platform/mobile_media_scanner.dart` +
  `DownloadDirectoryHandler.kt` 新增 `hasStorageAccess` + 媒体库页按钮 /
  空态 CTA / 首次自动触发（`mobileAutoScanDone` 旗标）。
- 首页历史行改缩略图卡片、媒体库搜索框胶囊化、网格卡片悬停描边。
- Android 构建中国镜像：`android/settings.gradle` / `android/build.gradle`
  前置 `storage.flutter-io.cn` + 腾讯云 / 阿里云 maven（本机
  dl.google.com 不可达，镜像后 `./gradlew assembleDebug` 恢复可用）。

## 最近实质性变更（R4，2026-11-10 早晨）

- `b9b3d2c` 发布演练第一跑三红灯修复：macOS pbxproj 的 `Kazumi.app` 残留
  （品牌化改名漏了工程文件，ditto 找不到 EmoPlay.app）改净、Windows 装环境
  改钉 `flutter-version: '3.47.9'`（flutter-action 的 version-file 解析在
  runner 上缺 yq）、arm64 自建 action 补 `libasound2-dev` +
  `libayatana-appindicator3-dev`（缓存冷时源码构建缺 ALSA 头）。
- `bd36f70` Windows 编译修复：runner main.cpp 残留已剥离业务 app_links 的
  死 include（`error C1083`），删除后 `emoplay://` 第二实例唤起仍工作，
  URL 转发记为待做。
- **发布达成**：`v2.0.0-alpha` tag 三次演练（42720144705 ✗ → 42722139024 ✗
  → 42724607274 ✓），GitHub Release 2026-11-10 08:13 CST 公开，9 资产挂
  release（`softprops/action-gh-release` 未设 prerelease → alpha 占
  Latest 位，语义待决策，见[工作报告 §5](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md)）。
- `2598bc8` 1.x `test_mpv_engine.cpp` apply 半边 5 条 live 用例逐用例平移
  （CI 有真 libmpv 后可做；`doubleInitializeRejected` 不移植，理由在测试
  文件头注释） - R1-R3 挂账的对账残余只剩 settings 恢复默认一条。
- `2c6bf06` 剩余欠账：设置页音频类 i18n 第二页（`audioEqualizerPresetLabels`
  单一来源 + 十频段行，`test/audio_settings_l10n_test.dart` 4 用例，zh+en，
  真实页面挂载）+ 中英 README「发布产物」章节。
- 本轮文档：R4 发布说明 / 工作报告、HANDOVER 刷新、路线图数字与轮次表修正、
  CHANGELOG 补 R4 与发布条目（见[工作报告](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md)）。

## 最容易踩的坑

1. **构建前必须 `source /opt/emoplay-env.sh`** - 否则 PATH 里可能没有 Flutter 或
   用错 SDK；`PUB_CACHE=/opt/pub-cache` 也是它设的。宿主机零污染、
   `/home/emo/code/mpv-emo` 只读是硬红线（SPEC §3）。
2. **CI 信号要按归因链读**（[R2 报告 §3.1](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)、
   [R3 报告 §3.1](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)、
   [R4 报告 §3.1](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md)）：
   纯 markdown 推送不触发 CI（pr.yaml `paths-ignore: '**.md'`），但**代码与
   文档混在同一次 push 时会触发，且 run 标题只显示头提交**（R2/R3/R4 三轮
   连续证实，release 侧 tag 移动后标题跟随新头提交 - 按 ref 列判演练）。
   另：**本地全绿 ≠ CI 绿** - runner 环境差异修 workflow，绝不跳过用例；
   **dlopen 每次只报第一个缺失依赖**，依赖缺口看 pr.yaml 的 ldd 审计步
   全量清单，不要按测试报错逐层补。真开 libmpv 的测试依赖装步在
   `flutter test` 之前。
3. **平移铁律**：1.x 源文件注释里嵌着 mpv v0.37 源码级考证，必须连注释一起搬；
   `history.json`/`library.json`/`settings.json` 字段名一个都不能改（PORT-MAP 头部）。
4. **产品决策兜底顺序**：规格未覆盖取最接近 Kazumi 现状；与 SPEC §4 不变量冲突时
   不变量赢（SPEC §10）。
5. **文档提交与代码提交分开**：`docs:` 前缀，文档只动 markdown 与 CHANGELOG.md
   （DOC-STANDARD 提交前检查清单最后一条）。
6. **打包产物别留在仓库根**：`package-linux.sh` / `package-appimage.sh`
   把 deb/tar.gz/AppImage/打包目录写在当前目录；`.gitignore` 已有
   `EmoPlay_linux_*/`、`*.deb`、`*.AppImage` 规则（审计轮补前两项，R6
   `e1a2df0` 补 AppImage），不会被误提交，但本机验证完仍建议清掉，CI 里
   靠 release.yaml 的 upload-artifact 路径收集。
7. **品牌化改名要跨全平台目录核对**：M1 改了应用名/applicationId，但
   `macos/Runner.xcodeproj/project.pbxproj` 的 Kazumi.app 引用漏网，直到
   发布演练才在 CI 炸出（drill#1）；改平台工程文件时逐平台 grep 旧品牌名
   （Kazumi / com.example.kazumi）再收工。
8. **发布语义四件事**：(a) `v2.0.0-alpha` 已是公开的 Latest release - 再演练
   要先删 release 与 tag，且移动 tag 重跑会连烧三次矩阵分钟数（本轮
   46 分钟+）；(b) **发布产物对应 tag 指向的提交，不是 main HEAD** - 推送
   R4 后不重打 tag 就不会有新产物；(c) Windows 上 flutter-action 的
   `flutter-version-file` 需要 yq（runner 不预装），版本钉在
   release.yaml（升级 Flutter 时与 `pubspec.yaml` 同步手改）。`8ed84c4`
   起已转正：Windows job 前置 `choco install yq`，版本恢复
   `flutter-version-file: pubspec.yaml` 单一来源，升级 Flutter 只改
   `pubspec.yaml`；(d) **R7 起发布为 draft 制**：tag 触发的 `Create release`
   步带 `draft: true`，跑完是 draft（不公开、不占 Latest、draft 不能被设为
   Latest），人工核对产物后手动 publish：`gh release edit <tag>
   --draft=false`（流程见 [guides/BUILD_GUIDE.md](guides/BUILD_GUIDE.md)
   §四）- **忘 publish 是新流程的主要失效模式**，draft release 在公开
   Releases 页看不到。
9. **门禁别守「没人会聚焦的节点」**：播放页快捷键曾整页失效（门禁要求
   primaryFocus 在自建 `keyboardFocus` 内，而没有任何交互会让它成为
   primaryFocus），壳层浮层曾不隐藏（Observer builder 内 `&&` 短路导致
   从未订阅）。写法约定：快捷键门禁用 route.isCurrent + EditableText
   检测（`player_keyboard_shortcuts.dart:134-148`）；Observer 内
   observable 必须无条件读取。
10. **字体链动一处要想到 fontconfig**：fontFamily 置空必须同时带显式 CJK
    兜底（`theme_provider.dart` 的 `kAppFontFamilyFallback`），否则中文
    可能被 fontconfig dump 到楷体风字体（M1 的楷体事故）；改字体相关
    代码时三条 ThemeData 路径（静态 / 动态配色）都要带上 fontFamily。
11. **fork 预置 vid=no：headless live 测试的夹具必须带音频轨或显式
    `vid=auto`**：VideoController attach 前 mpv 对纯视频文件会以
    「No video or audio streams selected」直接卸载，逐帧 / 章节等 live
    用例会静默空转（R9 考证，`mpv_player_properties.dart:37` 注释随行）；
    应用层不受影响（播放页总挂 VideoController）。
12. **选轨 / 快捷键真相源别用表面 API**：fork 的
    `Player.state.track.subtitle` 在裸 `sub-add` 后 stale，选轨状态要看
    mpv `sid` 属性（R9 实测）；快捷键分发按 `keyLabel`、不区分 Shift，
    字母键恒大写，mpv z/Z 型双键惯例映射不进本表（字幕延迟取 C/V 的
    根因，`constants.dart` 注释随行），新键位用
    `test/player_shortcut_keys_test.dart` 的模式锁 keyLabel 身份与冲突。
13. **新增落盘文件 ≠ 改 §7 schema，但缓存失效键要想清楚**：M4 一轮加了
    favorites.json / media_meta.json / media_nfo.json 三个 AppData 文件
    （各带损坏降级 + 原子写，data_compat 契约测试照跑，先例成立）；
    但失效键各有讲究：media_meta.json 键 `sha1(path+mtimeMs)` 与缩略图
    链同输入（改一个文件两缓存同失效），media_nfo.json 条目带 video +
    目录双 mtime（改海报/NFO 动的是目录 mtime）；app 外改刮削文件后
    要等重扫才刷新，没有文件监听。
14. **本地刮削的约定面很窄，排障先对约定**：海报只探四名
    （`<名>-poster.jpg` / poster.jpg / folder.jpg / fanart.jpg，png 变体
    不探测）；剧集只认文件名词边界的 SxxEyy / 1x02（`M4S01E02` 是文件名
    不是剧集，词边界守卫故意如此）；NFO 类型看根元素不看文件名，坏
    字段跳过不崩；`<thumb>` URL 只记录不抓取（联网兜底框架 M4-T7 已于
    R11 落地，默认关、真实数据流待 TMDB key 验收）。
    约定不匹配不是 bug，是增补范围的有意收窄。
15. **列表循环的回卷在应用层，别把它「修」回引擎**：`playlist` 档刻意映射
    `PlaylistMode.none`（引擎 loop 关）。media_kit `open(Media)` 只向 mpv
    装一个 entry 的内部 playlist，`loop-playlist=yes` 会让 mpv 无限回卷
    同一文件、completed/eof 永不到应用层，队列续播随之失效；队列推进走
    `PlayerProgressPipeline` → `resolveQueueNextIndex`
    （`lib/music/music_queue.dart` 文件头有完整考证），改队列/循环语义前
    先读它。
16. **replaygain / gapless：属性层绿 ≠ 听感生效**：runtime setProperty 被
    接受且回读一致只到属性层（R11 live 用例），增益 / 无缝的听感属 mpv
    选项自身契约，SPEC §9 人工验收挂账；off 档刻意显式钉 mpv `'no'`
    （审计表陈述意图，不靠「没写 = 默认」），导入 mpv.conf 显式项后写者
    胜（compatOptions 在 build() 最后 addAll，测试锁定）。
17. **media_online.json 的负缓存语义**：正命中与**明确未命中**都落盘，
    传输失败（断网 / 超时 / HTTP 错误 / 损坏响应）**永不缓存**（网络恢复
    后重试）；本地 NFO 覆盖的条目永远不联网。排障先对五道门禁顺序与
    key 掩码显示（`lib/media/online/online_meta_service.dart` 文件头）。
18. **mpv.conf 行内注释：runtime 应用 ≠ 文件读取**：compat 层把每行当
    运行时属性下发，`#` 在属性语境不是注释；runtime 值必须经
    `MpvConfigParser.runtimeOptionValue` 清洗（空白前导 `#` 起注释、
    紧贴值首的 `#` 是颜色码要保留，`mpv_config_parser.dart:137`）。
    绕过它做新解析时注释文本会静默变成值（R12 无声事故根因，
    `07427f8`；字符串型不报错、数字型 apply 失败，最隐蔽的是前者）。
19. **帧预览第二实例：属性集只有一张表，隐藏只 pause 不拆**：
    `seekPreviewMpvProperties`（`seek_preview_controller.dart:62`）是
    生产创建与测试断言共用的单通道，改属性只改表（漂移即红）；
    fork 预置 vid=no，预览实例必须 attach VideoController 才有画面；
    气泡隐藏是取消挂起 seek + pause（Haruna Loader active 语义），
    别把它「修」成销毁重建；关闭开关时零实例由
    `performance_guards_test` 两条守卫锁定。
20. **插件安全三件事的位置**：完整性对（sizeBytes+sha256）缺一拒装的
    闸门在 install/replace-update 链**最前**（任何 git 命令之前）；
    摘要定义（`.git` 剪枝、符号链接跳过、相对路径排序、
    `<hash>  <path>\n` 清单再整体 sha256）在 `PluginContentIntegrity`
    文件头，插件作者算钉值必须按它；`plugin_audit.jsonl` 是观察性
    日志（写失败吞掉、损坏行跳过），拦截逻辑挂在三段式确认链与
    porcelain 防线，别挂到审计上。另：`test/plugin_audit_test.dart:117`
    夹具内嵌字面 NUL 字节，git 视整文件为二进制（diff 不可文本评审），
    评审请直接读文件。

## 接手第一步清单

1. `source /opt/emoplay-env.sh && cd /home/emo/code/emoplay && flutter analyze && flutter test`
    - 预期 0 告警 + 585 通过 / 1 skipped（63 文件，R12 实测底数；1 skip =
      Windows-only 探针，按设计跳过。真 libmpv live 用例真跑；
      /tmp/emoplay-perf-lib 夹具在场时 4 段基准真跑，缺失时 skip 打印
      降级同样全绿，夹具可用 `tools/gen_perf_fixture.sh` 重建），
      达不到先查环境再查代码。
2. `git fetch origin && git log origin/main..HEAD --oneline` 与
   `gh run list -R emoeem/emoplay --limit 5`（gh 属窗口性，2026-11-13
   窗口 EOF） - 确认 R12 后两提交（`7b89bb0` / `3514db3`）与本轮文档
   （含路线图工作树回填）是否已推送、推送后 CI 是否
   **585 passed / 1 skipped**；红灯按坑 2 的归因链处理。
3. 通读 [SPEC.md](SPEC.md) §4 不变量与 [PORT-MAP.md](PORT-MAP.md) 头部铁律；
   3.0 施工任务从 [EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md) §五取
   （M4 七任务全 ✅ 含 T7 框架、M5 三任务全 ✅、M6 四任务全 ✅、
   M3-T0/T1 ✅；M3 剩 T2 刻度收口 / T3 悬浮面板 / T4-T9；下一阶段
   M7 诊断/测试；TMDB 真实联网数据流、replaygain/gapless 听感、帧预览
   画面三项目人工验收待用户，见 R12 报告 §5）。
4. 2.0 尾巴从 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) §四
   未做项清单取（发布产物实体机验证 → prerelease 语义 → i18n 其余设置页
   → 签名/公证；性能实测已 R7 ✅、AppImage 打包已 R6 `e1a2df0` 落地，
   路线图 §四 与 R3-R7 轮次表的勾选态以路线图下次收网为准），以及
   [最新工作报告 §6](reports/WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md)
   的优先级建议。
5. 改完代码跑 SPEC §9 gate（build_runner → analyze → test → build linux）。

## 路线图

2.0 迁移路线图的权威来源是
[UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)
（M0-M8 ✅+提交哈希、R1-R4 收尾轮次、未做项 ☐、验收标准与贯穿约定）；
**3.0 施工路线图是 [EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md)**
（M3-M8 文件级任务书与机检验收，R9 起施工按它推进）；逐里程碑的内容细节
另见 [CHANGELOG.md](../CHANGELOG.md) 的 Unreleased 各小节，轮次结构与
积压清单见 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四。
