# EmoPlay 3.0 路线图（M3-M8 施工件 · 文件级任务书）

| 项       | 值 |
| -------- | --- |
| 状态     | 生效中（提案定稿，施工未开始；每完成一项任务回填 ☐→✅+提交哈希） |
| 日期     | 2026-11-11（建立） |
| 适用版本 | git `bdad604`（2.0.0-alpha+2000000，`pubspec.yaml:4`；`87b3760`/`d971af0`/`0a3436c`/`bdad604` 四提交待推送） |
| 相关     | [SPEC.md](SPEC.md)、[UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)（2.0 权威路线图，本文不取代它）、[CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md)、[FORK-GOVERNANCE.md](FORK-GOVERNANCE.md)、[HANDOVER.md](HANDOVER.md) |

## 一、结论先行

本文是 EmoPlay 3.0 的施工路线图，覆盖 M3-M8 六个阶段（M0-M2 为规划阶段：四路
参考项目拆解、现状盘点、方向定调，其产出已并入本文 §二-§四）。产品方向已定：
**跨平台本地媒体中心**，Kazumi 框架 + PiliPlus 交互 + media_kit 内核 +
EmoPlay mpv 生态为差异化资产；范围纪律 = 本地优先，不上服务器/在线业务。

基线（2026-11-11 本文建立时实测，非转抄）：

| 门禁 | 结果 | 来源 |
| --- | --- | --- |
| 版本 | 2.0.0-alpha+2000000，HEAD `bdad604`，领先 origin/main 4 提交 | `git status -sb`、`git log origin/main..HEAD --oneline`（2026-11-11 实测） |
| 静态检查 | `No issues found! (ran in 6.8s)`（0 告警） | `source /opt/emoplay-env.sh && flutter analyze`（2026-11-11 实测） |
| 自动化测试 | **37 文件 / 355 通过 + 1 条件跳过全绿**（`00:19 +355 ~1: All tests passed!`） | `flutter test`（2026-11-11 实测；`ls test/*.dart | wc -l` = 37） |
| 代码规模 | lib/ 175 个 Dart 源文件（不含 8 个 `.g.dart`），共 33,703 行 | `find lib -name '*.dart' ! -name '*.g.dart' | xargs wc -l`（2026-11-11 实测） |

3.0 的六阶段主线：**M3 播放器交互**（帧预览/章节/鼠标映射/mpv 高级选项，把
Haruna、IINA、mpv.net 的成熟交互语义移植进来，这是 EmoPlay「mpv 生态差异化」
的主战场）→ **M4 媒体库升级**（统一数据模型落地 + 目录树/网格观感）→
**M5 音乐**（队列/循环/歌词的完整音乐模式）→ **M6 插件安全**（清单校验与
操作审计硬化）→ **M7 诊断/测试**（播放链路集成测试 + 运行时诊断探针）→
**M8 发布工程**（签名/语义/i18n 收尾，配合
[CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md)
的实机验证矩阵与 [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md) 的内核 fork 治理）。

**输入缺口声明（坏消息）**：本轮规划收到的「四路拆解」JSON 在 IINA/mpv.net
一路的第 5 模块中途截断，且 Kazumi、PiliPlus 两路拆解条目未送达。本文的处置：
1) IINA/mpv.net 第 5 模块（播放设置侧栏 + 视频均衡器）已用 `/tmp/iina-ref`
本地源码逐行核实补全；2) Kazumi/PiliPlus 的引用全部改为本文写者对本地只读
克隆（`/home/emo/code/Kazumi`、`/home/emo/code/PiliPlus`）的定向抽查，行号
均为本文实测。拆解原 JSON 若后续补齐，应以本文映射表为准做增量合并。

## 二、现状盘点：保留 / 复用 / 重构 / 缺失（文件级）

结论：**九条不变量（SPEC §4）与三份 JSON schema 的平移成果全部保留不动**；
重构集中在播放页两处大文件与音乐/诊断面；缺失项全部归入 M3-M8 任务。以下
行号为 2026-11-11 实测（git `bdad604` 工作树）。

### 2.1 保留（平移资产，施工时绝不改语义）

| 文件 | 职责 | 保留理由 |
| --- | --- | --- |
| `lib/media/history_store.dart`（342 行）、`lib/media/library_store.dart`（805 行）、`lib/services/storage/settings_keys.dart`（366 行） | history.json / library.json / settings.json 落盘 | SPEC §7 逐字段一致是发布承诺，字段名一个不改（PORT-MAP 头部铁律）；`test/data_compat_spec7_test.dart` 护航 |
| `lib/mpv/compat/mpv_import_rules.dart`、`lib/mpv/compat/compat_controller.dart`、`lib/mpv/compat/mpv_profile_scanner.dart`（370 行） | 导入三张表 + 写路径重定向 | 不变量 1/2/3（SPEC §4） |
| `lib/mpv/config/mpv_player_properties.dart`（147 行） | media_kit 属性预设 | 文件头 1-35 行嵌着 fork 行为实测考证（post-init setProperty 惯性、libmpv 0.41 探针），M3/M7 扩属性时**必须随行平移该注释** |
| `lib/pages/player/controller/pending_resume_seek.dart` | resume 挂起一次性消费状态机 | 不变量 4；7 用例护航，M4 数据模型不触碰其语义 |
| `lib/quality/quality_profile_engine.dart`（420 行）、`lib/quality/quality_controller.dart`（565 行）等 8 文件 | Anime4K 链序 / 掉帧降档 / ICC / 插值 | 不变量 5/8 |
| `lib/plugins/plugin_manager.dart`（933 行） | 三段式 + porcelain 守卫 | 不变量 6；M6 在其外层加固而非改内层 |
| `lib/media/thumbnail_service.dart`（421 行） | sha1 键 + 两段 ffmpeg 链 | 不变量 7；M4 缩略图升级复用其缓存键 |
| `lib/music/equalizer.dart` | 10 段 EQ 链（`equalizer=f=…:t=q:w=1.4:g=…`） | 不变量 9，与 1.x 逐字符一致 |
| `lib/utils/async_*.dart` 4 文件 | 限流/串行队列/单飞/会话 | M3/M4 新功能复用的并发基元 |

