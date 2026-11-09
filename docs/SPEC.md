# EmoPlay 2.0 迁移规格书（工作流各阶段 agent 的唯一决策依据）

本文档是 EmoPlay 2.0 迁移工作流的规格来源。各阶段 agent 遇到规格未覆盖的产品决策时，**默认取最接近 Kazumi 现有行为**的做法，不要自创交互；只有环境阻塞才升级提问。

- 旧版参考仓库（**只读，绝不修改**）：`/home/emo/code/mpv-emo`
- Kazumi 克隆（只读参考 + M1 起点）：`/home/emo/code/_upstream/kazumi`
- PiliPlus 克隆（只读参考，摘交互小件用）：`/home/emo/code/_upstream/piliplus`
- 新仓库：`/home/emo/code/emoplay`（全新 git 仓库，上游代码导入而非 fork）
- 配套文档：`PORT-MAP.md`（C++→Dart 映射）、`STRIP-LIST.md`（Kazumi 剥离清单）

## 1. 项目身份与品牌

| 项 | 值 |
|---|---|
| 应用名 | EmoPlay（窗口标题 `EmoPlay`，显示名 EmoPlay） |
| pubspec name | `emoplay` |
| org / applicationId | `com.emoplay`（Android）/ linux `com.emoplay.EmoPlay` |
| 版本 | 2.0.0-alpha |
| 图标 | **占位图标**（程序生成的简单矢量风 PNG），**禁止使用 Kazumi 的 logo**（Yuquanaaa 版权，非自由素材） |
| 字体 | 系统默认字体，**禁止捆绑 Mi Sans**；删除 Kazumi 的 fontFamily 全局覆写 |
| locale | 默认 zh，arb 结构预留 en（M1 只做 zh） |
| 主题 | 保留 Kazumi 的 Material 3 + DynamicColor 机制，默认深色优先 |

## 2. 技术决策（已定，不再讨论）

| 决策项 | 结论 |
|---|---|
| 骨架 | Kazumi@main（克隆时锁 commit）剥离番剧业务 |
| 播放器 | Kazumi 播放器为基底 + PiliPlus 交互小件摘取改写 |
| 播放内核 | `Predidit/media-kit` 锁 commit `83b7ca63772856e1ea0158916177e136f7b7b0be`；libmpv 由 fork 预编译包提供 |
| 状态管理 | MobX（build_runner 生成 `.g.dart`） |
| 路由 | flutter_modular（随 Kazumi） |
| Tab | 首页 / 媒体库 / 播放 / 插件 / 设置（五页） |
| 许可 | 整体 GPL-3.0；Kazumi/PiliPlus/Anime4K 版权声明保留（见 §8） |
| 数据 | JSON schema 与 1.x 逐字段一致（见 §7） |

## 3. 环境策略（宿主机零污染）

原则：宿主机只读复用；容器内补缺；一切安装在**容器自己的 rootfs**；构建后清缓存。绝不调用宿主机包管理器，绝不改宿主机配置文件，**不改 `~/.bashrc`**（home 可能与宿主共享）。

每个工具三档解析（幂等）：
1. 容器内已有 → 直接用（已确认有：gcc、g++、git、sudo）。
2. 宿主机有 → `distrobox-host-exec` 只读探测；若位于共享挂载路径可直接引用，不复制不安装。
3. 都没有（或跨边界不可用，如编译器/GTK 头文件）→ 装进容器：
   - `apt-get install -y cmake ninja-build clang libgtk-3-dev ffmpeg pkg-config`
   - Flutter SDK **3.47.9** tarball → `/opt/flutter`（先用 `findmnt /opt` 确认不是宿主挂载点；若是改 `/usr/local/emoplay-toolchain`）
   - `PUB_CACHE=/opt/pub-cache`

**环境变量约定（工作流所有 flutter/dart 命令必须显式携带）：**

```bash
export FLUTTER_ROOT=/opt/flutter   # 实际路径以 S0 探测为准,写入 /opt/emoplay-env.sh
export PUB_CACHE=/opt/pub-cache
export PATH="$FLUTTER_ROOT/bin:$PATH"
```

S0 结束时把实际生效的 env 写入 `/opt/emoplay-env.sh`（`source` 使用），并在工作流日志报告每个工具的三档解析结果。

清理阶段（S9）：`apt-get clean`、删 tarball、`flutter clean`、删 `build/`、`.dart_tool`、清空 `/opt/pub-cache`、删 `/home/emo/code/emoplay2-plan/`（内容已并入仓库 docs/）。保留：`/home/emo/code/emoplay`、`/home/emo/code/_upstream/`、`/opt/flutter`（文档写明一条删除命令）。

