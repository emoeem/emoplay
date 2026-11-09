# Changelog

格式参考 Keep a Changelog；预发布序列 alpha → beta → rc。EmoPlay 2.0 是
1.x（[mpv-emo](https://github.com/emoeem/mpv-emo)，C++/Qt6）在 Flutter 上的
重写：迁移决策依据 `docs/SPEC.md`，文件级映射见 `docs/PORT-MAP.md`，
Kazumi 剥离清单见 `docs/STRIP-LIST.md`。1.x 的版本历史见旧仓库的
`CHANGELOG.md`。

## [2.0.0-alpha] — 2026-11-10（未发布）

迁移工程 M1–M8 全部里程碑产物：Kazumi 骨架导入并剥离番剧业务，1.x 行为
语义逐条平移，数据 schema 与 1.x 逐字段一致。

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
  CI 改造——push/PR 仅单 job Linux analyze+test+build，全平台打包矩阵
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
  迁移路线图 `docs/UPGRADE_ROADMAP_2026-11-10.md`（M0–M8 ✅+提交哈希、
  R1/R2 收尾轮次、未做项 ☐ 清单、验收标准与贯穿约定）。

- **红灯清零（R3）**：Linux deb `Depends` 从 2 项补到 17 项——GTK 运行库
  显式钉入（`libgtk-3-0t64`），不再依赖 tray 包侧链隐式捎带，音频输出 /
  硬解 / GL 视频输出运行库齐备（`7052260`；覆盖经 `apt-cache depends
  --recurse` 审计：bundle ldd 闭包的 104 个提供包全部落在 17 包递归闭包
  251 包内，差集为空）；页签壳成为第一个接入 i18n 的页面——五个页签标签
  经 `menuTabLabels()` 单一来源分发（竖屏 NavigationBar 与横屏
  NavigationRail 同源，文案不可能漂移）、「再按一次退出应用」toast 换
  `AppLocalizations`，迁移链由 `test/menu_l10n_test.dart` 3 用例端到端
  锁定，默认语言仍 zh-Hans-CN、中文界面零变化（`c943414`）；媒体库响应性
  守卫 `test/performance_guards_test.dart` 3 用例（取消扫描毫秒级停且部分
  结果保留、进度按节流步触发不逐文件刷屏、flock 实证缩略图至多一个 ffmpeg
  子进程，与 1.x 单 worker 线程形状一致；isolate 分片多开经评估不采，
  理由记录在测试文件头注释）。

### Fixed

- CI 自建仓起零 run：`.github/workflows/pr.yaml` 触发分支写成 `master` 而仓库
  分支是 `main`，每次推送被静默跳过（`916c2d6` 改为 `main`）。
- CI 首跑红灯（run 42706655830）：`ubuntu-latest` 缺 VA/VDPAU 运行库，
  media_kit 捆绑的 `libmpv.so.2` 加载失败（`libva-drm.so.2: cannot open
  shared object file`），两条真开 libmpv 核心的均衡器用例失败；`3379d7a`
  将原生依赖安装步挪到 `flutter test` 之前并补装 `libva2 libva-drm2
  libva-x11-2 libva-wayland2 libvdpau1`（`release.yaml` 同步）。
- CI 第二跑红灯（run 42712702494）：同一批用例报 `libpulse.so.0: cannot
  open shared object file`——dlopen 每次只报第一个缺失依赖，R2 补的
  VA/VDPAU 只是直系依赖的第一层；`7debc83` 按 `readelf -d` 实测
  `libmpv.so.2` 全部直系 NEEDED 后向 pr.yaml / release.yaml 一次补装
  14 个运行库（`libpulse0 libxv1 libegl1 libgbm1 libdrm2 libunwind8
  liblcms2-2 libarchive13t64 libasound2t64 libdbus-1-3 libsndfile1
  libmpg123-0t64 libopus0 libogg0`；第二层编解码库交给发行版依赖图，
  不按随发行版变名的 soname 钉死），并把 pr.yaml 步序改为 构建 →
  `ldd libmpv.so.2 | grep 'not found'` 审计（任一缺失即红灯并列全清单）→
  测试——依赖缺口从此一次列全，不再逐轮烧 CI 分钟数。

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