### 2.2 复用（已具备，新功能直接建在其上）

| 文件 | 复用点 |
| --- | --- |
| `lib/pages/player/player_progress_bar.dart:51`（`_preview` OverlayPortalController）、`:58`（`_previewFraction`） | 现有 hover 时间气泡（M2 交付），帧预览与章节刻度直接扩展这条管道 |
| `lib/pages/player/controller/player_seek_controller.dart`（173 行） | 挂起 seek/进度步长逻辑；章节跳转与预览 seek 走同一入口 |
| `lib/pages/player/player_item_panel.dart:569`（`_showPlaylistSheet`）、`:575`（playlist 取数） | 底板播放列表面板，M3 悬浮面板改造的落点 |
| `lib/pages/player/player_gesture_detector.dart:45-67`（Listener+GestureDetector，仅 seek/垂直拖动） | 手势入口，鼠标映射在其上加 tap/doubleTap/secondaryTap/滚轮分发 |
| `lib/pages/player/player_pointer_interaction.dart`（22 行） | 指针类型判定谓词，映射表的执行端 |
| `lib/pages/settings/keyboard_settings.dart:10`（`_ShortcutGroup`）、`:17`（分组表） | 快捷键只读页，input.conf 编辑器在同型页上升级 |
| `lib/mpv/compat/mpv_key_name.dart` + `test/mpv_key_name_test.dart` | 键名映射，按键录制窗与 input.conf 编解码共用 |
| `lib/mpv/config/mpv_config_parser.dart` + `test/mpv_config_parser_test.dart` | conf 解析，高级选项编辑器只补「注释保持往返 + 默认值 diff 写回」 |
| `lib/bean/widget/side_panel_transition.dart:3`（`SidePanelTransition`） | 侧栏容器，OSC 双形态/播放设置侧栏直接用 |
| `lib/pages/player/player_transport_bar.dart:17`（`PlayerTransportBar`） | 底部控制条，工具栏定制与悬浮形态的宿主 |
| `lib/pages/player/player_adjustment_hud.dart:5-6`（brightness/volume 枚举） | 调节 HUD，视频均衡器五滑块按同型扩展 |
| `lib/pages/player/video_details_sheet.dart:72-73`（TabController 2 页：状态/日志） | 详情弹层，章节页签或独立 sheet 的容器 |
| `lib/pages/library/library_page.dart:216-262`（search/typeFilter/sortMode 已在） | M4 目录树/网格观感在其上加，不换数据源 |
| `test/audio_probe_test.dart`（真 libmpv 探针先例，pinned ao=pulse 实测出声） | M7 播放链路集成测试的照抄模板 |
| `test/performance_guards_test.dart`（取消延迟/进度节流/缩略图串行） | M3/M4 新增性能守卫的挂点 |

### 2.3 重构（结构债，施工前清）

| 位置 | 问题 | 动作 | 依据 |
| --- | --- | --- | --- |
| `lib/pages/player/player_item.dart`（**1538 行**，审计时 1506） | 上帝类：PiP/键盘/HUD 定时/audio_service 绑定/全屏/菜单 8 职责簇 | M3-T0 按 AUDIT_FULL §一 P1 建议拆分（PiP→`player_pip.dart`、audio 绑定→`player_audio_binding.dart`、HUD→`player_adjustment_hud.dart` 已部分存在），355 用例护航。**已拆分（`c9245f8`，2026-11-12 实测 git `5fedee0` 工作树）**：`player_item.dart` **484 行**（<500 达标）；拆出 `player_pip.dart` 264、`player_audio_binding.dart` 83、`player_keyboard_shortcuts.dart` 526、`player_menu_binding.dart` 32、`player_item_gestures.dart` 302、`player_panel_hold.dart` 288、`player_progress_pipeline.dart` 164、`player_screenshot_actions.dart` 165、`player_screenshot_filmstrip.dart` 211、`player_super_resolution_prompt.dart` 120 行；`player_screenshot_sheet.dart` 1052→855 行 | audits/AUDIT_FULL_2026-11-10.md §一第 1 行 |
| `lib/pages/player/player_screenshot_sheet.dart`（1052 行） | 截图功能单文件过巨 | 随 player_item 拆分一并复审（同审计 §三） | 同上 |
| `lib/pages/player/controller/player_playback_controller.dart:443`（`setPlaylistMode(PlaylistMode.none)` 硬编码） | 循环模式不可达 | M5-T1 把 PlaylistMode 提升为设置项+面板项 | 本文 §五 M5 |
| `lib/mpv/diagnostics/diagnostics_info.dart:48-54` | 诊断字段全是静态路径（appVersion/dataDir/configDir/logDir），无运行时探针 | M7-T1 补 mpvVersion/renderBackend/ao 运行时读取 | SPEC §6 第 10 类要求「全部运行时读取」 |

### 2.4 缺失（对照参考项目的功能空位，编号即任务号）

- **帧预览**：进度条 hover 只有时间文本气泡（`player_progress_bar.dart:51,216`），
  无第二解码实例，Haruna 有（P0，M3-T1）。
- **章节**：`grep -ri 'chapter' lib/ -il` 零命中（2026-11-11 实测），chapter/
  chapter-list 属性全链缺失（P0，M3-T2）。
