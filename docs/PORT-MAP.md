# PORT-MAP：mpv-emo (C++/Qt) → EmoPlay 2.0 (Dart/Flutter) 文件级映射

源仓库 `/home/emo/code/mpv-emo`（只读）。目标目录结构见 §5。**平移铁律：源文件注释里嵌着 mpv v0.37 源码级考证（文件行号级引用），必须连注释一起搬**；JSON schema 即兼容契约，字段名一个都不能改。

## 1. A 类：纯逻辑直译（零 Qt 依赖，函数级对译 + 用例平移）

| 源 | 目标（emoplay/lib/ 下） | 要点 |
|---|---|---|
| `src/config/MpvConfigParser.{h,cpp}` | `mpv/config/mpv_config_parser.dart` | `parseMpvConf`（行内 `#` 属于值）、`parseInputConf`（空格前导 `#` 才是注释）、`tokenizeCommand`（双引号） |
| `src/compat/MpvImportRules.{h,cpp}` | `mpv/compat/mpv_import_rules.dart` | 强制/剥离/重定向三张表照抄；redirectTarget 单一事实源 |
| `src/compat/MpvProfileScanner.{h,cpp}` | `mpv/compat/mpv_profile_scanner.dart` | XDG 语义注释即规格：XDG_CONFIG_HOME 优先且排他、否则 `~/.config/mpv`、legacy `~/.mpv` 仅当主候选不存在；Windows `%APPDATA%/mpv`；递归扫 scripts/shaders/fonts/script-opts |
| `src/compat/MpvKeyName.{h,cpp}` | `mpv/compat/mpv_key_name.dart` | Qt::Key 枚举 → Flutter `LogicalKeyboardKey`，"ctrl+shift+PGDWN" 语法不变 |
| `src/quality/QualityProfileEngine.{h,cpp}` | `quality/quality_profile_engine.dart` | 决策表纯函数；Anime4K 链序 L82-118 照抄 |
| `src/quality/InterpolationDecision.{h,cpp}` | `quality/interpolation_decision.dart` | 6 个 MEMC_* 预设、admission 阻塞原因枚举、`@emoplay-interp:vapoursynth=file=%len%...` vf 条目构造与链读回校验 |
| `src/music/LrcParser.{h,cpp}` | `music/lrc_parser.dart` | 多时间戳、[ti/ar/al]、BOM/CRLF |
| `src/music/MusicController.cpp` 纯函数 | `music/equalizer.dart` | isAudioMedia/lyricIndexAt/equalizerChain/bandFrequencies/presetGains |
| `src/media/MediaClassifier.{h,cpp}` | `media/media_classifier.dart` | Kind 枚举、planDrop、folderMedia(maxDepth=4)、扩展名表（视频 15、音频 8、字幕 srt/ass/ssa/vtt/sub） |
| `src/library/LibraryStore.cpp` 静态扫描 | `media/library_store.dart` | 扫描算法 + library.json 格式（SPEC §7） |
| `src/library/ThumbnailQueue.h` + `ThumbnailService.cpp` 静态逻辑 | `media/thumbnail_service.dart` | 缓存键/两段链/超时/降级；QProcess→`dart:io Process` |
| `src/history/HistoryStore.{h,cpp}` | `media/history_store.dart` | 记录/去重置顶/50 上限/5s 刷新语义/history.json |
| `src/settings/AppSettings.{h,cpp}`（schema 部分） | `settings/emoplay_settings.dart` | settings.json 全字段（SPEC §7）；QSaveFile→原子写 |
| `src/plugins/PluginManifest.{h,cpp}` | `plugins/plugin_manifest.dart` | 纯解析校验（name 域/url/destination 必填/防穿越/mode∈{check,replace}；接受 `{"sources":[...]}` 或裸数组） |
| `src/plugins/PluginManager.cpp` 状态机 | `plugins/plugin_manager.dart` | planOperation/状态机/update 四步/QProcess git→`Process.run`；state.json 格式不变 |
| `src/plugins/RemoteManifestSource.cpp` 纯逻辑（mergeCatalog/cacheFileName） | `plugins/remote_manifest_source.dart` | QNAM→package:http；缓存文件名 host+URL digest 不变 |
| `src/update/UpdateChecker.cpp` 纯函数 | `services/update_checker.dart` | tagToVersion/compareVersions(alpha<beta<rc)/isNewer |

## 2. B 类：重设计（Qt 集成点 → Flutter 生态），语义逐条保留

| 源 | 目标 | 保留的语义 |
|---|---|---|
| `src/mpv/MpvEngine.cpp`（语义层） | media_kit `NativePlayer` + `PlayerConfiguration.properties` | 默认选项表语义、load-scripts=no、写路径重定向、observe 清单对应 player streams、NONE 属性清空规则（防止上一文件残留值） |
| `src/mpv/PlaybackController.{h,cpp}` | `player/controllers/playback_controller.dart`（MobX） | openAt pendingSeek 一次性消费、playlist 管理、错误文案 |
| `src/compat/CompatController.{h,cpp}` | `mpv/compat/compat_controller.dart`（决策持久化+编排） | 导入决策持久化、startupOptions 组装顺序（先 compat 再插件 append）、own empty input.conf 兜底与失败告警 |
| `src/quality/QualityController.{h,cpp}` | `quality/quality_controller.dart`（MobX） | fileLoaded/videoParams/fps 事件驱动重算、掉帧≥2/s 会话降档、`change-list glsl-shaders clr+append` |
| `src/quality/InterpolationController.{h,cpp}` | `quality/interpolation_controller.dart` | 会话级 probe（append→读回 vf→remove）、失败持久化 off + vsUnavailable |
| `src/quality/IccController.{h,cpp}` | `quality/icc_controller.dart` | 存在/可读校验→设置+读回校验→禁用恢复快照→失败持久化 off |
| `src/media/MediaBrowser.{h,cpp}` | `media/media_browser.dart` | 异步+generation 号防陈旧、面包屑/历史/quickLinks（path_provider）、filter/search/status |
| `src/library/LibraryScanWorker` | `Isolate.run`/`compute` + 取消标志 | 取消语义按文件轮询 |
| `src/main.cpp` 装配 | `lib/app/` DI（flutter_modular coreModule） | 装配顺序语义：compat 选项→插件 scripts 追加→播放器初始化→stores |

