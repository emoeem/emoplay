# EmoPlay

<div align="center">

**基于 mpv（media-kit/libmpv）的本地媒体播放器 · Flutter 重写版**

*A local media player built on mpv (media-kit/libmpv), rewritten in Flutter.*

[![License](https://img.shields.io/badge/license-GPL--3.0-bd93f9)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.9-41cd52)](https://docs.flutter.dev/)
[![libmpv](https://img.shields.io/badge/libmpv-0.37%2B-ff5555)](https://mpv.io/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Android-50fa7b)](#构建)

简体中文 | [English](#english)

</div>

---

## 项目定位

EmoPlay 播放**你磁盘上已有的**视频和音乐：没有账号、没有在线番剧源、没有遥测。
它以 mpv 为播放内核（通过 [media-kit](https://github.com/media-kit/media-kit) 的
libmpv 预编译包），界面为 Flutter/Material 3，并把 [EmoPlay 1.x](https://github.com/emoeem/mpv-emo)
（C++/Qt6）的播放行为语义与 JSON 数据格式逐字段带到了 2.0：

- **数据兼容**：1.x 的 `history.json` / `library.json` / `settings.json`
  放进应用数据目录即可直接使用（schema 契约见 `docs/SPEC.md` §7，
  兼容性由 `test/data_compat_spec7_test.dart` 锁定）。
- **mpv 配置兼容**：首启扫描用户的 mpv 目录（`~/.config/mpv` 等），mpv.conf /
  input.conf / 脚本 / 着色器按三张导入规则表（强制 / 剥离 / 重定向）迁移，
  **绝不写回用户的 mpv 配置目录**。
- **断点续播**：进度按 path 去重置顶（上限 50 条），resume seek 挂起到下一次
  file-loaded 才执行，与 1.x 语义一致。

当前版本 **2.0.0-alpha**：迁移工程已按里程碑全部完成（骨架 → 播放 → 本地媒体 →
媒体库/历史 → mpv 兼容 → 画质 → 插件/设置/音乐），CI 门禁全绿，`v2.0.0-alpha`
全平台发布矩阵已在 GitHub Actions 演练通过（产物见下方[发布产物](#发布产物)）。

## 功能清单

| | |
|---|---|
| 🎬 **播放核心** | libmpv 全格式解码、音轨/字幕面板、外挂字幕、播放列表、倍速、键盘/手势控制、Android PiP（画中画）、DLNA 投屏、Linux 外部播放器接管 |
| 🎨 **画质引擎** | 内容自适应画质档位（动画/真人 × 分辨率分组）、Anime4K 着色器链（900/1440p 链序表，缺文件优雅降级）、SSimSuperRes 真人高档、HDR tone-mapping、插值/补帧（VapourSynth 预设，掉帧自动降档）、ICC 显示配置 |
| 🖼️ **媒体库** | 多目录递归扫描（isolate 后台）、视频/音频筛选、排序与搜索、ffmpeg 两段式缩略图（sha1 缓存键，无 ffmpeg 自动降级）、扫描进度与取消 |
| 🎵 **音乐模式** | 纯音频识别、.lrc 歌词逐行高亮、10 段均衡器 + 预设（flat/bass/vocal/live/custom） |
| 📜 **历史与首页** | 最近播放、继续观看、媒体统计；5s 心跳刷新进度，暂停时不写盘 |
| 🧩 **插件系统** | manager.json 清单、内置 6 插件（uosc / uosc_danmaku / anime4k / file_browser / hdr-toys / trakt_scrobble）+ 在线源、git 安装/更新/删除、三段确认、**本地改动永不覆盖** |
| ⚙️ **设置中心** | 11 类：常规 / 播放 / 视频与画质 / 音频 / mpv 配置（导入审计）/ 着色器管理 / 外观 / 快捷键 / 存储 / 诊断 / 关于 |

五个页签：首页 · 媒体库 · 播放 · 插件 · 设置；竖屏 NavigationBar / 横屏
NavigationRail，`Ctrl+1..5` 直达。

## 构建

依赖：[Flutter SDK **3.47.9**](https://docs.flutter.dev/)（版本锁定见
`pubspec.yaml` 的 `environment.flutter`）、Linux 桌面构建需要
`clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev`。

```bash
git clone https://github.com/emoeem/emoplay.git
cd emoplay
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 MobX *.g.dart
flutter analyze                                            # 0 error 才算过
flutter test                                               # 含 1.x 平移用例

# 平台产物
flutter build linux --release                              # build/linux/x64/release/bundle
flutter build windows --release
flutter build macos --release
flutter build apk --release --split-per-abi
```

运行时说明：libmpv 由 media-kit 的预编译包提供（锁 commit
`83b7ca6…`，见 `pubspec.yaml`），无需系统安装 mpv；缩略图与帧插值分别
依赖系统 PATH 中的 `ffmpeg` / VapourSynth，缺失时对应功能自动降级，不影响播放。
从源码构建 Linux 时，除上列构建工具外，运行期还需 libmpv 的依赖闭包
（libva / libvdpau / libpulse 等，完整清单见 `.github/workflows/pr.yaml`
的 "Install native build tools" 步）。

### 发布产物

`v2.0.0-alpha` 起，`v*` tag 触发全平台发布矩阵（`.github/workflows/release.yaml`），
产物直接挂到 GitHub Release：

| 平台 | 产物 |
|---|---|
| Linux | `EmoPlay_linux_*_amd64.deb` / `_arm64.deb`、同名 `tar.gz` |
| Android | `app-*-release.apk`（arm64-v8a / armeabi-v7a / x86_64） |
| Windows | `EmoPlay_windows_*.zip` |
| macOS | `EmoPlay_macos_*.zip` |

Linux 建议直接安装 deb（`sudo apt install ./EmoPlay_linux_*_amd64.deb`）：
依赖闭包已审计钉入 `Depends`，最小系统可直装。APK 与 Windows 产物目前
**未签名**（详见 `CHANGELOG.md`「已知限制」）。

CI（GitHub Actions，见 `.github/workflows/`）：push/PR 只跑单 job 的
Linux analyze + test + build；Windows/macOS/Android/Linux arm64 全平台打包
仅由 `v*` tag 触发（`.github/workflows/release.yaml`）。

## 上游声明

本项目**不是** Kazumi 的 fork，而是全新仓库：导入 Kazumi 骨架（GPL-3.0）后
剥离全部番剧业务，再平移 1.x 行为语义。各上游的版权与许可声明见
[NOTICE.md](NOTICE.md)，要点：

| 来源 | 许可 | 用途 |
|---|---|---|
| [Kazumi](https://github.com/Predidit/Kazumi)（Predidit 及贡献者） | GPL-3.0 | 应用骨架、播放器栈、设置组件、着色器服务、平台壳（导入于 commit `7265274`） |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)（bggRGjQaUbCoE 及贡献者） | GPL-3.0 | 播放器交互小件摘取改写 |
| [Anime4K](https://github.com/bloc97/Anime4K)（bloc97） | MIT（`assets/shaders/LICENSE`） | `assets/shaders/` 的 GLSL 着色器组，原样保留 |
| EmoPlay 1.x（emoeem） | MIT → **GPL-3.0** | 行为语义与 JSON schema 平移，整体重授权为 GPL-3.0 |

剥离清单与文件级映射见 `docs/STRIP-LIST.md` / `docs/PORT-MAP.md`，来源记录见
`docs/UPSTREAM.md`。

## 文档

- `docs/SPEC.md` —— 迁移规格（不变量、数据 schema、许可处置、决策兜底）
- `docs/PORT-MAP.md` —— C++/Qt → Dart/Flutter 文件级映射
- `docs/STRIP-LIST.md` —— Kazumi 剥离清单
- `docs/UPSTREAM.md` —— 上游导入记录
- `CHANGELOG.md` —— 版本历史

## 许可

本项目以 [GPL-3.0](LICENSE) 发布；第三方组件声明见 [NOTICE.md](NOTICE.md)。
应用图标为程序生成的占位图；不捆绑任何品牌字体。

---

<a id="english"></a>

## English

### Positioning

EmoPlay plays the videos and music **already on your disk**: no accounts, no
online anime sources, no telemetry. mpv is the playback core (via the prebuilt
libmpv packages of [media-kit](https://github.com/media-kit/media-kit)), the UI
is Flutter/Material 3, and the playback semantics and JSON data formats of
[EmoPlay 1.x](https://github.com/emoeem/mpv-emo) (C++/Qt6) are carried over
field-for-field:

- **Data compatibility**: drop 1.x `history.json` / `library.json` /
  `settings.json` into the app-data directory and they just work (schema
  contract in `docs/SPEC.md` §7, locked by `test/data_compat_spec7_test.dart`).
- **mpv config compatibility**: on first start your mpv directory
  (`~/.config/mpv` etc.) is scanned; mpv.conf / input.conf / scripts /
  shaders migrate through the three import rule tables (forced / stripped /
  redirected), and **your mpv config directory is never written to**.
- **Resume playback**: history entries are deduped by path (50 max); the
  resume seek is deferred until the next file-loaded event, same as 1.x.

Current version **2.0.0-alpha**: the milestone migration (skeleton → player →
local files → library/history → mpv compat → quality → plugins/settings/music)
is complete, the CI gate is green, and the `v2.0.0-alpha` full-platform release
matrix has been exercised on GitHub Actions (artifacts under
[Release artifacts](#release-artifacts)).

### Features

| | |
|---|---|
| 🎬 **Playback** | full-format decoding via libmpv, audio/subtitle tracks, external subtitles, playlists, speed control, keyboard/gesture control, Android PiP, DLNA cast, Linux external-player handoff |
| 🎨 **Quality engine** | content-adaptive tiers (anime/live-action × resolution groups), Anime4K shader chains (900/1440p chain tables, graceful degradation on partial installs), SSimSuperRes for high-tier live action, HDR tone-mapping, frame interpolation (VapourSynth presets, auto step-down on dropped frames), ICC display profiles |
| 🖼️ **Library** | multi-directory recursive scan (background isolate), video/audio filters, sorting and search, two-stage ffmpeg thumbnails (sha1 cache keys, degrades without ffmpeg), scan progress and cancel |
| 🎵 **Music mode** | audio-only detection, .lrc lyric highlighting, 10-band equalizer with presets (flat/bass/vocal/live/custom) |
| 📜 **History & home** | recent plays, continue watching, library stats; a 5 s heartbeat refreshes position and skips writes while paused |
| 🧩 **Plugins** | manager.json manifests, 6 builtin plugins (uosc / uosc_danmaku / anime4k / file_browser / hdr-toys / trakt_scrobble) plus online sources, git-based install/update/remove with a three-step confirm, **local modifications are never overwritten** |
| ⚙️ **Settings** | 11 categories: general / playback / video & quality / audio / mpv config (import audit) / shader management / appearance / shortcuts / storage / diagnostics / about |

Five tabs: Home · Library · Player · Plugins · Settings; NavigationBar in
portrait, NavigationRail in landscape, `Ctrl+1..5` jumps straight to a tab.

### Build

Requirements: [Flutter SDK **3.47.9**](https://docs.flutter.dev/) (pinned in
`pubspec.yaml` under `environment.flutter`); Linux desktop additionally needs
`clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev`.

```bash
git clone https://github.com/emoeem/emoplay.git
cd emoplay
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates MobX *.g.dart
flutter analyze                                            # must report 0 errors
flutter test                                               # includes the 1.x ported cases

# Platform targets
flutter build linux --release                              # build/linux/x64/release/bundle
flutter build windows --release
flutter build macos --release
flutter build apk --release --split-per-abi
```

Runtime notes: libmpv ships prebuilt through media-kit (pinned commit
`83b7ca6…`, see `pubspec.yaml`) — no system mpv needed. Thumbnails and frame
interpolation use `ffmpeg` / VapourSynth from PATH when available and degrade
gracefully without them; playback is unaffected. Building Linux from source
also needs libmpv's runtime dependency closure beyond the build tools listed
above (libva / libvdpau / libpulse etc.; the full list lives in the
"Install native build tools" step of `.github/workflows/pr.yaml`).

### Release artifacts

From `v2.0.0-alpha` on, a `v*` tag triggers the full-platform release matrix
(`.github/workflows/release.yaml`); artifacts are attached to the GitHub
Release:

| Platform | Artifacts |
|---|---|
| Linux | `EmoPlay_linux_*_amd64.deb` / `_arm64.deb` plus matching `tar.gz` |
| Android | `app-*-release.apk` (arm64-v8a / armeabi-v7a / x86_64) |
| Windows | `EmoPlay_windows_*.zip` |
| macOS | `EmoPlay_macos_*.zip` |

On Linux prefer the deb (`sudo apt install ./EmoPlay_linux_*_amd64.deb`):
the dependency closure has been audited and pinned into `Depends`, so it
installs on a minimal system. APK and Windows builds are currently
**unsigned** (see the 已知限制 / known-limitations section of
`CHANGELOG.md`).

CI (GitHub Actions, see `.github/workflows/`): pushes/PRs run a single-job
Linux analyze + test + build gate; the Windows/macOS/Android/Linux arm64
packaging matrix is tag-triggered only (`v*`, in
`.github/workflows/release.yaml`).

### Upstream statement

This is **not** a Kazumi fork but a fresh repository: the Kazumi skeleton
(GPL-3.0) was imported with all anime-business code stripped, then 1.x
semantics were ported on top. Copyright and license notices per upstream live
in [NOTICE.md](NOTICE.md):

| Source | License | Used for |
|---|---|---|
| [Kazumi](https://github.com/Predidit/Kazumi) (Predidit and contributors) | GPL-3.0 | app skeleton, player stack, settings components, shader service, platform shells (imported at commit `7265274`) |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) (bggRGjQaUbCoE and contributors) | GPL-3.0 | adapted player interaction widgets |
| [Anime4K](https://github.com/bloc97/Anime4K) (bloc97) | MIT (`assets/shaders/LICENSE`) | the GLSL set under `assets/shaders/`, kept verbatim |
| EmoPlay 1.x (emoeem) | MIT → **GPL-3.0** | behavior semantics and JSON schemas, relicensed as a whole under GPL-3.0 |

Strip list and file-level mapping: `docs/STRIP-LIST.md` / `docs/PORT-MAP.md`;
import record: `docs/UPSTREAM.md`.

### License

Released under the [GPL-3.0](LICENSE); third-party notices in
[NOTICE.md](NOTICE.md). The app icon is a generated placeholder; no branded
fonts are bundled.