- **鼠标操作映射 / 自定义 mpv 命令**：无映射表、无按键→动作解析（P1，M3-T4）。
- **mpv 高级选项编辑器**（可搜索 conf 编辑 + 原始选项追加，注释保持往返）（P0，M3-T5/T6）。
- **input.conf 快捷键编辑器**（往返编解码 + 按键录制）（P0，M3-T6）。
- **OSC 双形态 / 工具栏定制 / 类型化 OSD / 视频均衡器侧栏**（P1，M3-T7/T8）。
- **媒体库目录树 / 收藏集 / 扩展元数据缓存**（M4-T2/T3/T4）。
- **音乐队列 / 循环模式 / 迷你条**（M5）。
- **插件清单完整性校验（sha256/签名）/ 操作审计落盘**（M6）。
- **播放链路集成测试 / 运行时诊断探针**（审计 §四明确缺口）（M7）。
- **签名 / prerelease 语义 / emoplay:// URL 转发 / i18n 余页**（2.0 路线图 §4.2 全部遗留）（M8）。

## 三、参考项目借鉴映射（四路拆解合并，按 M3-M8 归组）

结论：来源标注 `[拆解]` = 来自本轮工作流传入的拆解 JSON（Haruna/Celluloid 一路
完整；IINA/mpv.net 一路 1-4 模块完整）；`[补全]` = 本文写者对 `/tmp/iina-ref`、
`/tmp/mpvnet-ref` 本地源码实测补全（输入截断部分）；`[抽查]` = 本文写者对本地
只读克隆的定向读取。**不移植项**（拆解已判定，维持）：Qt/GTK/KDE 框架层、
QQuickImageProvider 缩略图管线、Celluloid input.conf 输入桥、Celluloid 停靠式
播放列表与 Haruna 多 tab 播放列表管理、thumbfast 独立进程（EmoPlay 用进程内
第二 Player 实例）、Celluloid 帧预览（该项目没有此功能）。