## 4. 关键不变量（从 1.x 平移必须逐条保留）

1. **`load-scripts=no` + 显式 scripts 选项表**：mpv 默认会自动加载 config-dir scripts/ 下所有脚本，必须显式关闭；插件脚本只经 scripts 选项表生效，**永不替换用户脚本表**，按平台拼分隔符（Linux `:`、Windows `;`）追加。
2. **写路径重定向**：watch_later/ screenshots/ shader_cache/ icc_cache/ demuxer_cache 全部落到应用数据目录；**从不写用户 mpv 配置目录**（单一事实源 redirectTarget 函数，启动与运行时共用）。
3. **导入规则三张表**：强制项（vo=libmpv/osc=no/terminal=no 等，media_kit 场景下映射为等价属性）、剥离项（include/profile/scripts/input-conf/config-dir/watch-later-dir/screenshot-directory/gpu-shader-cache-dir/icc-cache-dir/dump-stats/log-file）、重定向项；`[profile]` 段只报告不应用；screenshot-template 含 `~~` 整条丢弃。
4. **resume 语义**：`openAt(path, seconds)` 的 seek **挂起**到下一次 fileLoaded 事件才执行、**一次性消费**（后续 playlist 文件从头播）。提前 seek 会被 mpv 丢弃。
5. **Anime4K 链序表**：按源视频高度 900/1440 分组，Group A/A+A/C 的多文件精确序列照抄 `mpv-emo/src/quality/QualityProfileEngine.cpp` L82-118；HDR/HFR(≥50fps) 避让；部分安装时优雅降级；SSimSuperRes 只给真人高档。
6. **插件三段式**：`planOperation` → UI 确认 → 执行；check 模式永不覆盖文件；replace 前跑 `git status --porcelain`，有本地改动则拒绝；name 域 `[A-Za-z0-9_-]` 且 destination 防路径穿越；`.backup-<name>` 备份后原子 swap。
7. **缩略图**：缓存键 `sha1(path+mtimeMs).jpg`；两段 ffmpeg 链（`-i` 抓 Duration，预期 exit 1 → `-ss <10%时长> -frames:v 1 -vf scale=320:-2 -y`）；30s 超时强杀；无 ffmpeg 优雅降级为类型图标。
8. **画质降级**：掉帧率≥2/s 会话级自动降档；InterpolationController 探测失败→持久化 off；IccController profile 不可读→持久化 off + 恢复启动快照。
9. **EQ 链**：10 段 `equalizer=f=<freq>:t=q:w=1.4:g=<gain>,…` 拼 `af`（superequalizer 18 固定带被否决的考证注释随代码平移）；预设 flat/bass/vocal/live/custom，增益 ±12dB。

## 5. Tab 与页面结构

| Tab | 内容 | 数据来源 |
|---|---|---|
| 首页 | 最近播放、继续观看（HistoryRow 式）、快捷打开、媒体统计 | HistoryStore/LibraryStore |
| 媒体库 | 目录管理、视频/音频筛选（typeFilter all/video/audio）、排序（title/titleDesc/size/recent/path）、搜索、扫描进度+取消、缩略图网格 | LibraryStore + ThumbnailService |
| 播放 | 当前播放、播放列表、音轨/字幕面板、控制界面 | PlaybackController |
| 插件 | 内置 6 插件（uosc/uosc_danmaku/anime4k/file_browser/hdr-toys/trakt_scrobble）+ 在线源、安装/更新/删除（三段确认） | PluginManager |
| 设置 | 见 §6 分类法 | SettingsStore |

导航形态沿用 Kazumi `ScaffoldMenu`：竖屏 NavigationBar / 横屏 NavigationRail；页面状态经 RouterOutlet 保留。Ctrl+1..5 直达页；ESC 优先级链：对话框 → 播放器面板 → 全屏 → 应用。

## 6. 设置中心分类法（Kazumi 设置组件 + EmoPlay 分类）

沿用 Kazumi 的 `SettingsList/SettingsSection/SettingsTile/SettingsSliderTile/SettingsRadioSection/SettingsCategoryTile` 组件与双面板自适应（compact 断点 600×480），分类改为：

