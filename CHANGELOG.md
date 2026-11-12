# Changelog

格式参考 Keep a Changelog；预发布序列 alpha → beta → rc。EmoPlay 2.0 是
1.x（[mpv-emo](https://github.com/emoeem/mpv-emo)，C++/Qt6）在 Flutter 上的
重写：迁移决策依据 `docs/SPEC.md`，文件级映射见 `docs/PORT-MAP.md`，
Kazumi 剥离清单见 `docs/STRIP-LIST.md`。1.x 的版本历史见旧仓库的
`CHANGELOG.md`。

## [2.4.0-alpha] - 2026-11-13（已发布）

R12 施工收口（tag `v2.4.0-alpha`；`pubspec.yaml` version
`2.3.0-alpha+2030000` → `2.4.0-alpha+2040000`）。3.0 路线图
（`docs/EMOPLAY-3.0-ROADMAP.md` §五 M6）插件安全四任务（清单完整性 /
操作审计 / destination 防穿越 / 插件页 catalog）+ M3-T1 进度条帧预览
+ mpv.conf 行内注释无声根因修复（用户报告）。本轮要点（全部实测取证，
分项明细见下）：

> 第 12 轮施工：M6 插件安全四任务（清单完整性 / 操作审计 / 暴力面
> 收缩 / 插件页 catalog）+ M3-T1 帧预览 + mpv.conf 行内注释无声修复。
> 全量测试 63 文件 585 用例 + 1 平台条件跳过（2026-11-13 文档窗口实测，
> 明细见 docs/releases/RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md）。

### Added

- **插件清单资产完整性（M6-T1，`757d130`）**：manifest 可选
  `sizeBytes` + `sha256` 全有全无对（缺一拒装，`integrityGateError()`），
  闸门在 install / replace 型 update 链**最前**（任何 git 命令之前）；
  克隆内容先验后记（`PluginContentIntegrity`：`.git` 剪枝、符号链接
  跳过、相对路径排序、`<hash>  <path>\n` 清单再整体 sha256，字节数
  独立先比），不匹配即删刚克隆的树；不声明字段 = 1.x 行为逐位不变
  （`toMap()` 条件输出 + 往返用例锁定）。测试：plugin_manifest_test
  +5、plugin_manager_test +4。
- **插件操作审计（M6-T2，`757d130`）**：新 AppData 文件
  `plugin_audit.jsonl`（plugins/ 兄弟文件）append-only JSONL，
  plan/operation 两类事件、拒绝也留痕（busy / 已安装 / porcelain 防线 /
  完整性拒绝同一出口）；观察性日志（写失败吞掉、损坏行跳过），从不
  阻断操作。新增 `test/plugin_audit_test.dart`（5 用例，验收线 ≥4）。
- **destination 防穿越 fuzz + 操作白名单（M6-T3，`0919ccc`）**：敌意
  destination 语料 12 条 + 形似对照 4 条 + 符号链接两类端到端钉死
  （parse 拒绝 / 整目录 fail-closed / git 零调用）；planOperation 字符串
  动作收敛为 `allowedOperations` 常量白名单，未知动作默认拒绝。
  plugin_manager_test +6。
- **插件页 catalog 重组（M6-T4，`7b89bb0`）**：Kazumi plugin_editor
  范式（搜索框 + 全部/已安装/可更新过滤 chip + 每插件详情页 + 更新
  动作独立成件），三段式 UI 语义不变（不变量 6）；plugins_page
  577→485 行拆四件（dispatch/row/detail/actions，全部 <600 行）；新增
  `test/plugin_catalog_test.dart` 9 用例。
- **进度条帧预览（M3-T1，`3514db3`）**：hover / 拖动出帧图，第二
  media_kit 解码实例（Haruna MpvPreview 语义移植，属性集等价表
  `seekPreviewMpvProperties` 生产/断言共表，mute/pause/aid=no/sid=no/
  osd-level=0 等逐项对照 mpvpreview.cpp:21-38）；激活门禁五条件同
  Haruna HProgressBar（开 && 本地文件 && 视频 && 非停止），hover 懒建
  + 100ms 消抖、隐藏即取消挂起 seek 并 pause 实例、拖动双 seek；开关
  `seekPreview` **默认关**（Haruna kcfg 同默认，关闭零第二实例开销，
  实例数守卫锁定）+ `seekPreviewWidth` 默认 200（滑杆 120-400）；
  气泡带章节标题（复用 M3-T2 上界二分）。属性集 live probe 2026-11-13
  实测全过；画面效果待 GUI 人工验收（SPEC §9）。新增
  `test/seek_preview_controller_test.dart` 10 用例（验收线 ≥6）+
  performance_guards_test +2。

### Fixed

- **带注释的 mpv.conf 导致无声**（`07427f8`，用户报告 2026-11-12，
  v2.2.0-alpha / v2.3.0-alpha 可复现）：1.x 由 mpv 读文件（空白前导
  `#` 是行尾注释），2.0 兼容层把每行当运行时属性下发（属性语境 `#`
  不是注释），字符串型选项静默把注释文本当值收下（audio-device 变成
  `auto # 此项用于指定启动时的音频输出设备`，设备找不到，每会话
  「Could not open/initialize audio device -> no sound」）。根因修复：
  `MpvConfigParser.runtimeOptionValue`（`mpv_config_parser.dart:137`）
  复刻 mpv 文件语义（空白前导 `#` 起注释、紧贴值首 `#` 是颜色码保留），
  设置编辑器往返保留原始行，审计表报告清洗后值；5 条回归测试取自
  报告人真实 conf 行（mpv_config_parser_test +4 / mpv_import_rules_test
  +1）。

### 验证

- 本地门（R12 施工/文档窗口实测，2026-11-13）：`flutter analyze` 0
  告警；`flutter test` 63 文件 **585 通过 + 1 平台条件跳过**全绿
  （1 skip = Windows-only 探针，按设计跳过；新增用例 46 逐文件计数与
  全量差值 585-539 闭环；真 libmpv live 用例真跑）。
- CI：R12 五提交已推送（origin/main = `5b1c5d9`，2026-11-13 fetch 实测
  ahead 0）；main run 43263474834 ✓（CI 签名 **585 tests passed /
  1 skipped**，与本地门一致）。发布门随 `v2.4.0-alpha` tag 触发
  release.yaml 矩阵，全绿后 draft 收口（同 v2.2/v2.3 流程）。

## [2.3.0-alpha] - 2026-11-12（已发布）

R11 施工收口（tag `v2.3.0-alpha`；`pubspec.yaml` version
`2.2.0-alpha+2020000` → `2.3.0-alpha+2030000`）。3.0 路线图
（`docs/EMOPLAY-3.0-ROADMAP.md` §五 M5）音乐三任务（循环/队列、
replaygain/gapless、歌词与迷你条）+ 用户改向纳入的在线元数据兜底框架
（M4-T7）。本轮要点（全部实测取证，分项明细见下）：

> 第 11 轮施工：M5 音乐三任务（循环/队列、replaygain/gapless、歌词与
> 迷你条）+ 用户改向纳入的在线元数据兜底框架（M4-T7）。全量测试
> 60 文件 539 用例 + 1 平台条件跳过（2026-11-12 文档窗口实测，明细见
> docs/releases/RELEASE_2026-11-10_M5_MUSIC_METADATA.md）。

### Added

- **循环模式三态与音乐队列面板（M5-T1，`2115183`）**：
  `player_playback_controller.dart:443` 的 `PlaylistMode.none` 硬编码提升
  为 settings.json `behavior.playlistMode` 三态（none/single/playlist，
  默认 none = 1.x 现状，追加键 + 默认值/往返用例随行），设置下拉、播放
  面板菜单、music 形态「播放队列」面板三动线可切；单曲循环走引擎原生
  loop-file，列表循环刻意不开引擎 `loop-playlist`（media_kit 单 entry
  装载下会让文件无限自循环、completed 永不到应用层），回卷在应用层
  （PlaybackSession 事实源 + `resolveQueueNextIndex` 纯决策函数）；新增
  `test/music_queue_test.dart`（7 用例，验收线 ≥5）。
- **replaygain 与 gapless（M5-T2，`ec456b3`）**：设置 → 音频「音频属性」
  分组：响度均衡（ReplayGain）三档 off/track/album（默认 off = 1.x 现状
  从未写过该属性；off 显式钉 mpv `'no'` 让审计表陈述意图；未知/损坏取值
  回落不启用；导入 mpv.conf 显式项后写者胜）、`gapless-audio=weak` 钉为
  全局预置（mpv 默认已是 weak，shipped libmpv 回读实测；防 fork 默认
  漂移）；1.x 明文遗留项清偿；属性层 live 用例真跑，增益/无缝的听感生效
  待 SPEC §9 人工验收。
- **歌词升级与常驻迷你条（M5-T3，`a539866`）**：歌词页首帧定位修复
  （根因：此前只跟随 lyricIndex 变化，歌词加载晚于首帧时第一行不定位）
  + 滚动动画时长与滚动距离成比例（120-420 ms 夹紧）+ 翻译列（同时间戳
  相邻行分组，第一行原文其余译文，行高常量滚动确定性）；常驻迷你条
  `music_mini_bar.dart`（非播放页底部显示当前曲目/播放暂停/进度，点击回
  播放页与点 tab 同源；视频条目同样适用，文件名跟随路线图命名）。
- **在线元数据兜底框架（M4-T7，2026-11-12 用户改向纳入）**：本地
  NFO/海报（M4-T6）之后的联网补全框架轮。`lib/media/online/` 三件：
  provider 接缝、TMDB 适配器骨架（注入 http.Client，测试用 mock 不真连）、
  `OnlineMetaService`（五道门禁：总开关关 → 无 API key → 本地 NFO 覆盖
  → media_online.json 缓存命中 → 才发起联网；断网/超时/损坏响应/HTTP 错
  误全部降级不崩溃，传输失败不落缓存）。设置中心新增「在线元数据」分类：
  总开关**默认关闭**（本地优先）+ TMDB API key 输入项（settings.json 增
  `online` 段，默认值与往返用例按 §四红线补齐）。媒体库 NFO 详情弹层挂
  「联网补全」动作，无 key / 关闭 / 本地覆盖 / 断网各有优雅提示，命中与
  明确未命中缓存到新文件 `media_online.json`（三份 §7 schema 一个字段不
  改）。可达性实测（2026-11-12）：api.themoviedb.org 可达，curl 0.83s /
  Dart HttpClient 1.04s，无效 key 恰返 HTTP 401 标准错误体（2026-11-11
  GitHub API 的 TLS ECONNRESET 未复现于 TMDB）；**真实联网数据流待用户
  填入有效 TMDB API key 后人工验收（pending）**。新增
  `test/online_meta_service_test.dart`、`test/tmdb_provider_test.dart`、
  `test/library_online_ui_test.dart`，`flutter test` 全量 539 绿。

### 验证

- 本地门（R11 施工/文档窗口实测，2026-11-12 07:00 CST）：`flutter
  analyze` 0 告警；`flutter test` 60 文件 **539 通过 + 1 平台条件跳过**
  全绿（1 skip = Windows-only 探针，按设计跳过；新增用例 50 逐文件计数
  与全量差值 539-489 闭环；真 libmpv live 用例真跑）。
- CI：R11 五提交已推送（origin/main = `e5a5e0d`，2026-11-12 fetch 实测
  ahead 0）；main run 43117670715 ✓（CI 签名 **539 tests passed /
  1 skipped**，与本地门一致）。发布门随 `v2.3.0-alpha` tag 触发
  release.yaml 矩阵，全绿后 draft 收口（同 v2.2.0-alpha 流程）。

## [2.2.0-alpha] - 2026-11-12（已发布）

R10 施工收口（tag `v2.2.0-alpha`；`pubspec.yaml` version
`2.1.0-alpha+2010000` → `2.2.0-alpha+2020000`）。3.0 路线图
（`docs/EMOPLAY-3.0-ROADMAP.md` §五 M4）媒体库升级整轮施工 + R9 挂账的
M3-T0 清偿 + 用户增补的本地 NFO / 海报 / 剧集分组（M4-T6）。本轮要点
（全部实测取证，分项明细见下方 R10 节）：

### Added

- **统一媒体模型与播放队列收编**（M4-T0，`0da4a95`）：`MediaItem` /
  `PlaybackSession` / 无损映射器；基础字段逐字段对齐 §7 store 语义，
  3.0 扩展槽可空且永不写回 1.x 数据文件，播放页以 `PlaybackSession` 为
  事实源（不变量 4 的 resume 语义不动）。
- **元数据缓存**（M4-T4，`0da4a95`）：`media_meta.json` 新 AppData 文件，
  两段 ffprobe 链（容器 → 编码 + 宽高），缓存键 `sha1(path+mtimeMs)`，
  30s 超时强杀、无 ffprobe 优雅降级、命中零进程。
- **网格分组与目录树侧栏**（M4-T2/T5，`25dd830`）：媒体库 SliverGrid +
  pinned 分组头（目录 / 年月 / 剧集 / 电影四种），search / typeFilter /
  sortMode 语义不变；面包屑 + 目录树，深度剪枝从
  `LibraryStore.scanOptions` 派生，不加新扫描。
- **收藏集**（M4-T3，`25dd830`）：`favorites.json` 新 AppData 文件，卡片
  收藏角标、拖拽排序弹层（失效收藏降级文件名不丢条目）、损坏 JSON 降级 +
  原子写用例锁定。
- **本地 NFO / 海报 / 剧集分组**（M4-T6 用户增补，`5fedee0`）：手写容错
  NFO 解析（Kodi 语义）、海报四名约定（sidecar → poster → folder →
  fanart）、SxxEyy / 1x02 词边界解析与剧-季-集三级分组、本地海报上格子、
  NFO 详情弹层、`media_nfo.json` 双 mtime 缓存；`<thumb>` URL 只记录不
  下载（联网兜底排期第 11 轮）。

### Changed

- **`player_item.dart` 拆分**（M3-T0，`c9245f8`，R9 挂账清偿）：1614 →
  484 行（验收线 <500），拆出十个职责文件（全部 <600 行）；纯搬移不改
  行为，用户可感知变化为零。

### 验证

- 本地门（R10 施工/文档窗口实测）：`flutter analyze` 0 告警；`flutter
  test` 54 文件 **489 通过 + 1 平台条件跳过**全绿（1 skip = Windows-only
  探针，按设计跳过）；分项计数与全量差值交叉核对见下方 R10 节。
- 发布门：release.yaml 矩阵（flutter-test / flutter-analyze 前置，Android
  split-per-abi ×3、Windows zip+msix、macOS zip、Linux amd64 / arm64
  tar.gz+deb+AppImage）全绿后产物落 draft，人工核对产物集后
  `gh release edit v2.2.0-alpha --draft=false` 公开（同 v2.1.0-alpha 流程）。

### R10 · M4 媒体库升级轮（2026-11-12）

> 3.0 路线图（`docs/EMOPLAY-3.0-ROADMAP.md` §五 M4）整体施工 + R9 挂账的
> M3-T0 清偿 + 用户增补的本地 NFO / 海报 / 剧集分组（M4-T6）。施工于
> v2.1.0-alpha 发版之后，随 v2.2.0-alpha tag 收口发布。

#### Added

- **统一媒体模型与播放队列收编**（M4-T0，`0da4a95`）：`MediaItem` /
  `PlaybackSession` / 无损映射器；基础字段逐字段对齐 §7 store 语义，
  3.0 扩展槽全部可空且永不写回 history.json / library.json /
  settings.json（`test/data_compat_spec7_test.dart` 契约测试保持绿）；
  播放页以 `PlaybackSession` 为事实源，对外 playlist 接口不变，resume
  语义仍归 `PendingResumeSeek`（不变量 4）。
- **元数据缓存**（M4-T4，`0da4a95`）：`media_meta.json` 新 AppData 文件，
  两段 ffprobe 链（容器 → 编码 + 宽高），缓存键 `sha1(path+mtimeMs)` 与
  缩略图链同输入，30s 超时强杀，部分失败缓存可用部分，无 ffprobe 时
  优雅降级且已缓存条目继续服务，命中零进程。
- **网格分组**（M4-T2，`25dd830`）：媒体库网格 SliverGrid + pinned 分组
  头，search / typeFilter / sortMode 语义不变；分组键 / 输入序保持契约
  随行注释。初始目录 / 年月两种，剧集 / 电影两种随 M4-T6 到场。
- **收藏集**（M4-T3，`25dd830`）：`favorites.json` 新 AppData 文件
  （条目 = path + addedAt，渲染期对库索引 join、不复制 §7 数据），卡片
  收藏角标、ReorderableListView 拖拽排序弹层（失效收藏降级文件名不丢
  条目）、损坏 JSON 降级 + 原子写用例锁定。
- **目录树侧栏**（M4-T5，`25dd830`）：面包屑 + 树，深度剪枝从
  `LibraryStore.scanOptions` 派生（树在扫描停的地方结束），不加新扫描。
- **本地 NFO / 海报 / 剧集分组**（M4-T6 用户增补，`5fedee0`）：手写容错
  NFO 解析（Kodi 语义：类型看根元素、跳过根前垃圾、多根取首块、坏字段
  跳过不崩）、海报四名约定（sidecar → poster → folder → fanart，最具体
  优先）、文件名 SxxEyy / 1x02 词边界解析与剧-季-集三级分组（无标记落
  未分组桶，一行不丢）、网格剧集 / 电影两种分组（嵌套 SliverMainAxis
  Groups + pinned 头）、本地海报上格子、NFO 详情弹层；`media_nfo.json`
  缓存（video + 目录双 mtime 失效）；`<thumb>` URL 只记录不下载（本地
  优先，联网兜底排期第 11 轮）。

#### Changed

- **`player_item.dart` 拆分**（M3-T0，`c9245f8`，R9 挂账清偿）：1614 →
  484 行（验收线 <500），拆出 PiP / 音频绑定 / 键盘 / 菜单 / 手势 /
  面板持有 / 进度管线 / 截图动作 / 截图胶片 / 超分提示十个职责文件
  （全部 <600 行），`player_screenshot_sheet.dart` 1052 → 855 行；纯
  搬移不改行为，用户可感知变化为零。

#### 验证

- `flutter analyze` 0 告警（`No issues found! (ran in 4.8s)`）；
  `flutter test` 54 文件 **489 通过 + 1 平台条件跳过**全绿（2026-11-12
  文档窗口实测；上轮 44 文件 / 411 + 1，+10 文件 / +78 用例：mappers 11、
  meta cache 9、favorites 7、folder tree 5、grid grouping 6、episode
  grouper 13、NFO UI 1、NFO meta cache 10、NFO parser 10、poster
  finder 6，逐文件实测计数与全量差值交叉核对一致）。1 skip = Windows-only
  探针（`mpv_profile_scanner_test.dart`，按设计跳过）。/tmp 夹具缺失时
  perf 基准段与音频探针按 skip-打印降级（计数不变），live libmpv 用例
  真跑。gh 本窗口恢复可达：R9 尾提交 `e9bf692` main run 43069268623 ✓、
  v2.1.0-alpha release run 43069322152 ✓（release 已公开 11 资产）。
  发布窗口补记：本轮四提交与 docs 收网提交 `f87b4e2` 均已随 main 推送
  （2026-11-12 fetch 实测 ahead 0）；随 v2.2.0-alpha tag 触发的发布矩阵
  flutter-test job 为 CI 实测签名来源，预期 **489 passed / 1 skipped**。
  分轮明细见
  `docs/releases/RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md` 与
  `docs/reports/WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md`。

## [2.1.0-alpha] - 2026-11-12（已发布）

R5–R9 施工收口（tag `v2.1.0-alpha`；`pubspec.yaml` version
`2.0.0-alpha+2000000` → `2.1.0-alpha+2010000`）。R8（`3dcfb6a`，2026-11-11）
为纯文档轮（3.0 路线图 / 跨平台验证矩阵 / fork 治理三件套），无用户可感知
变化。本轮要点（全部实测取证，分轮明细见下方五节）：

### Added

- **章节导航**（R9，`f2b7754`）：mpv `chapter-list` / `chapter` 属性读取
  （fork `readNativeString` 回读，JSON 形态逐条实测，非该形态降级空表不
  崩）+ 底板章节面板（当前章高亮，无章节文件优雅隐藏）+ Page Up /
  Page Down 跳章快捷键。M3-T2 验收面的进度条章节刻度 / hover 章节标题 /
  中键跳章未做（记录于
  `docs/releases/RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md` §五）。
- **字幕管理**（R9，`a8cb844`）：字幕轨道切换面板、外挂字幕加载
  （srt/ass/ssa/vtt/sub）、关闭字幕、字幕延迟 ±0.5s 步进（±0.5 重复累加
  的二进制小数漂移以一位小数舍入兜住）；选轨真相源是 mpv `sid` 属性
  （fork `Player.state.track.subtitle` 在裸 `sub-add` 后保持 stale，fork
  实测探针记录于
  `lib/pages/player/controller/player_subtitles_controller.dart:13`）。
- **A-B 循环与逐帧步进**（R9，`2e5d73d`）：A-B 循环三态（设 A → 设 B →
  清除，B 点 ≤ A 点客户端拒绝），键位 L；`frame-step` / `frame-back-step`
  （键位 `.` / `,`，暂停态控制条显示上一帧 / 下一帧按钮；fork 命令表
  strings 实测可用，frame-back-step 需 mpv ≥0.38，fork 降级须复检）。
- **设置 → 通用「恢复默认设置」**（R7，`d971af0`）：quality / behavior /
  music 三分区回 1.x schema 默认，媒体库、观看历史与 mpv 配置导入决策
  不动（`test/settings_service_semantics_test.dart:139` 逐字节不变语义
  测试锁定）；通用设置页 zh / en 双语 i18n 第三页。
- **性能实测**（R7，`87b3760`）：2000 条目夹具、容器 Isolate 计时——
  worker isolate 热扫 125ms（≈16000 files/s）、进度回调 63 次（32 步长
  节流）、library.json 装载 1.7–2.2ms（远低于 100ms 阻塞阈值，判定不改
  代码）、缩略图串行链 77–81ms/作业、并发重叠 0；数字全录
  `docs/reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md`。
- **Linux AppImage 产物**（R6，`e1a2df0`）：linuxdeploy 打包接入
  release.yaml（amd64 本地 extract-and-run 冒烟实测通过；arm64 走
  linuxdeploy-aarch64，仅 CI 可验）；依赖收敛与 web/ 模板目录清理
  （`988122f`）。
- **tag 发布 draft 制**（R7，`0a3436c`）：release 产物先落草稿、不占公开
  Latest 位，人工核对产物集后 `gh release edit <tag> --draft=false` 公开
  （本节即按此流程发布）。

### Fixed

- **播放中快捷键全部失效**（R5，`ec1c91e`）：键盘处理器把「是否处理」门
  在 primaryFocus 位于面板自建 `keyboardFocus` 内的永假条件上；改为
  「当前路由 isCurrent + 焦点不在任何 EditableText」（PiliPlus
  player_focus 语义，`player_keyboard_shortcuts.dart`）。
- **播放页导航浮层残留**（R5，`ec1c91e`）：壳层 `menu.dart` 在 Observer
  builder 内用 `&&` 短路读状态，observable 未被订阅，导航条 / rail 该
  隐藏时不隐藏；现 observable 无条件读取 + `pageCurrent`
  （`ModalRoute.isCurrent` 驱动）派生全出血与页签高亮。
- **CJK 落楷体（LXGW ZhenKai）**（R5）：恢复 Kazumi 内置 MiSans-Regular
  （8,122,324 字节，`aeda939`）+ 设置 → 主题「使用系统字体」开关（默认
  开，关闭后切内置 MiSans，`63d9f59`）；两条路径显式携带 CJK 兜底，
  不再信任 fontconfig 猜字体。
- **播放面板按 Kazumi@`7265274` 逐槽位重组**（R5，`d446bb8`，402 插入 /
  485 删除）：手机与桌面共用一套槽位（底条 = 播放/暂停、下一集、进度+
  时间、全屏；宽控件进顶部「更多」菜单），取代 PiliPlus 式组合；渐变
  遮罩与安全区 insets 保留，播放 tick 只重建进度条与时间标签。
- **library_store_test 扫描静止态竞态**（R9，`a8cb844`）：链式扫描管线
  排干前断言静止态偶发红灯，补 `pumpUntil(() => !store.isScanning)` 排水
  等待，产品代码零改动。

### 验证

- 本地门（R9 收网窗口 2026-11-12 实测，两遍同数）：`flutter analyze`
  0 告警；`flutter test` 44 文件 **411 通过 + 1 平台条件跳过**（1 skip =
  Windows-only 探针 `mpv_profile_scanner_test.dart:217`，按设计跳过）。
  分轮验证数字见下方各轮「验证」小节。
- 发布门：release.yaml 矩阵（flutter-test / flutter-analyze 前置，Android
  split-per-abi ×3、Windows zip+msix、macOS zip、Linux amd64 / arm64
  tar.gz+deb+AppImage）全绿后产物落 draft，人工核对产物集后
  `gh release edit v2.1.0-alpha --draft=false` 公开。

### R9 · M3 播放器交互轮（2026-11-12）

> 3.0 路线图（`docs/EMOPLAY-3.0-ROADMAP.md`）M3 阶段的第一批施工。上一轮
> R8（`3dcfb6a`，2026-11-11）为纯文档轮（3.0 路线图 / 跨平台验证矩阵 /
> fork 治理三件套），无用户可感知变化，故不设独立小节。

#### Added

- **章节导航**（`f2b7754`）：读取 mpv `chapter-list` / `chapter` 属性
  （fork 经 `readNativeString` 回读，JSON 形态逐条实测，非该形态降级为
  空表不崩；考证注释随行 `lib/mpv/config/mpv_player_properties.dart:37`），
  底板章节面板（Kazumi 同款自适应面板，当前章高亮，无章节文件优雅隐藏）
  与 Page Up / Page Down 跳章快捷键（出货 libmpv 内嵌默认 input.conf 的
  同位置建议绑定显式化）。M3-T2 验收面的进度条章节刻度 / hover 章节标题 /
  中键跳章未做（见 `docs/releases/RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md`
  §五与 `docs/reports/WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md` §5）。
- **字幕管理**（`a8cb844`）：字幕轨道切换面板（Kazumi 同款底板面板）、
  外挂字幕加载（srt/ass/ssa/vtt/sub）、关闭字幕、字幕延迟 ±0.5s 步进
  （±0.5 重复累加的二进制小数漂移以一位小数舍入兜住，HUD 显示
  `+0.5s` / `0.0s` 形态）。选轨真相源是 mpv `sid` 属性：fork 的
  `Player.state.track.subtitle` 在裸 `sub-add` 后保持 stale（fork 上实测
  探针，`lib/pages/player/controller/player_subtitles_controller.dart:13`
  头注释记录）。键位 C / V 承接 ±（mpv z/Z 双键惯例不可用：本表按
  keyLabel 分发不区分 Shift，且 Z 被 Kazumi 倍速减占用；快捷键设置页新增
  「字幕」分组）。
- **A-B 循环与逐帧步进**（`2e5d73d`）：A-B 循环三态（设 A → 设 B →
  清除），B 点 ≤ A 点在客户端拒绝（mpv 留为未定义的守卫）；键位 L 沿
  mpv 内置 `ab-loop` 惯例（1.x 实际行为：该键经 Main.qml 未消费按键转发
  落到 mpv 内置绑定，本条在 Flutter 层显式化）。逐帧步进
  `frame-step` / `frame-back-step`（fork 命令表 strings 实测可用；
  frame-back-step 需 mpv ≥0.38，fork 降级须复检），键位 `.` / `,`，
  底部控制条暂停态显示上一帧 / 下一帧按钮（mpv OSC 惯例位，播放态
  不占位）。

#### Fixed

- **library_store_test 扫描静止态竞态**（`a8cb844`）：链式扫描管线
  （worker 握手慢时第一趟已覆盖全部文件夹、第二趟随后串接）排干前断言
  静止态偶发红灯；`test/library_store_test.dart:364` 补
  `pumpUntil(() => !store.isScanning)` 排水等待，产品代码零改动。

#### 验证

- `flutter analyze` 0 告警（`No issues found! (ran in 5.7s)`）；
  `flutter test` 44 文件 **411 通过 + 1 平台条件跳过**全绿（2026-11-12
  文档窗口两遍实测同数；上轮 37 文件 / 355 + 1，+7 文件 / +56 用例：
  章节 14+2、字幕 7+2、A-B 循环 26、逐帧 live 3、键位守护 2，逐文件
  实测计数与全量差值交叉核对一致）。1 skip = Windows-only 探针
  （`mpv_profile_scanner_test.dart:217`，按设计跳过）。7 条真 libmpv
  live 用例真跑（逐帧 live 17s）；/tmp/perf 夹具缺失时基准段与音频探针
  按 skip-打印降级通过（计数不变）。CI 本窗口不可测：`gh run list` EOF
  （api.github.com 不可达）；R9 三提交未推送（本地 ahead 3），推送后
  预期签名 **411 passed / 1 skipped**。

### R7 · 性能实测与设置收尾轮（2026-11-11）

#### Added

- **设置 → 通用「恢复默认设置」**（`d971af0`）：1.x
  `SettingsService::restoreDefaults` 的 UI 槽位落地，EmoDialog 危险样式
  确认后 quality / behavior / music 三分区回 1.x schema 默认
  （`lib/settings/emoplay_settings.dart:500`）；媒体库、观看历史与 mpv
  配置导入决策不动（导入决策的重置在 mpv 配置页自有 tile）；恢复后把
  新值推进会话控制器（`reloadFromSettings`）与
  `LibraryStore.setScanOptions`，画质 / 音频 / 媒体库页即时刷新。
  1.x 对账清单最后一项（`restoreDefaultsKeepsMediaAndHistory`）消账：
  2.0 语义测试（`test/settings_service_semantics_test.dart:139`）seed
  全部非默认值后断言真实 library.json / history.json 逐字节不变。
- **性能基准资产**（`87b3760`）：`test/perf_scan_benchmark_test.dart`
  （4 段，skip-if-fixture-missing，夹具缺失自动降级通过）+
  `tools/gen_perf_fixture.sh`（2000 文件夹具生成器，幂等，只进 /tmp）。
  2000 条目量级实测：worker isolate 热扫 125ms（16000 files/s）、进度
  回调 63 次（32 步长节流）、library.json 装载 1.7-2.2ms（远低于 100ms
  阻塞阈值，判定不改代码）、缩略图串行链 77-81ms/作业、并发重叠 0。
  全部为容器 Isolate 计时（非宿主基线），数字全录
  `docs/reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md`。
- **tag 发布 draft 制**（`0a3436c`）：release.yaml `Create release` 步
  `draft: true`，alpha / 误打 tag 的产物先落草稿、不占公开 Latest 位
  （draft 不能被设为 Latest）；人工核对后
  `gh release edit <tag> --draft=false` 公开，流程新增
  `docs/guides/BUILD_GUIDE.md` §四。主要失效模式：忘 publish。

#### Changed

- **通用设置页 i18n 第三页**（`d971af0`）：页签壳（R3）、音频设置（R4）
  之后，通用设置页整体迁移 AppLocalizations，zh / en 双语（含恢复默认
  确认文案）；新增 `test/general_settings_l10n_test.dart` 5 用例
  headless 挂真实页面，锁双语渲染、确认对话框取消不动分区、确认后
  三分区复位且页面即时刷新。
- **deb control 注释口径考证**（`0a3436c`）：依赖清单注释里互相矛盾的
  库数（历史五口径 250/234/166/64/113 与原写「115」）改为审计 P2 实测
  口径并写明统计范围：直连 NEEDED 并集 63 soname（64→63 对应 R6 移除
  `screen_brightness_ohos`）、ldd 传递闭包 125 路径 = 9 内嵌 + 116 外部、
  3 个 dlopen-only 内嵌库从不进 ldd。注释级修复，无行为变化。

#### 验证

- `flutter analyze` 0 告警（`No issues found! (ran in 8.3s)`）；
  `flutter test` 37 文件 **355 通过 + 1 skipped** 全绿（2026-11-11 03:40
  CST 文档收网窗口实测，夹具在场基准段真跑；上轮 35 文件 / 345 + 1）。
  CI 本窗口不可测：`gh run list` EOF（03:41 CST，api.github.com 不可达）；
  `87b3760` / `d971af0` / `0a3436c` 三提交未推送，推送后预期签名
  **355 passed / 1 skipped**（CI 无 /tmp 夹具时基准段 skip 降级，计数不变）。

### R6 · 卫生与交付形态轮（2026-11-11）

#### Added

- **Linux AppImage 打磨**（`e1a2df0`）：`.github/scripts/package-appimage.sh`
  经 linuxdeploy 打包（amd64 实测 extract-and-run 冒烟通过；arm64 走
  linuxdeploy-aarch64，仅 CI 可验），release.yaml 挂 `*.AppImage` 资产；
  系统库（GTK/VA-API 等）按 deb `Depends` 同款策略不内嵌。README 增补
  AppImage 产物行与截图占位说明。
- **Kazumi 对齐守护测试** `test/kazumi_alignment_ui_test.dart`（3 用例，
  headless 挂载真实页面）：关于页许可证 tile 指向本项目 LICENSE（曾误指
  Kazumi 仓库）；首页 / 媒体库空态按钮走 Kazumi `StateActionButton` idiom
  （64×48 药丸样式断言）；`url_launcher_platform_interface` 以
  dev_dependency `^2.3.2` 作启动捕获测试缝（`pubspec.yaml:69`）。

#### Changed

- **空态按钮对齐 Kazumi idiom**：首页「选择媒体文件」、播放页
  「打开文件/文件夹/URL/媒体库」、媒体库空态按钮从裸 `FilledButton` 换成
  已平移的 `StateActionButton(.tonal)`（`lib/bean/widget/state_presentation.dart`
  与 Kazumi 逐字节一致，此前只在错误页使用）；仅样式层，回调不动。
- **插件页徽章与次要文案主题化**：「已定制」徽章从硬编码深棕
  （`Color(0xFF5a3d1e)`，两个主题下前景不可读）改为 `errorContainer` 容器对；
  模式徽章补 `onSecondary/onTertiaryContainer` 前景；「本地定制永不覆盖」
  说明与「暂无在线条目」提示改为 `bodySmall + onSurfaceVariant` 弱化
  （Kazumi 次要文案 idiom）。
- **依赖收敛与死配置清理**（`988122f`）：三处 `any` 约束钉上确切版本
  （synchronized `^3.6.1+1` / material_color_utilities `^0.13.0` /
  path `^1.9.1`，审计 P2「any×3」）；`analysis_options.yaml` 删掉
  `lib/bbcode/generated/**` 与 `web/**` 两条指向已不存在路径的死排除。

#### Removed

- **web/ Flutter 模板目录**（`988122f`）：`index.html` / `manifest.json` /
  favicon / 4 张 icon（111 行 + 5 图）整体删除，理由：目标平台只有桌面与
  移动，不构建 web（审计 P2）；`.metadata` 同步去掉 web 平台登记。
- **`screen_brightness_ohos` 依赖**（`988122f`）：lib/ 零直接引用
  （审计 P2「依赖必要性存疑」项；`screen_brightness_android/ios/
  platform_interface` 保留在用）。

#### 验证

- `flutter analyze` 0 告警（`No issues found! (ran in 5.3s)`）；
  `flutter test` 35 文件 **345 通过 + 1 skipped** 全绿（1 skip 维持：
  Windows-only probe）。2026-11-11 02:21 CST 前后文档收网窗口独立复测，
  与施工轮 HANDOVER 数字一致（上轮 34 文件 / 342 + 1）。Linux debug 构建
  与 Android `assembleDebug` 本轮未重跑（R6 无原生构建面改动）。
- AppImage amd64 产物实测：仓库根 `EmoPlay_linux_v2.0.0-alpha_amd64.AppImage`
  35,584,504 字节、ELF static-pie（`file` 实测），runtime `--appimage-help`
  应答正常（exit 0），`.gitignore:62 *.AppImage` 覆盖不入侵仓库；
  extract-and-run 冒烟由施工轮完成（`.github/scripts/package-appimage.sh`
  头注释）。CI 结论本窗口不可测：`gh run list` EOF（02:21 CST，
  api.github.com 不可达）；`d446bb8` / `8ed84c4` / `1dc5d14` / `988122f` /
  `e1a2df0` / `b0e1a06` 六个提交未推送，推送后预期签名
  **345 passed / 1 skipped**。

### R5 · 面板观感轮（2026-11-10）

#### Fixed

- **播放中快捷键全部失效**：早期键盘处理器把「是否处理」门在 primaryFocus
  位于面板自建 `keyboardFocus` 内，而没有任何交互会让它成为 primaryFocus，
  条件永假。现改为「当前路由 isCurrent + 焦点不在任何 EditableText」
  （PiliPlus player_focus 语义，`player_keyboard_shortcuts.dart`）。
- **播放页导航浮层残留**：壳层 `menu.dart` 在 Observer builder 内用 `&&`
  短路读状态，observable 未被读取、Observer 从未订阅，导航条 / rail 该
  隐藏时不隐藏。现 observable 无条件读取；`PlayerPageController` 新增
  `pageCurrent`（`ModalRoute.isCurrent` 驱动），全出血条件 = 播放页
  isCurrent 且有活动媒体，页签高亮随路由状态派生。
- **CJK 落楷体（LXGW ZhenKai）**：M1 剥离时删除内置字体且主题未设
  fontFamily，fontconfig 在部分 Linux 环境把中文 dump 到楷体风字体。
  两层修复：恢复 Kazumi 的 MiSans-Regular（`assets/fonts/`，8,122,324
  字节）+ 按 Kazumi useSystemFont 设计端到端落地（见下）。

#### Added

- **设置 → 主题「使用系统字体」开关**（默认开，`useSystemFont`）：关闭后
  切换到内置 MiSans（Kazumi 同款）；两条路径都显式携带 CJK 兜底
  （Noto Sans CJK SC / Noto Sans SC / sans-serif），fontFamily 置空也
  不再信任 fontconfig 猜字体；静态主题切换时重发射 setTheme（否则非
  动态配色下开关不生效）。SPEC §1 字体行同步。
- **音频诊断探针** `test/audio_probe_test.dart`：针对「无声」报告，fixture
  存在才真跑（runner 上缺失即早退通过）；双趟探测 default ao 与 pinned
  ao=pulse。本轮实测 pinned 趟 `AO: [pulse] 44100Hz stereo 2ch float`。

#### Changed

- **播放面板按 Kazumi@`7265274` 逐槽位重组**（`player_item_panel.dart`
  单文件，402 插入 / 485 删除）：取代上轮「手机 6 键传输行 + 底部更多
  面板」的 PiliPlus 式组合，手机与桌面共用一套槽位（底条 = 播放/暂停、
  下一集、进度+时间、全屏；宽控件进顶部「更多」菜单，compact 子集 =
  视频比例 / 倍速 / 超分辨率）；弹幕与 Syncplay 槽位有意缺席；渐变遮罩
  与安全区 insets 保留；播放 tick 只重建进度条与时间标签。
- **发布矩阵九个 job 补齐 timeout-minutes**（pr linux-ci 20 分钟；release
  test / analyze 15、Android / Linux amd64 / arm64 40、Windows / macOS
  45、Release job 15）。
- **Windows 版本单一来源恢复**：release.yaml Windows job 前置
  `choco install yq`，flutter-action 恢复 `flutter-version-file:
  pubspec.yaml`（取代 R4 钉死 `flutter-version: '3.47.9'` 的权宜）。

#### 验证

- `flutter analyze` 0 告警；`flutter test` 34 文件 342 用例全绿（1 skip
  维持：Windows-only probe）；`flutter build linux --debug` 通过；ldd
  审计 0 缺失。Android assembleDebug 本轮未重跑（无 Android 原生改动）。
- CI 结论本窗口不可测：`gh run list` 两次连接 EOF（api.github.com 不可达）；
  `d446bb8` / `8ed84c4` 未推送，推送后预期签名 342 passed / 1 skipped。

### R5 · 移动端播放修复轮（2026-11-10）

#### Fixed

- **手机横屏播放左侧出现选项栏**：根因是壳层 `ScaffoldMenu` 在横屏切
  NavigationRail，而播放页是五页签之一，横屏播放时 rail 常驻视频左侧。
  现在全屏播放与手机横屏播放中时壳层切换为全出血（无导航条 / rail，
  黑底 edge-to-edge，`menu.dart`）；竖屏保留 NavigationBar，音频播放时
  仍可切页签。
- **手机全屏按钮无效**：`PlayerPageController.toggleFullscreen` 原先只调
  window_manager（桌面 API，安卓上空操作）。已拆平台分支：手机走
  `DisplayModeService`（旋转锁定 landscape + 原生 `setSystemBarsHidden`
  沉浸式；该 service 与 MainActivity 通道此前已实现但从未接线），桌面保持
  window_manager。
- **状态栏与播放控制重合**：`PlayerItemPanel` 原先完全没有安全区处理。
  现在非全屏时顶栏垫 `viewPadding.top`（状态栏）、底栏垫
  `viewPadding.bottom`（手势条），全屏（沉浸式）时归零；整面 0.35 黑
  替换为 PiliPlus 式上下渐变遮罩。
- **竖屏底部按钮行溢出**：手机传输行精简为 6 个紧凑按钮（播放 / 跳过片头 /
  倍速 / 截图 / 更多 / 全屏），超分辨率、视频详情、定时关闭、锁定、画中画、
  加载字幕移入「更多」底部面板；桌面保持全量内联。
- **锁定控制无解锁入口**：锁定按钮改为带状态切换（lock/lock_open），
  「更多」面板同步。
- `PlayerItem.dispose` 补充兜底：路由被绕过拆除（页签快捷键等）时手机不再
  残留沉浸式与横屏锁定。

#### Added

- **手机旋转自动全屏**（PiliPlus 行为，`PlayerItem._syncOrientationFullscreen`）：
  播放中物理旋转进入横屏即沉浸式全屏，转回竖屏自动退出；PiP 与锁定面板时
  跳过，与手动全屏互为幂等不回环。
- **手机本地媒体自动扫描**（`lib/services/platform/mobile_media_scanner.dart`）：
  走既有 `download_directory` 通道申请「所有文件访问」（manifest 已声明
  MANAGE_EXTERNAL_STORAGE，新增 `hasStorageAccess` 只查不弹页）；
  `Isolate.run` 内枚举 `/storage` 各卷，探测标准媒体目录（Movies/DCIM/
  Download/Music 等 10 项）+ 一级目录全扫（剔除 Android/data/obb），有媒体
  的目录按标准目录优先、数量降序返回并加入媒体库（`addDirectory` 链式扫描）。
  入口：媒体库页「扫描手机媒体」按钮 + 空态 CTA + 首次进库自动触发一次
  （仅权限已授予时，绝不自动弹系统设置页；`mobileAutoScanDone` 一次性旗标）；
  播放页空态新增「媒体库」跳转（手机）。

#### Changed

- 播放面板视觉：上下渐变遮罩、紧凑图标按钮（40px 约束）、进度条与音量条
  细轨化（trackHeight 3 / thumb 6）。
- 首页：历史行改缩略图卡片（16:9 缩略图帧 + 进度条 + 圆角悬停卡，缩略图
  复用 ThumbnailService）；不小于 720px 宽度时快捷动作与标题同行。
- 媒体库：搜索框改胶囊填充样式；网格卡片悬停高亮描边。
- Android 构建接入中国镜像（本机 `dl.google.com` / `storage.googleapis.com`
  不可达）：settings.gradle / build.gradle 增加 `storage.flutter-io.cn`
  （download.flutter.io 镜像）、腾讯云与阿里云 maven 前置，
  google()/mavenCentral() 保留兜底。

#### 验证

- `flutter analyze` 0 告警；`flutter test` 341 用例全绿（1 skip 维持）；
  `flutter build linux --debug` 通过；`./gradlew assembleDebug` 通过
  （`build/app/outputs/flutter-apk/app-debug.apk`）。模拟器视觉回归未跑
  （本机无 emulator 系统镜像且 dl.google.com 不可达，装机受阻）。

## [2.0.0-alpha] - 2026-11-10（已发布）

迁移工程 M1-M8 全部里程碑产物：Kazumi 骨架导入并剥离番剧业务，1.x 行为
语义逐条平移，数据 schema 与 1.x 逐字段一致。2026-11-10 08:13 CST 以 tag
`v2.0.0-alpha` 触发全平台发布矩阵并公开 GitHub Release（9 资产：Linux
amd64/arm64 的 deb 与 tar.gz、Android 三 ABI APK、Windows/macOS zip；
产物对应提交 `bd36f70`，未含其后 R4 的测试与 i18n 提交）。

### Added

- **骨架（M1）**：Kazumi@`7265274`（GPL-3.0）工作树导入，剥离番剧采集 /
  Bangumi API / XPath 规则引擎 / 弹幕 / Syncplay / 下载；五页签导航
  （首页 / 媒体库 / 播放 / 插件 / 设置，竖屏 NavigationBar、横屏
  NavigationRail、`Ctrl+1..5` 直达）；应用名 / applicationId / 图标 /
  字体全部 EmoPlay 化（占位图标，系统默认字体，无 Kazumi logo、无 Mi Sans）。
- **播放器（M2）**：media-kit（Predidit fork，锁 commit `83b7ca6`）接入；
  音轨/字幕面板、外挂字幕、播放列表、倍速、手势与快捷键、截图面板、
  Android PiP（弹幕按钮随弹幕业务一并移除）、DLNA 投屏、Linux 外部播放器
  接管；PiliPlus 交互小件摘取改写。
- **本地媒体（M3）**：文件/目录打开、拖拽导入、媒体分类器（视频/音频/字幕
  扩展名表）、扫描 isolate（skipHidden、maxDepth 剪枝、不跟随符号链接、
  进度回调与取消）。
- **媒体库与历史（M4）**：`library.json` / `history.json` 落盘（SPEC §7
  schema，与 1.x 逐字段一致；路径去重置顶、上限 50、5s 心跳刷新、暂停不写
  盘、重扫保留 lastPlayed）；ffmpeg 两段式缩略图（sha1 缓存键、30s 超时、
  无 ffmpeg 降级类型图标）；首页最近播放 / 继续观看 / 媒体统计。
- **mpv 兼容（M5）**：mpv.conf / input.conf 解析器；首启导入向导（完整 /
  选择性 / 独立 / 跳过，可重跑与重置决策）；强制 / 剥离 / 重定向三张规则
  表（`[profile]` 段只报告不应用；screenshot-template 含 `~~` 整条丢弃）；
  watch_later / screenshots / shader_cache / icc_cache / demuxer_cache 写
  路径全部重定向到应用数据目录，**绝不写用户 mpv 目录**；`load-scripts=no`
  + 显式 scripts 选项表；诊断页运行时审计当前生效选项。
- **画质引擎（M6）**：Anime4K 链序表照抄 1.x（900/1440p 分组，Mode A / A+A /
  C 多文件精确序列，HDR/HFR 避让，部分安装优雅降级）；SSimSuperRes 真人
  高档；HDR tone-mapping 档位；插值/补帧 VapourSynth 六预设 + 掉帧 ≥2/s
  会话级自动降档 + 探测失败持久化 off；ICC profile 不可读时持久化 off 并
  恢复启动快照。
- **插件 / 设置 / 音乐（M7）**：PluginManager 三段式（planOperation → 确认
  → 执行），check 模式永不覆盖、replace 前 `git status --porcelain` 防线，
  `.backup-<name>` 备份 + 原子 swap；内置 6 插件 + 在线源清单；设置中心
  11 类（常规 / 播放 / 视频与画质 / 音频 / mpv 配置 / 着色器管理 / 外观 /
  快捷键 / 存储 / 诊断 / 关于）；10 段均衡器（`equalizer=f=…:t=q:w=1.4`
  链）+ 预设 + .lrc 歌词。
- **交付（M8）**：双语 README、NOTICE.md（Kazumi / PiliPlus / Anime4K /
  1.x MIT→GPL-3.0 重授权声明）；SPEC §7 数据兼容测试
  （`test/data_compat_spec7_test.dart`，1.x 样例 JSON 喂入两个 store）；
  CI 改造 - push/PR 仅单 job Linux analyze+test+build，全平台打包矩阵
  （Windows/macOS/Android/Linux amd64+arm64）仅 `v*` tag 触发，删除全部
  dart-define 密钥注入与第三方签名服务，iOS 构建保留注释待接入。

- **对账收网（R1）**：1.x `src/update/UpdateChecker.cpp` 平移落地
  （`lib/services/update_checker.dart`，纯函数与考证注释逐行直译；启动 3s 后
  至多一次 GET，端点 `repos/emoeem/emoplay/releases/latest`，结果只报告、
  永不下载安装、失败完全静默；设置页确认新版后给出发布页入口）；画质 /
  插值控制器补齐 1.x「每次 apply 实时重读持久化设置」语义
  （`interpolation_controller.dart:172`、`quality_controller.dart:375`）；
  测试对账：26 个 1.x C++ 测试文件逐一对账（`quality_engine_test.dart` 等补齐，
  见 `docs/reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md` §3.1）。

- **转绿补账（R2）**：健壮性边界测试 `test/robustness_test.dart`（损坏媒体
  文件 / 非媒体目录 / 空库 / 权限拒绝目录，11 用例，全对真实文件系统、无
  GUI）；`test_settings_service.cpp` 两槽位语义补齐
  （`test/settings_service_semantics_test.dart`：扫描选项经真实 worker
  isolate 生效于下一次扫描、保存失败以 `save()` 返回 false + toast 上报而非
  静默丢失）；i18n 骨架（`l10n.yaml` + `lib/l10n/app_zh.arb`（zh 模板，键值
  取自真实 UI 字符串并带出处注释）/ `app_en.arb`（结构预留）+ 生成的
  `AppLocalizations` 类（非 synthetic-package，生成文件提交）+
  `app_widget.dart` 装配；默认语言仍 zh-Hans-CN，页面字符串迁移为后续轮次）；
  迁移路线图 `docs/UPGRADE_ROADMAP_2026-11-10.md`（M0-M8 ✅+提交哈希、
  R1/R2 收尾轮次、未做项 ☐ 清单、验收标准与贯穿约定）。

- **红灯清零（R3）**：Linux deb `Depends` 从 2 项补到 17 项 - GTK 运行库
  显式钉入（`libgtk-3-0t64`），不再依赖 tray 包侧链隐式捎带，音频输出 /
  硬解 / GL 视频输出运行库齐备（`7052260`；覆盖经 `apt-cache depends
  --recurse` 审计：bundle ldd 闭包的 104 个提供包全部落在 17 包递归闭包
  251 包内，差集为空）；页签壳成为第一个接入 i18n 的页面 - 五个页签标签
  经 `menuTabLabels()` 单一来源分发（竖屏 NavigationBar 与横屏
  NavigationRail 同源，文案不可能漂移）、「再按一次退出应用」toast 换
  `AppLocalizations`，迁移链由 `test/menu_l10n_test.dart` 3 用例端到端
  锁定，默认语言仍 zh-Hans-CN、中文界面零变化（`c943414`）；媒体库响应性
  守卫 `test/performance_guards_test.dart` 3 用例（取消扫描毫秒级停且部分
  结果保留、进度按节流步触发不逐文件刷屏、flock 实证缩略图至多一个 ffmpeg
  子进程，与 1.x 单 worker 线程形状一致；isolate 分片多开经评估不采，
  理由记录在测试文件头注释）。

- **首绿发布（R4）**：CI 首绿达成（run 42718530280，`332 tests passed,
  1 skipped`，与 R3 预期签名一致）后，`v2.0.0-alpha` tag 三次演练打穿真实
  发布链并公开 GitHub Release（9 资产，见 Fixed 三盏红灯与死 include 的
  修复）；1.x `tests/test_mpv_engine.cpp` 的 apply() 半边逐用例平移 - 
  5 条真开 libmpv 的 live 用例进 `test/mpv_player_properties_test.dart`
  （propertyRoundTripDispatch / applyPresetLandsOnLiveCore /
  observedPropertySignalsAvailableAndUnavailable /
  unavailableIdleCoreReadsClearedValues / commandErrorSurfacesThroughLogStream，
  `initializeSmoke` 吸收进各 live 用例、`doubleInitializeRejected` 因 2.0
  无引擎单例不移植，对账表在测试文件头注释）（`2598bc8`）；设置页音频类
  接入 i18n（第二页）：app bar / 分区与瓦片标题 / 均衡器提示实时翻转 /
  预设单一来源标签表 `audioEqualizerPresetLabels` / 十个频段行，默认语言
  仍 zh-Hans-CN、中文界面零变化，迁移链由 `test/audio_settings_l10n_test.dart`
  4 用例（zh+en，真实页面挂载）锁定（`2c6bf06`）；中英 README 增「发布
  产物 / Release artifacts」节（平台×产物表、deb 直装建议、未签名提示）
  与 Linux 源码构建的运行期依赖说明（`2c6bf06`）。

### Fixed

- CI 自建仓起零 run：`.github/workflows/pr.yaml` 触发分支写成 `master` 而仓库
  分支是 `main`，每次推送被静默跳过（`916c2d6` 改为 `main`）。
- CI 首跑红灯（run 42706655830）：`ubuntu-latest` 缺 VA/VDPAU 运行库，
  media_kit 捆绑的 `libmpv.so.2` 加载失败（`libva-drm.so.2: cannot open
  shared object file`），两条真开 libmpv 核心的均衡器用例失败；`3379d7a`
  将原生依赖安装步挪到 `flutter test` 之前并补装 `libva2 libva-drm2
  libva-x11-2 libva-wayland2 libvdpau1`（`release.yaml` 同步）。
- CI 第二跑红灯（run 42712702494）：同一批用例报 `libpulse.so.0: cannot
  open shared object file` - dlopen 每次只报第一个缺失依赖，R2 补的
  VA/VDPAU 只是直系依赖的第一层；`7debc83` 按 `readelf -d` 实测
  `libmpv.so.2` 全部直系 NEEDED 后向 pr.yaml / release.yaml 一次补装
  14 个运行库（`libpulse0 libxv1 libegl1 libgbm1 libdrm2 libunwind8
  liblcms2-2 libarchive13t64 libasound2t64 libdbus-1-3 libsndfile1
  libmpg123-0t64 libopus0 libogg0`；第二层编解码库交给发行版依赖图，
  不按随发行版变名的 soname 钉死），并把 pr.yaml 步序改为 构建 →
  `ldd libmpv.so.2 | grep 'not found'` 审计（任一缺失即红灯并列全清单）→
  测试 - 依赖缺口从此一次列全，不再逐轮烧 CI 分钟数。
- `v2.0.0-alpha` 发布演练第一跑三平台红灯（run 42720144705，`b9b3d2c` 一次
  修复，第二跑验证）：macOS 打包 `ditto: Cannot get the real path for
  source '.../EmoPlay.app'` - M1 品牌化改名漏了
  `macos/Runner.xcodeproj/project.pbxproj`，构建产物仍是 `Kazumi.app`
  （product 引用 / RunnerTests bundle id / TEST_HOST 全部改 EmoPlay）；
  Windows 装环境 `yq not found` - flutter-action 的
  `flutter-version-file` 解析在 windows-latest 需要 yq 且未预装（改钉
  `flutter-version: '3.47.9'`，与 pubspec 同步手改）；Linux arm64 构建
  `Could NOT find ALSA` - 自建 action 冷缓存走源码构建时装 Flutter 缺
  ALSA 头文件（apt 清单补 `libasound2-dev` +
  `libayatana-appindicator3-dev`）。
- `v2.0.0-alpha` 发布演练第二跑 Windows 编译红灯（run 42722139024）：
  `windows/runner/main.cpp` 残留已随 STRIP-LIST 剥离的 app_links 插件
  include（`error C1083: Cannot open include file:
  'app_links/app_links_plugin_c_api.h'`，头文件永远无法解析）；`bd36f70`
  删除 include 与 `SendAppLink()` 调用（第二实例 `emoplay://` 唤起保留，
  URL 内容转发为待做功能），第三跑 run 42724607274 全绿并完成发布。

### Changed

- 许可：整体 MIT（1.x）→ **GPL-3.0**；Kazumi / PiliPlus 版权声明保留，
  Anime4K 随 `assets/shaders/LICENSE`（MIT）保留，1.x 代码重授权声明见
  `NOTICE.md`。
- 语言：Dart/Flutter 3.47.9 替代 C++20/Qt6；状态管理 MobX（build_runner
  生成），路由 flutter_modular。

### 兼容性

- 1.x 的 `history.json` / `library.json` / `settings.json` 放入应用数据
  目录即可直接读取（`test/data_compat_spec7_test.dart` 锁定，含 `lastPlayed`
  为 null 的外来写入者情形）。
- 插件 state.json / manager.json 清单格式与 1.x 一致，在线源可继续使用。

### 已知限制

- iOS 构建未进入发布矩阵（workflow 留注释，待签名方案）。
- Android APK 发布为未签名产物（待仓库配置签名密钥后接入）。
- Windows / macOS 产物未经实体机验证；无 Authenticode / 公证。