| # | 借鉴项 | 参考证据 | EmoPlay 落点 | 阶段/任务 |
| --- | --- | --- | --- | --- |
| 1 | 进度条帧预览（第二 libmpv 解码实例：vo=libmpv、mute/pause、关音轨字幕、hr-seek 跟随设置、position 异步写 + 消抖） | [拆解] Haruna `src/mpv/mpvpreview.cpp:21-38,53-58,65-71`；UI `HProgressBar.qml:48-61,144-170,226-252` | 新建 `lib/pages/player/controller/seek_preview_controller.dart`（第二个 media_kit Player，按 Haruna 属性集配置）；`player_progress_bar.dart` 气泡升级为帧图+章节标题；开关落 `lib/pages/settings/player_settings.dart` | M3-T1 (P0) |
| 2 | 章节导航（chapter/chapter-list 属性、titleAtPosition 上界二分、刻度 rowCount*20<宽 规则、中键跳章、Skip 过滤） | [拆解] Haruna `mpvitem.cpp:69-70,637-649`、`chaptersmodel.cpp:67-77`、`HProgressBar.qml:190-272,274-348`；Celluloid `celluloid-player.c:492-493` | `lib/mpv/config/mpv_player_properties.dart` 增属性读取；新建 `lib/pages/player/controller/chapters_model.dart` + `lib/pages/player/chapters_sheet.dart`；`player_progress_bar.dart` 刻度+中键 | M3-T2 (P0) |
| 3 | 播放列表悬浮面板（左右 edge、宽度记忆、边缘 50px 悬停展开、右键菜单/搜索过滤语义） | [拆解] Haruna `Playlist.qml:18-46,129-288`、`MpvVideo.qml:82-97`；Celluloid 右键菜单 `playlist-widget.c:623-648` | `player_item_panel.dart:569` 底板升级悬浮面板（`side_panel_transition.dart` 容器）；边缘判定复用 `player_gesture_detector.dart:39-43` isAtEdge；宽度记忆入 `settings_keys.dart`（新增 key，见 §四红线） | M3-T3 (P1) |
| 4 | 鼠标操作映射（十键位×修饰键→动作名；默认 Left→playPause、Left×2→fullscreen、Middle→mute、Wheel→volume、Forward/Back→seek±） | [拆解] Haruna `mouseactionsmodel.h:17-114`、`mousesettings.kcfg:13-42`、`MpvVideo.qml:71,100-157` | 新建 `lib/settings/mouse_action_settings.dart`（键位→动作名字典）；`player_gesture_detector.dart` 加 onTap/onDoubleTap/onSecondaryTap/滚轮分发；UI 新建 `lib/pages/settings/mouse_settings.dart`（同型 `keyboard_settings.dart:10`） | M3-T4 (P1) |
| 5 | 自定义 mpv 命令（命令串+OSD 消息+shortcut/action 类型+setOnStartup；分词→commandBlocking 等价） | [拆解] Haruna `customcommandsmodel.h:19-27`、`EditCustomCommand.qml:52-126`、`mpvitem.cpp:751-755` | 新建 `lib/mpv/config/custom_commands.dart`（分词+类型+启动注入，走 `mpv_player_properties.dart:131-146` apply 通道；运行时经 NativePlayer 命令直调）；UI 挂设置「mpv 配置」类 | M3-T4b (P1) |
| 6 | 快捷键编辑器（input.conf 往返编解码：tab 归一/修饰键规范化/menu:/! 语法/# 注释往返；编辑表+按键录制窗 VK→mpv 键名；只写偏离默认项，改写前备份） | [拆解] mpv.net `InputHelp.cs:317-445`、`InputConf.cs:27-113`、`InputWindow.xaml.cs:20-117`、`LearnWindow.xaml.cs:100-210` | 新建 `lib/mpv/compat/input_conf_codec.dart`（往返编解码，与 `mpv_key_name.dart` 对接）；`keyboard_settings.dart` 升级编辑+录制（Flutter `HardwareKeyboard` 捕获）；序列化走 CompatController 现有注入通道 | M3-T6 (P0) |
| 7 | mpv 高级选项编辑器（声明式元数据→分目录可搜索面板；conf 读注释保持/写仅偏离默认；改动实时 SetPropertyString 下发；类型化控件渲染） | [拆解] mpv.net `editor_conf.txt`、`ConfWindow.xaml.cs:23-472` | 新建 `lib/mpv/config/mpv_option_meta.dart`（精选选项元数据表）；`lib/pages/settings/mpv_settings.dart` 改元数据驱动；`mpv_config_parser.dart` 补注释保持往返 + 默认值 diff | M3-T5 (P0) |
| 8 | mpv 原始选项追加编辑器（option=value 行编辑、启动逐条下发打日志、用户显式项不被内部默认覆盖） | [拆解] IINA `SettingsPageAdvanced.swift:138-164`、`MPVController.swift:596-606,1835-1840` | 并入 M3-T5：`mpv_option_meta.dart` 增加 free-form 列表 UI；合并/冲突保护点在 `mpv_player_properties.dart:64-103`（compat options 已有「用户项后到先得」语义，补显式去重告警） | M3-T5b (P1) |
| 9 | 播放设置侧栏四 tab（layout/video/audio/sub）+ 视频均衡器五滑块（brightness/contrast/saturation/gamma/hue，-100..100 + 逐项复位，经 mpv equalizer 属性下发） | [补全] IINA `QuickSettingViewController.swift:14-35`（TabType 与 defaultTab=.video）、`SidebarVideoPane.swift:614-660`（EqualizerView 滑块组）、`PlayerCore.swift:1389-1409`（setVideoEqualizer→mpv 属性名）；双栏容器 [拆解] `SidebarController.swift:14-91,200-208` | 新建 `lib/pages/player/player_settings_sidebar.dart`（`SidePanelTransition` 容器 + ConnectedTabs）；均衡器写入 `lib/pages/player/player_adjustment_hud.dart` 同款通道（mpv 属性 brightness/contrast/saturation/gamma/hue） | M3-T7 (P1) |
| 10 | OSC 双形态（底部条+悬浮条同 IA 双注册）+ 可定制工具栏（两栏拖拽定制按钮集）+ 自动隐藏（1s 延迟+hover 重置；全屏 2s 隐藏光标） | [拆解] IINA `MainWindowController.swift:488-491,663-671,962-1002`、`PrefOSCToolbarSettingsSheetController.swift:20-131`；Haruna `Footer.qml:29-94,295-390`、`MpvVideo.qml:56-64` | `player_transport_bar.dart` 双形态（底部/悬浮同 IA）；工具栏按钮集持久化新键入 `settings_keys.dart`；自动隐藏叠加进 `player_panel_hold.dart` + `player_item_surface.dart` 光标隐藏 | M3-T8 (P1) |
| 11 | 类型化 OSD 消息模型（OSDType{normal,withText,withProgress,withPosition}；每个动作一个 case；addAccessoryView 扩展位） | [拆解] IINA `OSDMessage.swift:60-68+`、`OSDView.swift:67-143` | 新建 `lib/pages/player/osd/osd_message.dart`（Dart 枚举模型）；`player_seek_indicator.dart` 改为按 case 渲染；截图/均衡器/倍速统一复用 | M3-T9 (P1) |
| 12 | 网格页观感（SliverGrid 定列数 + pinned 头部 + 下拉刷新/无限滚动语义） | [抽查] Kazumi `lib/pages/popular/popular_page.dart:136`（SliverGrid）、`:163`（pinned） | `lib/pages/library/library_page.dart` 网格段改 SliverGrid+pinned 分组头（按目录/日期分组） | M4-T2 |
| 13 | 拖拽排序交互（ReorderableListView 用于收藏夹/目录排序） | [抽查] PiliPlus `lib/pages/fav_folder_sort/view.dart:71`（ReorderableListView.builder） | M4 收藏集排序、M3 播放列表面板行拖拽（Celluloid `playlist-widget.c:357-395` 拖拽语义同参） | M4-T3 / M3-T3 |
| 14 | 插件目录/商店型 UX（catalog 视图、试用页、更新动作分离） | [抽查] Kazumi `lib/pages/plugin_editor/`（plugin_catalog_view.dart、plugin_shop_page.dart、plugin_update_actions.dart 等 10 文件，目录清单实测） | `lib/pages/plugins/plugins_page.dart`（577 行）按 catalog 视图重组；安全能力见 M6 | M6-T1 |
| 15 | 日志页交互范式（Kazumi `lib/pages/logs/` 目录存在；EmoPlay 已有 `lib/pages/logs/logs_page.dart`） | [抽查] 目录清单实测 | M7 诊断日志页：级别过滤 + 导出（对齐 CROSS-PLATFORM-VERIFICATION-MATRIX.md 的取证需要） | M7-T1 |
| 16 | 音乐页交互参考（PiliPlus 音频页 controller/view/volume_button 分层） | [抽查] PiliPlus `lib/pages/audio/`（controller.dart、view.dart、volume_button.dart，目录清单实测） | M5 队列面板/音量条交互参考；EQ 已有（不变量 9） | M5-T1 |
| 17 | mpv 默认键位表分层（默认绑定表 + 用户覆盖文件 + 「绑定存在→事件是否下放」判定），只取思想，不取 mpv 自管输入机制 | [拆解] Celluloid `celluloid-def.h:91-115`、`controller-input.c:180-189`（已判不移植，思想采纳） | M3-T4/T6 的映射表默认值层 + 用户覆盖层设计依据 | M3-T4/T6 |

## 四、统一 MediaItem / PlaybackSession 数据模型（渐进迁移，不动摇 355+1）

结论：**三份 JSON schema（history/library/settings，SPEC §7）一个字段不动**；
这是 1.x 兼容发布承诺与 `test/data_compat_spec7_test.dart` 的契约。统一模型
只做 **Dart 内存层**，持久化扩展走**新文件**（新增 ≠ 修改），迁移分四步，
每步都是独立可合入的 PR 粒度。

