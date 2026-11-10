# Changelog

格式参考 Keep a Changelog；预发布序列 alpha → beta → rc。EmoPlay 2.0 是
1.x（[mpv-emo](https://github.com/emoeem/mpv-emo)，C++/Qt6）在 Flutter 上的
重写：迁移决策依据 `docs/SPEC.md`，文件级映射见 `docs/PORT-MAP.md`，
Kazumi 剥离清单见 `docs/STRIP-LIST.md`。1.x 的版本历史见旧仓库的
`CHANGELOG.md`。

## [Unreleased] - 2026-11-10（面板观感轮）

### Fixed

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

### Added

- **设置 → 主题「使用系统字体」开关**（默认开，`useSystemFont`）：关闭后
  切换到内置 MiSans（Kazumi 同款）；两条路径都显式携带 CJK 兜底
  （Noto Sans CJK SC / Noto Sans SC / sans-serif），fontFamily 置空也
  不再信任 fontconfig 猜字体；静态主题切换时重发射 setTheme（否则非
  动态配色下开关不生效）。SPEC §1 字体行同步。
- **音频诊断探针** `test/audio_probe_test.dart`：针对「无声」报告，fixture
  存在才真跑（runner 上缺失即早退通过）；双趟探测 default ao 与 pinned
  ao=pulse。本轮实测 pinned 趟 `AO: [pulse] 44100Hz stereo 2ch float`。

### Changed

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

### 验证

- `flutter analyze` 0 告警；`flutter test` 34 文件 342 用例全绿（1 skip
  维持：Windows-only probe）；`flutter build linux --debug` 通过；ldd
  审计 0 缺失。Android assembleDebug 本轮未重跑（无 Android 原生改动）。
- CI 结论本窗口不可测：`gh run list` 两次连接 EOF（api.github.com 不可达）；
  `d446bb8` / `8ed84c4` 未推送，推送后预期签名 342 passed / 1 skipped。

## [Unreleased] - 2026-11-10（移动端播放修复轮）

### Fixed

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

### Added

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

### Changed

- 播放面板视觉：上下渐变遮罩、紧凑图标按钮（40px 约束）、进度条与音量条
  细轨化（trackHeight 3 / thumb 6）。
- 首页：历史行改缩略图卡片（16:9 缩略图帧 + 进度条 + 圆角悬停卡，缩略图
  复用 ThumbnailService）；不小于 720px 宽度时快捷动作与标题同行。
- 媒体库：搜索框改胶囊填充样式；网格卡片悬停高亮描边。
- Android 构建接入中国镜像（本机 `dl.google.com` / `storage.googleapis.com`
  不可达）：settings.gradle / build.gradle 增加 `storage.flutter-io.cn`
  （download.flutter.io 镜像）、腾讯云与阿里云 maven 前置，
  google()/mavenCentral() 保留兜底。

### 验证

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