## 3. C 类：不搬代码，搬"结论/规范"

- `docs/architecture.md`（367 行）：P4/P5/P6/P7 的 mpv 0.37 行为考证——迁移期间作为 **mpv 行为规格书**，平移相关模块时必读对应章节。
- `docs/project-upgrade/03-mpv-compatibility-matrix.md`：未验证清单 = 新项目 M5 的验证清单。
- `qml/Theme.qml` / `qml/AppIcon.qml`：视觉 token 与 30 图标清单可作设计输入（实现用 Flutter 生态）。
- `tools/e2e*.py` / `vkbd.py`：Wayland E2E 手法参考。
- `qml/Main.qml` 的 ESC 优先级链、MpvItem 常驻单实例约束（Flutter 对应：Video widget 不随路由销毁）。

## 4. 测试用例映射（用例表平移，数量在 M4-M7 各阶段报告中对账）

先 `ls /home/emo/code/mpv-emo/tests/` 全量枚举再逐个映射；已知对应：

| C++ 测试 | Dart 测试 | 平移阶段 |
|---|---|---|
| `tests/test_media_classifier.cpp` | `test/media_classifier_test.dart` | S3 |
| `tests/test_library_store.cpp` | `test/library_store_test.dart` | S4 |
| `tests/test_history_store.cpp` | `test/history_store_test.dart` | S4 |
| `tests/test_import_rules*.cpp`（以实际文件名为准） | `test/mpv_import_rules_test.dart` | S5 |
| `tests/test_mpv_config_parser*.cpp`（同上） | `test/mpv_config_parser_test.dart` | S5 |
| `tests/test_quality_profile_engine*.cpp`（同上） | `test/quality_profile_engine_test.dart` | S6 |
| `tests/test_interpolation_decision*.cpp`（同上） | `test/interpolation_decision_test.dart` | S6 |
| `tests/test_plugin_manifest*.cpp`（同上） | `test/plugin_manifest_test.dart` | S7 |
| `tests/test_app_settings.cpp` | `test/emoplay_settings_test.dart` | S4 |

纯逻辑模块的每个 C++ TEST/用例 = 一个 Dart `test()`；断言值原样照抄（它们是行为规格）。`tests/fixtures/media/` 的夹具生成方式（ffmpeg 命令）写在测试文件注释里的照抄，Dart 测试用临时目录现生成。

## 5. 目标 Dart 目录树

```
emoplay/lib/
├── app/            # 装配:coreModule、路由表、主题
├── pages/          # home/library/player/plugins/settings(改自 Kazumi pages/)
├── player/         # controllers/ widgets/ gestures/ playlist/ subtitle/ tracks/
├── media/          # classifier browser library_store history_store thumbnail_service
├── mpv/            # config/ compat/(parser rules scanner keyname controller) diagnostics/
├── quality/        # profile_engine interpolation_decision icc_controller anime4k/
├── plugins/        # manifest manager remote_source state/
├── music/          # lrc_parser equalizer
├── services/       # settings_store update_checker shaders(改自Kazumi)
├── models/         # 本地媒体条目/播放参数(sealed LocalFilePlaybackArgs)
└── common/         # 通用组件(Kazumi bean/ 保留件)
```

## 6. PiliPlus 摘取清单（S2 播放器阶段，源 `/home/emo/code/_upstream/piliplus`）

| 源文件 | 摘什么 | 改写要求 |
|---|---|---|
| `lib/plugin/pl_player/widgets/forward_seek.dart` / `backward_seek.dart` | 双击快进/快退浮层 | 去 GetX，改 MobX/局部 State；接入 Kazumi 手势层 |
| `lib/plugin/pl_player/view/view.dart` 手势段 | 长按倍速（长按 3x、松手恢复） | 只取交互逻辑，不搬 view 整体 |
| `lib/common/widgets/progress_bar/` | 进度条交互样式 | 自包含组件可直接搬+换肤 |
| `lib/pages/video/widgets/player_focus.dart` | 键位表参考（Space/F/D/P/M/S/L/方向键/倍速） | 去 UgcIntroController/三连/投币；叠加 1.x 键位（Ctrl+1..5、ESC 链） |
| `lib/plugin/pl_player/models/` 枚举 | PlaySpeed/DoubleTapType/FullscreenMode 等值对象 | 按需摘取 |
| `lib/plugin/pl_player/utils/fullscreen.dart` | 桌面全屏流程参考 | 落地用 `windowManager.setFullScreen` |

禁止整体搬 `view.dart`/`controller.dart`（B 站强解包耦合）；不引入 GetX。