```dart
// 新建 lib/models/media_item.dart（M4-T0 交付）
class MediaItem {
  final String path;        // 唯一键（1.x 语义：绝对路径）
  final String title;
  final String type;        // 'video' | 'audio'（classifier 词汇，不扩）
  final int size;
  final double duration;    // 秒；来自历史或元数据缓存，可空
  final DateTime? lastPlayed;
  // 以下为 3.0 扩展位：全部可空、不落三份 JSON
  final String? container;  // 元数据缓存：封装格式
  final String? videoCodec; final String? audioCodec;
  final int? width; final int? height;
}

// 新建 lib/models/playback_session.dart（M4-T0 交付）
class PlaybackSession {
  final List<MediaItem> items;   // 播放队列
  final int startIndex;
  final double? startPosition;   // resume 秒数；语义仍归 pending_resume_seek
  final bool isMusic;            // 驱动音乐/视频两形态
  final String? origin;          // 'library'|'history'|'picker'|'external'
}
```

迁移四步（每步验收都含 `flutter test` 全绿且 `data_compat_spec7_test.dart` 不红）：

1. **引入模型 + 适配器（M4-T0）**：新建上述两文件 + `lib/models/media_item_mappers.dart`
   （`LibraryEntry→MediaItem`、`HistoryEntry→MediaItem`、`MediaItem→PlayerPlaylistItem`）。
   现有页面零改动。新增 `test/media_item_mappers_test.dart`：三份 store 的样例
   JSON（1.x 真实文件样例）进、模型出、断言字段无损。
2. **播放队列收编（M4-T0b）**：`player_page_controller.dart` 的
   `PlayerPlaylistItem` 列表改为 `PlaybackSession` 派生（播放页对外接口不变）；
   `openAt(path, seconds)` 签名不变，resume 语义零改动（不变量 4）。
3. **扩展元数据缓存（M4-T4）**：新建 `lib/media/media_meta_cache.dart`：
   键沿用 `thumbnail_service.dart` 的 `sha1(path+mtimeMs)`，文件
   `media_meta.json`（新文件，随 AppData 落盘，记录 container/codecs/width/
   height），ffprobe 两段式同 thumbnail 模式（进程列表参数、超时强杀、降级）。
   新增 `test/media_meta_cache_test.dart`（含损坏 JSON 降级用例，robustness 先例）。
4. **UI 切换（M4-T5）**：library/home 页逐页改读 `MediaItem` 视图模型；完成后
   `PlayerPlaylistItem` 降为播放页内部实现类。

红线：任何一步若需要改三份 JSON 的字段名/结构 → **不变量赢，改设计不改
schema**（SPEC §10.3）。settings.json 的新增**键**（如鼠标映射、面板宽度）
允许追加（1.x 读取方忽略未知键），但每追加一个键必须在
`test/emoplay_settings_test.dart` 补默认值与往返用例。

## 五、阶段排期（M3-M8）

约定：每阶段收尾执行 SPEC §9 门禁（`source /opt/emoplay-env.sh` →
build_runner → `flutter analyze` → `flutter test` → `flutter build linux --debug`；
发布期 `--release`）；用例底数 **355+1 只增不减**；表中「验收」均为机检命令或
文件存在性检查，人工项显式标注。依赖关系：M3 内部 T0 → 其余；M4 依赖 M3 仅
在播放页文件冲突上（先 M3 后 M4 串行最稳）；M5 依赖 M4-T0；M6/M7 可与 M4/M5
并行（文件面不相交）；M8 最后。

### M3 播放器交互（第一优先，工作量最大）

依赖：无外部依赖；**T0 必须先做**（后续任务都在拆出来的文件上施工）。

