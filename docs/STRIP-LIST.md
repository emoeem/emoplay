# STRIP-LIST：Kazumi → EmoPlay 2.0 文件级处置清单

源：`/home/emo/code/_upstream/kazumi`（克隆后记录 HEAD commit）。目标：`/home/emo/code/emoplay`（全新 git 仓库，不是 fork——导入代码 + 保留许可头）。

> 执行注意：清单基于 2026-11-09 的 main 分支考察。克隆后若发现实际文件有出入，以"**职责判断**"为准：番剧采集/Bangumi/规则解析/弹幕服务 → 删；导航/设置组件/播放器/着色器服务/工具 → 留。每删一个模块，编译错误会告诉你牵连面，逐个解决。

## 1. 保留（骨架核心，原样或近原样）

- `lib/pages/menu/`（menu.dart + route_visibility.dart）——Tab 容器（菜单项改五页）
- `lib/pages/index_page.dart`
- `lib/pages/settings/` + `lib/pages/settings/settings_module.dart`（删 danmaku/sync/plugin/download 相关路由与页面，其余保留；分类改 SPEC §6 的 EmoPlay 分类）
- `lib/bean/settings/` 全部（SettingsList/SettingsSection/SettingsRadioSection/SettingsCategoryTile/SettingsSliderTile/SettingsTile/settings_detail_scaffold/settings_dropdown_tile/theme_provider/color_type）
- `lib/bean/appbar/`、`lib/bean/dialog/`
- `lib/bean/widget/`（删 bangumi_avatar/bangumi_mirror_error_widget/collect_button）
- `lib/pages/player/` 全目录（删 syncplay、danmaku 相关 controller；其余：playback controller、panel/seek/screenshot/debug/aspect-ratio、手势、指针、快捷键、字幕样式全保留）
- `lib/services/`：shaders/（ShaderAssetService 原样）、storage/、logging/、platform/、network/（删镜像加速）、player/、update/（删 Kazumi API 调用部分，保留版本比较）
- `lib/utils/`：constants.dart（**删番剧常量** bangumiHTTPHeader/UA 等，**保留** mpvAnime4KShaders 数组、倍速表、LayoutBreakpoint）、device、theme、format、file_system、async_* 4 件、date_time、version、image_extension、media.dart（buildShadersAbsolutePath）
- `assets/shaders/`（9 个 GLSL + LICENSE 原样）
- `lib/hive_registrar.g.dart`（按新模型重新生成）
- `linux/`、`android/`（改 applicationId/命名）、`windows/`、`macos/`、`ios/` 平台壳（品牌化）
- `.github/workflows/`（改造为 EmoPlay 的 CI，M8 用）

## 2. 删除（番剧业务，整目录/整文件）

- `lib/plugins/`（XPath 规则引擎）
- `lib/request/`（bangumi_api/danmaku_api/trace_api/plugin_catalog_api 等）
- `lib/webview/`（captcha + video 抓流）
- `lib/bbcode/`
- `lib/pages/popular/`、`lib/pages/timeline/`、`lib/pages/info/`、`lib/pages/search/`、`lib/pages/video/`（番剧中转页；播放器本体在 pages/player/ 已保留）、`lib/pages/plugin_editor/`、`lib/pages/collect/`
- `lib/services/plugin/`、`lib/services/video_source/`、`lib/services/download/`、`lib/services/deep_links/`
- `lib/services/sync/` 中 bangumi_sync_service/danmaku_shield_sync_service（webdav.dart、history_sync_service.dart 若被保留模块引用可留壳）
- `lib/modules/` 中 bangumi、character(s)、comments、roads、staff、plugin
- `lib/bean/card/` 番剧卡片（bangumi_*/character/comments/rule/staff；network_img_layer/palette_card 视引用决定）
- `lib/request/` 关联模型：`lib/models/` 里 bangumi 相关
- `assets/images/logo/`、`assets/statements/`、`assets/fonts/MiSans-*.ttf`
- `fastlane/`
- pubspec 依赖：xpath_selector、json_path、html 解析、flutter_inappwebview×3、webview_windows、desktop_webview_window、app_links、cached_network_image/flutter_cache_manager、flutter_rating_bar、scrollview_observer、macos_secure_bookmarks、cookie_jar、crypto（若仅反爬用）
- `lib/utils/` 中 m3u8_parser、m3u8_ad_filter、episode_url、anime_season、search_parser、bangumi_mirror_credentials、dandan_credentials、danmaku.dart、encoding
- main.dart 中 deep links / webview / ECH HTTP / 弹幕 API --dart-define 注入段

## 3. 改造（换业务内核，结构照抄）

| 文件 | 改造 |
|---|---|
| `lib/pages/menu/menu.dart` | 四 Tab → 五 Tab：首页/媒体库/播放/插件/设置（SPEC §5） |
| `lib/pages/index_module.dart` | 路由表：tabModule 挂五页；删 popular/timeline/info/search/video 模块 |
| `lib/app_module.dart` / `core_module.dart` | DI：删番剧单例（PluginsController 等），加 EmoPlay stores（settings/library/history/plugins/quality） |
| `lib/pages/my/` | 改造成"首页"Tab 内容（最近播放/继续观看/统计，SPEC §5） |
| `lib/pages/history/` + `lib/repositories/history_repository.dart` | 键从 BangumiItem 改本地文件 path；Progress(file→position/duration) 机制保留 |
| `lib/pages/video/video_playback_args.dart` | sealed args 保留；子类换 `LocalFilePlaybackArgs{path,title,startAt}` |
| `lib/main.dart` | 删番剧初始化；window_manager/Hive/MediaKit.ensureInitialized 保留 |
| `lib/app_widget.dart` | locale 默认 zh；删 Mi Sans fontFamily；默认深色 |
| `pubspec.yaml` | name `emoplay`、版本 2.0.0-alpha；**media_kit overrides 保持 Predidit fork @ 83b7ca6 不动**；删 §2 依赖 |
| 平台壳 linux/android/… | applicationId `com.emoplay`、显示名 EmoPlay、占位图标 |
| `.github/workflows/*` | 改名/改 dart-define/删 Kazumi 密钥注入 |

## 4. 品牌化操作清单

1. 全局替换应用显示名 Kazumi → EmoPlay（UI 文案、窗口标题、linux/*.desktop、android:label）
2. 图标：生成占位 PNG（简单"▶E"矢量风，深底浅字）替换全部尺寸（linux/icons、android mipmap、windows/macos/ios 资源）——**不得复用任何 Kazumi 位图**
3. 删除 README 原文，写 EmoPlay README（M8 完成）
4. `lib/utils/constants.dart` 里appName/应用内链接常量改 EmoPlay（更新检查地址在 M8 定为 EmoPlay 仓库）

## 5. 验证口径

- `dart run build_runner build --delete-conflicting-outputs` 成功
- `flutter analyze` 0 error
- `grep -ri "bangumi\|kazumi\|xpath\|danmaku_api\|番剧" lib/` 剩余命中必须逐一解释（UI 文案里的"弹幕"等中性词可留，业务引用必须清零）
- `flutter build linux --debug` 成功