1. 常规（启动页、resumeOnReopen、库扫描参数 maxDepth/skipHidden、更新检查）
2. 播放（倍速默认、进度步长、播放重复模式、音频输出）
3. 视频与画质（contentMode/qualityTier/toneMappingMode/scaleOverride/debandMode、Anime4K 开关与档位、插值/补帧 VapourSynth 预设、ICC profile）
4. 音频（EQ 开关、预设、10 段增益滑块）
5. mpv 配置（导入向导重跑、导入决策重置、当前生效选项审计表）
6. 着色器管理（着色器目录、已装 GLSL 列表勾选、缓存清理）
7. 外观（主题色、主题模式、OLED 纯黑）
8. 快捷键（键位表展示，M7 只读展示即可）
9. 存储与缓存（数据目录、缓存大小、清理按钮）
10. 诊断（appVersion/mpvVersion/renderBackend/dataDir/configDir/logDir，全部运行时读取）
11. 关于（版本、上游声明、许可链接）

## 7. 数据 schema（与 1.x 逐字段一致，路径用 path_provider 应用支持目录）

**history.json**（上限 50 条，按 path 去重置顶）：
```json
{"version":1,"entries":[{"path":"","title":"","position":0.0,"duration":0.0,"lastPlayedAt":"2026-01-01T00:00:00.000Z"}]}
```
5s 定时器刷新 position（每次实时读当前属性防 playlist 竞态；paused 时跳过写盘）。

**library.json**：
```json
{"version":1,"directories":[],"entries":[{"path":"","title":"","type":"video|audio","size":0,"lastPlayed":null}]}
```
扫描：QDirIterator 语义 = Dart 递归（skipHidden 不下钻隐藏目录、不跟随符号链接、深度=相对路径 `/` 计数 >maxDepth 剪枝、扩展名查表 14 视频+11 音频、绝对路径去重、title 大小写不敏感排序、每 32 文件进度回调、支持取消）。重扫保留 lastPlayed。

**settings.json**：
```json
{
  "importDecision": "full|selective|standalone|skip|null",
  "dontAskAgain": false,
  "selectedFiles": [],
  "lastImportSummary": null,
  "importedAt": null,
  "quality": {"contentMode":"auto|anime|live","qualityTier":"low|medium|high","toneMappingMode":"auto|clip|mobius|reinhard|hable|gamma|linear|bt.2390","scaleOverride":null,"debandMode":"off|low|medium|high","manualShaderList":[],"interpolation":{"enabled":false,"preset":"MEMC_01|...|MEMC_06"},"icc":{"enabled":false,"profilePath":""}},
  "behavior": {"resumeOnReopen":true,"libraryMaxDepth":2,"librarySkipHidden":true},
  "music": {"equalizerEnabled":false,"equalizerPreset":"flat","equalizerGains":[0,0,0,0,0,0,0,0,0,0]}
}
```
原子写（临时文件+rename），写失败上报 lastError。

## 8. 许可处置

- 新仓库 `LICENSE` = GPL-3.0 全文（来自 Kazumi）
- `NOTICE.md`：Kazumi（Predidit 及贡献者，GPL-3.0）、PiliPlus（bggRGjQaUbCoE 及贡献者，GPL-3.0，摘取交互组件）、Anime4K（bluesky/Anime4K，随 assets/shaders/LICENSE）、EmoPlay 1.x 代码（emoeem，MIT→GPL-3.0 重授权声明）
- 保留上游文件头版权注释；删除的仅是番剧业务实现，公共框架代码的许可头保留
- `assets/shaders/`（Anime4K GLSL）连同其 LICENSE 一起保留；**删除** `assets/images/logo/`、Mi Sans、`assets/statements/`

## 9. gate 命令约定

```bash
source /opt/emoplay-env.sh
cd /home/emo/code/emoplay
flutter analyze            # 0 error 才算过（info/warning 允许存在但须无新增 error）
dart run build_runner build --delete-conflicting-outputs   # 每阶段 gate 前
flutter test               # 含平移用例
flutter build linux --debug    # S1-S7 gate
flutter build linux --release  # S8 gate
```

冒烟（S2 起）：后台启动构建产物 20 秒，读取 stderr 无未捕获异常/崩溃退出；桌面显示依赖 distrobox Wayland 直通，若无法显示则以进程存活 + 日志判定，并在报告中标注"显示待人工验收"。

## 10. 决策兜底规则

1. 规格未覆盖的 UI 细节 → 最接近 Kazumi 现状。
2. 交互细节与 1.x 冲突时 → 播放器交互优先 PiliPlus 摘取件，页面/设置交互优先 Kazumi。
3. 与不变量（§4）冲突 → 不变量赢。
4. 环境阻塞（sudo 失效、网络不可达、磁盘不足）→ 升级提问。