| 任务 | 内容（文件级） | 依赖 | 验收（机检） |
| --- | --- | --- | --- |
| M3-T0 ✅（`c9245f8`） | 拆 `player_item.dart`（1538 行）：PiP→`player_pip.dart`、audio_service 绑定→`player_audio_binding.dart`、键盘→既有 `player_keyboard_shortcuts.dart` 收拢、菜单→独立文件；`player_screenshot_sheet.dart`（1052 行）复审拆分。纯搬移不改行为 | 无 | `flutter test` 355+1 全绿；`flutter analyze` 0 error；`wc -l lib/pages/player/player_item.dart` < 500；新增文件均 < 600 行 |
| M3-T1 ☐ | 帧预览：新建 `lib/pages/player/controller/seek_preview_controller.dart`（第二 Player，Haruna 属性集：pause/mute/aid=no/sid=no/sub-auto=no/osd-level=0/audio-display=no/hr-seek 跟随等价设置）；`player_progress_bar.dart` hover 气泡加载帧图（`Video` widget 纹理）；拖动中双 seek（主+预览）；开关+预览宽度设置落 `player_settings.dart` + `settings_keys.dart` 新键 | T0 | 新增 `test/seek_preview_controller_test.dart`（≥6 用例：激活条件 isLocalFile&&isVideo&&非停止、消抖、隐藏即 pause、设置关闭不建实例、dispose 链）；性能守卫入 `performance_guards_test.dart`：关闭开关时 Player 实例数不增（测试缝计数） |
| M3-T2 ☐ | 章节：`mpv_player_properties.dart` 补 chapter/chapter-list 读取说明（沿用文件头考证格式）；新建 `lib/pages/player/controller/chapters_model.dart`（titleAtPosition 上界二分）；`player_progress_bar.dart` 章节刻度（rowCount*20<宽 规则）+ hover 章节标题；新建 `lib/pages/player/chapters_sheet.dart`（跳转+Skip 过滤设置键）；中键跳下一章 | T0 | 新增 `test/chapters_model_test.dart`（≥8 用例：空表/单章/边界/二分正确性）；chapters_sheet 挂接；全绿底数 ≥ 355+14 |
| M3-T3 ☐ | 播放列表悬浮面板：`player_item_panel.dart:569` 底板升级悬浮面板（`SidePanelTransition` 容器）；左右 edge 设置键、宽度记忆键、边缘悬停展开（复用 `player_gesture_detector.dart:39-43`）；行右键菜单（播放下一/移除/复制路径）+ 行拖拽排序（PiliPlus ReorderableListView 范式） | T0 | 面板宽度/edge 持久化用例入 `test/emoplay_settings_test.dart`；新增 `test/playlist_panel_test.dart`（≥4 用例：开关/宽度钳制 260..window-50 语义/拖拽重排/菜单动作） |
| M3-T4 ☐ | 鼠标映射：新建 `lib/settings/mouse_action_settings.dart`（十键位×修饰键→动作名字典 + 默认表照抄 Haruna `mousesettings.kcfg` 语义）；`player_gesture_detector.dart` 加 tap/doubleTap/secondaryTap/滚轮分发→查表→动作执行；新建 `lib/pages/settings/mouse_settings.dart` | T0 | 新增 `test/mouse_action_settings_test.dart`（≥8 用例：默认表、修饰键解析、getAction 未知键回退、JSON 往返） |
| M3-T4b ☐ | 自定义命令：新建 `lib/mpv/config/custom_commands.dart`（命令串分词、osdMessage、shortcut/action、setOnStartup）；启动注入并入 `mpv_player_properties.dart` build()（注释同步平移 1.x 考证）；UI 挂「mpv 配置」设置类 | T0 | 新增 `test/custom_commands_test.dart`（≥5 用例：分词引号、非法命令拒绝、setOnStartup 注入顺序、不替换用户 scripts 表） |
| M3-T5 ☐ | mpv 高级选项编辑器：新建 `lib/mpv/config/mpv_option_meta.dart`（声明式元数据：name/group/type/default/help）；`lib/pages/settings/mpv_settings.dart` 改分目录+可搜索；`mpv_config_parser.dart` 补注释保持往返+仅偏离默认写回；改动实时下发（apply 通道已有逐键失败日志） | T0 | `test/mpv_config_parser_test.dart` 增往返用例（注释/分节/行内注释保留 ≥5）；新增 `test/mpv_option_meta_test.dart`（≥4：默认值 diff、类型渲染分派） |
| M3-T5b ☐ | 原始 mpv 选项追加：free-form option=value 列表 UI（增删/排序）并入 mpv_settings；冲突保护：用户显式项不被内置默认覆盖（IINA userOptionsContains 语义），合并点 `mpv_player_properties.dart:64-103` | T5 | `mpv_player_properties_test.dart` 增 ≥2 用例（用户项覆盖内置默认、重复项告警日志） |
| M3-T6 ☐ | input.conf 快捷键编辑器：新建 `lib/mpv/compat/input_conf_codec.dart`（解析/序列化：注释往返、修饰键规范化、menu:/! 语法、ignore、只写偏离默认）；`keyboard_settings.dart` 升级编辑+按键录制（Flutter `HardwareKeyboard` 事件捕获，键名经 `mpv_key_name.dart`）；写前 `.backup` | T0 | 新增 `test/input_conf_codec_test.dart`（≥10 用例：mpv.net Parse/ConvertToString 等价语义表、注释往返逐字节、备份生成）；录制窗 widget 测试 ≥2 |
| M3-T7 ☐ | 播放设置侧栏：新建 `lib/pages/player/player_settings_sidebar.dart`（layout/video/audio/sub 四 tab，`SidePanelTransition` + `ConnectedTabs`）；视频均衡器五滑块（brightness/contrast/saturation/gamma/hue，-100..100+复位，经 mpv 属性下发）；音频页复用 EQ 既有通道 | T0 | 新增 `test/player_settings_sidebar_test.dart`（≥6 用例：tab 切换、滑块→属性命令串断言、复位） |
| M3-T8 ☐ | OSC 双形态+工具栏定制+自动隐藏：`player_transport_bar.dart` 底部/悬浮双形态同 IA；工具栏按钮集两栏拖拽定制（持久化新键）；`player_panel_hold.dart` hover 重置计时器+全屏态；`player_item_surface.dart` 全屏 2s 光标隐藏 | T0 | 新增 `test/transport_bar_customization_test.dart`（≥4：按钮集持久化往返、双形态切换、隐藏计时器重置） |
| M3-T9 ☐ | 类型化 OSD：新建 `lib/pages/player/osd/osd_message.dart`（OSDType 枚举+各动作 case）；`player_seek_indicator.dart` 按 case 渲染（进度/文本/位置）；扩展位接口供截图等插入 | T0 | 新增 `test/osd_message_test.dart`（≥4：case→视图类型分派、进度格式化） |

M3 阶段验收追加：`flutter test` 用例数 ≥ **355 + 45**；`flutter build linux --debug`
通过；帧预览/自动隐藏的 GUI 手感按 SPEC §9 标注「显示待人工验收」。

### M4 媒体库升级

依赖：M3-T0（文件冲突面）；§四迁移四步是本阶段主线。

| 任务 | 内容 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M4-T0 ✅（`0da4a95`） | §四步骤 1+2：`lib/models/media_item.dart`、`lib/models/playback_session.dart`、`lib/models/media_item_mappers.dart`；播放队列收编 | M3 | 新增 `test/media_item_mappers_test.dart`（≥8：1.x 样例 JSON 进出无损）；`data_compat_spec7_test.dart` 必绿 |
| M4-T2 ✅（`25dd830`） | 网格观感：`library_page.dart` 改 SliverGrid + pinned 分组头（目录/年月分组，Kazumi popular_page 范式）；保持 search/typeFilter/sortMode 既有语义 | M4-T0 | 新增 `test/library_grid_grouping_test.dart`（≥3：分组键、筛选后分组、pinned 结构冒烟）；响应性守卫维持绿 |
| M4-T3 ✅（`25dd830`） | 收藏集：新建 `lib/media/favorites_store.dart`（`favorites.json` 新文件，条目=MediaItem path+addedAt；原子写同 settings 模式）；library/home 卡片收藏角标；排序复用 ReorderableListView 范式 | M4-T0 | 新增 `test/favorites_store_test.dart`（≥6：增删/去重/损坏 JSON 降级/原子写/lastPlayed 不受影响） |
| M4-T4 ✅（`0da4a95`） | 元数据缓存：§四步骤 3（`media_meta_cache.dart` + `media_meta.json`） | M4-T0 | 新增 `test/media_meta_cache_test.dart`（≥6：sha1 键、损坏降级、超时强杀、无 ffprobe 优雅退化）；性能守卫：缓存命中不触发进程 |
| M4-T5 ✅（`25dd830`） | 目录树导航：`library_page.dart` 加目录侧栏（面包屑+树），数据源 LibraryStore.directories 派生，不加新扫描 | M4-T2 | 新增 `test/library_folder_tree_test.dart`（≥4：树构造、深度剪枝与扫描器语义一致、选中联动） |
| M4-T6 ✅（`5fedee0`，2026-11-12 用户增补） | 本地 NFO/海报/剧集分组：新建 `lib/media/nfo_parser.dart`、`lib/media/nfo_meta_cache.dart`（NFO 元数据缓存）、`lib/media/poster_finder.dart`（本地海报定位）、`lib/media/episode_grouper.dart`（剧集分组）+ `lib/pages/library/nfo_details_sheet.dart` 详情弹层；`library_grid_groups.dart`/`library_page.dart` 接入剧集分组与海报展示 | M4-T0 | 随 `5fedee0` 新增 `test/nfo_parser_test.dart`、`test/nfo_meta_cache_test.dart`、`test/episode_grouper_test.dart`、`test/poster_finder_test.dart`、`test/library_nfo_ui_test.dart` 共 5 个测试文件（git show --stat 核实入库） |
| M4-T7 ✅（`eb3b2bf`，2026-11-12 用户改向纳入，框架轮） | 在线元数据兜底框架（本地 NFO 之后的联网补全；真实数据流待用户 TMDB key）：新建 `lib/media/online/metadata_provider.dart`（provider 接缝）、`lib/media/online/tmdb_provider.dart`（注入 http.Client 的 /search/multi 适配器，全部失败形态收束为一个类型化异常）、`lib/media/online/online_meta_service.dart`（五道门禁：关→无 key→本地 NFO 覆盖→缓存→才联网；`media_online.json` 新缓存文件，正命中与明确未命中落盘、传输失败不缓存）；`emoplay_settings.dart` 增 `online` 段（enabled 默认 **关** + apiKey 默认 ''）；设置中心增「在线元数据」分类（`online_settings.dart` + 路由）；NFO 详情弹层挂「联网补全」动作（badge 拓宽到全部视频格子，无 NFO 格子 tooltip 为联网补全），七种结果各有优雅提示；可达性实测：api.themoviedb.org 可达（curl 0.83s / Dart HttpClient 1.04s，无效 key 恰返 HTTP 401 标准错误体），此前 GitHub API TLS ECONNRESET 未复现于 TMDB | M4-T6 | 新增 `test/online_meta_service_test.dart`（10 用例：开关关不联网、无 key 降级、本地 NFO 不联网、缓存命中零请求、损坏响应/HTTP 错误/超时降级不落缓存、正命中持久化、负命中缓存、forget）、`test/tmdb_provider_test.dart`（10 用例：请求拼装、电影/剧集解析、person 行跳过、空结果、401/损坏体/缺 results 异常）、`test/library_online_ui_test.dart`（零请求 UI 冒烟）；`emoplay_settings_test.dart` 增 4 用例（online 默认值/往返/错误类型/恢复默认）；全量 `flutter test` 539 绿 |

### M5 音乐

依赖：M4-T0（PlaybackSession）。

| 任务 | 内容 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M5-T1 ✅（`2115183`） | 循环/队列：`player_playback_controller.dart:443` 的 `PlaylistMode.none` 硬编码提升为设置+面板切换（single/playlist/none，media_kit PlaylistMode 原生）；music 形态队列面板（复用 M3-T3 面板组件） | M4-T0 | 新增 `test/music_queue_test.dart`（≥5：模式切换持久化、audio 队列续播、切 video 形态语义） |
| M5-T2 ✅（`ec456b3`） | 音频属性：replaygain（mpv replaygain 属性开关，设置落音频类）、gapless（`gapless-audio=weak` 默认考察注释随行）；沿用 `mpv_player_properties.dart` 通道 | M5-T1 | `mpv_player_properties_test.dart` 增 ≥2 用例；设置往返用例 |
| M5-T3 ✅（`a539866`） | 歌词与迷你条：`music_lyrics_page.dart` 升级（逐行高亮精度、翻译列）；新建 `lib/pages/player/music_mini_bar.dart`（非播放页常驻迷你条） | M5-T1 | `test/music_lyrics_page_test.dart` 增 ≥3；新增 mini bar 测试 ≥2（`lrc_parser_test.dart` 不动） |

### M6 插件安全

依赖：无（可与 M4/M5 并行）。

| 任务 | 内容 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M6-T1 ☐ | 清单完整性：`plugin_manifest.dart` 增资产 sha256 必填校验（size+hash 双字段，缺一拒装）；`plugin_git_runner.dart` 校验点前置 | 无 | `test/plugin_manifest_test.dart` 增 ≥4（缺 hash 拒绝、hash 不符拒绝、重放同 hash 通过、字段往返） |
| M6-T2 ☐ | 操作审计：`plugin_manager.dart` planOperation 结果（永不直接执行的判定链）落盘 `plugin_audit.jsonl`（AppData 新文件，append-only） | 无 | 新增 `test/plugin_audit_test.dart`（≥4：append-only、损坏行跳过、porcelain 拒绝也留痕、不写用户目录） |
| M6-T3 ☐ | 暴力面收缩：destination 防穿越 fuzz 用例批量（路径穿越/符号链接/绝对路径/`..` 混合 ≥10 用例）；operations 白名单常量化 | 无 | `test/plugin_manager_test.dart` 增 fuzz 段；全绿 |
| M6-T4 ☐ | 插件页 catalog 重组（Kazumi plugin_editor 范式：目录视图+详情+更新动作分离），三段式 UI 语义不变（不变量 6） | M6-T1 | 现有 plugin 用例全绿；新增 catalog 分派测试 ≥2 |

### M7 诊断/测试

依赖：M3-T2（章节属性读取通道建立后探针更全）；集成测试可与施工并行。

| 任务 | 内容 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M7-T1 ☐ | 运行时诊断：`diagnostics_info.dart` 补 mpvVersion（mpv-version 属性）、renderBackend（vo 当前值）、audioDevice（ao 列表）；诊断页 + 日志页级别过滤/导出 | M3-T0 | 新增 `test/diagnostics_runtime_test.dart`（≥4，live-libmpv 模式照抄 `audio_probe_test.dart` 头注释约定）；非容器环境缺失时 skip 契约同现有 |
| M7-T2 ☐ | 播放链路集成测试：新建 `test/playback_chain_live_test.dart`（open→fileLoaded→seek→resume 一次性消费→下一集；live-libmpv 无渲染面，审计 §四缺口） | M3-T0 | ≥6 用例；CI 有真 libmpv 环境真跑（pr.yaml 装步已先于 test）；条件缺失 skip 打印（同 audio_probe 先例） |
| M7-T3 ☐ | 性能回归基线：`perf_scan_benchmark_test.dart` 增 M3/M4 新增面的守卫（预览实例停用零开销、元数据缓存命中路径耗时上限断言） | M3-T1/M4-T4 | 夹具缺失自动降级契约维持（R7 先例）；新增断言 ≥2 |
| M7-T4 ☐ | GUI E2E 计划落地：按 CROSS-PLATFORM-VERIFICATION-MATRIX.md「桌面自动化」节在桌面空闲窗口执行指针类用例（audit §八工具链结论：wlrctl 可用、绝对坐标需空闲） | 桌面空闲 | 矩阵表逐行回填（人工项标「需用户」） |

### M8 发布工程

依赖：M3-M7 完成；实机项配合 CROSS-PLATFORM-VERIFICATION-MATRIX.md。

| 任务 | 内容 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M8-T1 ☐ | prerelease 语义：release.yaml 按 tag 后缀（-alpha/-beta/-rc→prerelease=true）自动判定 | 无 | workflow 演练（draft 制下核对）；BUILD_GUIDE §四流程不回退 |
| M8-T2 ☐ | Android 签名：接入密钥（CI secret 注入 keystore，产物改签名 APK；CHANGELOG「未签名」限制消除） | 用户提供密钥 | `apksigner verify` 通过；矩阵 Android 行回填 |
| M8-T3 ☐ | Windows 收尾：`emoplay://` URL 内容转发到已运行实例（R4 `bd36f70` 遗留）；msix 签名评估（`pubspec.yaml:98-102` sign_msix:false → 决策记录） | 无 | 新增 Windows 集成测试或手动步骤入矩阵；决策写入本文件 §七 |
| M8-T4 ☐ | i18n 收尾：其余设置页字符串迁 `AppLocalizations`（zh+en 双语全页面覆盖） | 无 | 新增 l10n 守卫测试（照 R3/R4 先例每页 ≥2）；`flutter analyze` 0 |
| M8-T5 ☐ | macOS 公证/签名评估 + iOS 构建注释维持（CHANGELOG 已知限制不回退） | 需用户/证书 | 决策记录；矩阵 macOS 行回填 |
| M8-T6 ☐ | 3.0 发布：CHANGELOG 3.0 节、RELEASE/WORK_REPORT 全套、tag 走 draft 制人工 publish | 全部 | SPEC §9 release 门禁 + 矩阵 Linux 行全绿 |

## 六、贯穿约定（继承 2.0，冲突时不变量优先）

1. 环境红线：宿主机零污染；`/home/emo/code/mpv-emo` 只读；构建前
   `source /opt/emoplay-env.sh`（SPEC §3）。
2. 决策优先级：SPEC §4 九条不变量 > 一切；规格未覆盖处取最接近 Kazumi 现状
   （SPEC §10），本文映射表与 Kazumi 现状冲突时，**以 Kazumi 现状为准**。
3. 平移铁律：1.x 考证注释随行平移；三份 JSON 字段名一个不改；新增键必须补
   默认值+往返用例（§四红线）。
4. fork 内核：media_kit 升级/同步一律走 [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md)
   流程，不在本路线图各任务内顺手升级。
5. 实机验证：一律走 [CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md)，
   矩阵行是验收的一部分，不是附属品。
6. 文档纪律（DOC-STANDARD）：每任务完成回填 ☐→✅+提交哈希；数字实测写来源；
   坏消息单列。

## 七、已知限制与未做项（坏消息）

- **拆解输入截断**：IINA/mpv.net 第 5 模块靠本地源码补全；Kazumi/PiliPlus 两路
  拆解未送达，相关映射全部为本文写者定向抽查（§三已标注）。若原拆解含未覆盖
  的发现，需增量合并进 §三。
- **fork-point 未知**：与上游 media-kit 的精确 merge-base 需外网（本环境
  GitHub API 不可达，2026-11-11 实测 TLS ECONNRESET），详见
  [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md) §六。
- **M0-M2 无文档**：六阶段外的 M0-M2（规划阶段）没有独立文档，其产出即本文
  §二-§四；如工作流另有定义，以工作流为准。
- **性能基线口径**：R7 性能实测为容器 Isolate 计时，非宿主基线
  （reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md）；M7-T3 的守卫仍沿用
  该口径，宿主基线归 SPEC §9 人工验收轮。
- **未排期**：iOS 正式进矩阵（签名方案未定）、Flatpak 打包（维持不做）、在线
  字幕联网源（与本地优先纪律冲突，明确不做）。
- **改向纳入（2026-11-12 用户决策）**：在线元数据联网源由「明确不做」改方向
  纳入排期，排在第 11 轮，位于本地 NFO/海报（M4-T6，`5fedee0`）之后作联网兜底；
  框架已落地（M4-T7，`eb3b2bf`）：默认关闭、设置中心可开、API key 用户自填，
  真实联网数据流待用户提供 TMDB key 后实测。
