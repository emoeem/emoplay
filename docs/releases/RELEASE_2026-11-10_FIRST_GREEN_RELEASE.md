# 更新说明 · 2026-11-10（首绿发布 R4）

> CI 首绿达成，第一个公开发布产物上线。R3 修复推送后，main CI 以预期签名
> `332 tests passed, 1 skipped` 一次转绿；同日打 `v2.0.0-alpha` tag 演练真实发布，
> 第一跑炸出三盏红灯（macOS 打包还在找 `Kazumi.app`、Windows 安装 Flutter 缺
> `yq`、arm64 构建缺 ALSA 头文件），第二跑只剩 Windows 编译撞出 Kazumi 时代
> 的死 include，第三跑八个 job 全绿——3 个 APK、Linux amd64/arm64 的 deb 与
> tar.gz、macOS/Windows zip 共 9 个产物已挂上 GitHub Release。同轮把 1.x
> `MpvEngine::apply` 的测试半边逐用例平移（5 条真开 libmpv 的 live 用例）、
> 设置页音频类接入 i18n。全仓 33 个测试文件 341 条用例通过（另有 1 条
> Windows 专属探测按 QSKIP 契约跳过），`flutter analyze` 0 告警。

| 项         | 值                                                                                     |
| ---------- | --------------------------------------------------------------------------------------- |
| 版本       | git `2c6bf06`（08:49 CST，R4: remaining debts；2.0.0-alpha+2000000）；发布 tag `v2.0.0-alpha` 指向 `bd36f70`（07:57 CST），GitHub Release 2026-11-10 08:13 CST 公开 |
| 平台       | 全平台产物已由 release 矩阵产出（9 资产，见一-1）；Linux 容器内实测 analyze / test / build / ldd；Windows / macOS / Android 产物未经实体机验证 |
| 自动化测试 | **33 文件 / 341 通过 + 1 平台条件跳过，全绿**（上轮 32 文件 / 332 通过 + 1 跳过，+1 文件 / +9 用例） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 3.0s)`）                    |
| CI         | main CI 三连绿：**首绿 run 42718530280**（4m12s，job 日志 `🎉 332 tests passed, 1 skipped.`，与 R3 预期签名一字不差）→ 42722128694 → 42724596082；release 矩阵演练 42720144705 ✗ → 42722139024 ✗ → **42724607274 ✓**（15m15s，GitHub Release 已发布）。R4 两个代码提交（`2598bc8` / `2c6bf06`）未推送，推送后预期 **341 passed / 1 skipped** |

## 一、首个公开发布产物（v2.0.0-alpha）

### 1.1 GitHub Release 与 9 个产物

`v*` tag 触发的全平台矩阵（`.github/workflows/release.yaml`）在演练
run 42724607274 全绿后，由收尾的 GitHub Release job（19s）自动发布。资产
清单与字节数取自 `gh api repos/emoeem/emoplay/releases`（2026-11-10 实测）：

| 资产 | 大小（字节） |
| --- | --- |
| `EmoPlay_linux_v2.0.0-alpha_amd64.deb` | 17,148,320 |
| `EmoPlay_linux_v2.0.0-alpha_amd64.tar.gz` | 20,782,458 |
| `EmoPlay_linux_v2.0.0-alpha_arm64.deb` | 15,967,744 |
| `EmoPlay_linux_v2.0.0-alpha_arm64.tar.gz` | 19,360,943 |
| `app-arm64-v8a-release.apk` | 21,146,127 |
| `app-armeabi-v7a-release.apk` | 19,833,123 |
| `app-x86_64-release.apk` | 22,113,973 |
| `EmoPlay_macos_v2.0.0-alpha.zip` | 37,325,390 |
| `EmoPlay_windows_v2.0.0-alpha.zip` | 30,725,989 |

用户感知：**Linux 用户 `sudo apt install ./EmoPlay_linux_*_amd64.deb` 直装
即可**——R3 审计钉入的 17 项 `Depends` 让最小化系统装完就能放视频；arm64
deb 同链路产出。Android 三个 ABI 的 APK、Windows 与 macOS 的 zip 首次随
tag 自动产出。

### 1.2 产物对应的提交范围（读 release 前必读）

tag `v2.0.0-alpha` 指向 `bd36f70`（`git rev-parse v2.0.0-alpha^{commit}` 实测），
**不含其后未推送的两个 R4 提交**——三盏发布红灯的修复与 Windows 死 include
的修复都在产物内，R4 的测试补充与音频页 i18n 不在（它们不改变产物行为，
随下次 tag 进入产物）。

## 二、发布管线的四盏红灯：根因与修复

演练采用「移动 tag 重跑」的方式迭代（第二次 run 的 checkout 日志显示 tag
重指到 `b9b3d2c`）。三盏红灯一次修复（`b9b3d2c`），第四盏单独修复
（`bd36f70`）：

### 2.1 macOS 打包：工程文件里的 Kazumi.app 残留

drill#1 日志：`✓ Built build/macos/Build/Products/Release/Kazumi.app
(90.9MB)` 之后 `ditto: Cannot get the real path for source
'build/macos/Build/Products/Release/EmoPlay.app'`——构建产物叫 Kazumi.app，
打包步找 EmoPlay.app。根因：M1 品牌化改名（应用名 / applicationId / 图标）
漏掉了 `macos/Runner.xcodeproj/project.pbxproj`，product 引用、RunnerTests
的 bundle id（`com.example.kazumi.RunnerTests`）与 TEST_HOST 路径仍是
Kazumi 时代的值；Linux/Windows 的对应文件改了，macOS 没改，CI 之外无处
暴露。修复（`b9b3d2c`）：pbxproj 三处 product 引用改 `EmoPlay.app`、bundle
id 改 `com.emoplay.EmoPlay.RunnerTests`、TEST_HOST 随之更新。drill#2 验证
macOS job 转绿。

### 2.2 Windows 装环境：flutter-action 解析版本文件需要 yq

drill#1 日志：`yq not found. Install it from
https://mikefarah.gitbook.io/yq`，job 15 秒即死在 Set up Flutter。根因：
`subosito/flutter-action@v2.16.0` 的 `flutter-version-file: pubspec.yaml`
在 windows-latest 上要靠 `yq` 解析版本文件，而 runner 不预装 yq。修复
（`b9b3d2c`）：Windows job 改钉 `flutter-version: '3.47.9'`，注释写明与
`pubspec.yaml` 的 `environment.flutter` 保持同步——升级 Flutter 时这是一处
要手改的耦合点（见 HANDOVER 坑 7）。

### 2.3 Linux arm64 构建：缓存未命中后暴露缺 ALSA 头

drill#1 日志：先 `Cache not found for input keys: flutter-arm64-3.47.9-Linux-`
（自建 action 需从源码装 Flutter），后 `Could NOT find ALSA (missing:
ALSA_LIBRARY ALSA_INCLUDE_DIR)`。根因：`.github/actions/flutter-arm64-setup`
的 apt 依赖清单没装 `libasound2-dev`，x64 路径靠预编译 SDK 绕过了这一步，
arm64 从源码构建时 CMake 探测 ALSA 直接失败。修复（`b9b3d2c`）：action 的
apt 清单补 `libasound2-dev` 与 `libayatana-appindicator3-dev`（托盘插件的
arm64 构建同样需要）。drill#2 验证 arm64 job 转绿。

### 2.4 Windows 编译：被剥离业务的死 include

drill#2 日志：`main.cpp(4,10): error C1083: Cannot open include file:
'app_links/app_links_plugin_c_api.h'`。根因：app_links 随深度链接业务在
Kazumi 剥离时移除（`docs/STRIP-LIST.md:37`，pubspec / lock /
generated_plugins.cmake 均无此插件），但 `windows/runner/main.cpp` 的
include 与 `SendAppLink()` 调用残留——头文件永远无法解析，Windows 编译必
炸；本地从不编 Windows，所以三轮 CI 之前无人踩到。修复（`bd36f70`）：删
include 与调用，第二实例经 `emoplay://` 唤起仍走 `ActivateExistingWindow()`，
URL 内容转发是待做功能（提交信息已记录）。

## 三、R4 代码面：语义锁定与第二页 i18n

### 3.1 mpv 引擎 apply 半边逐用例平移（5 条 live 用例，`2598bc8`）

R1/R2/R3 的对账残余之一：1.x `tests/test_mpv_engine.cpp` 的 `apply()` 半边
需要真开 libmpv，2.0 一直没有自动化覆盖。CI 依赖修全后 runner 有了真
libmpv（R3 起 equalizer 用例的先例），本轮把该半边逐用例平移进
`test/mpv_player_properties_test.dart`（文件头注释带对账表）：

| 1.x 槽位 | 2.0 用例 |
| --- | --- |
| `propertyRoundTrip` | `propertyRoundTripDispatch` |
| `scriptAutoloadDisabledByDefault` | `applyPresetLandsOnLiveCore` |
| `observedPropertySignals` | `observedPropertySignalsAvailableAndUnavailable` |
| `unavailablePropertiesEmitClearedValues` | `unavailableIdleCoreReadsClearedValues` |
| `commandErrorEmitsErrorSignal` | `commandErrorSurfacesThroughLogStream` |
| `initializeSmoke` | 吸收进每条 live 用例（Player 构建 + idle 读回） |
| `doubleInitializeRejected` | **不移植**：2.0 无引擎单例，每次会话构建一个 Player、apply 无状态——理由记录在文件头注释 |

用户感知：1.x 的 mpv 属性应用语义（布尔走 MPV_FORMAT_FLAG、脚本选项追加
不覆盖等）从此被测试钉死，未来重构 mpv 集成层时回归会当场暴露。

### 3.2 设置页音频类接入 i18n（第二页，`2c6bf06`）

页签壳（R3 第一页）之后，音频设置页成为第二个从 arb 取字符串的页面：
app bar / 分区标题 / 瓦片标题与描述 / 均衡器关闭提示（开关切换时实时翻转）
/ 预设下拉的单一来源标签表 `audioEqualizerPresetLabels` / 十个通用单位频段
行（`31 Hz`..`16k Hz`）。默认语言仍 zh-Hans-CN，**中文界面一个字都没变**；
en arb 同步补键。迁移链由新文件 `test/audio_settings_l10n_test.dart` 4 条
用例锁定（zh + en 双语言）：该页可注入 `MusicController`，测试挂载的是
真实页面组件——不走路由树、不初始化 MediaStores、不碰平台通道，变异留在
内存（构造器语义），链路证明力与 R3 的页签壳测试同级。

### 3.3 README 补发布产物章节（`2c6bf06`）

中英双语 README 各增「发布产物 / Release artifacts」一节：`v*` tag → 全平台
矩阵 → 产物挂 GitHub Release 的链路说明、按平台的产物表、Linux deb 直装
建议与「APK / Windows 产物未签名」提示；「正在做整体验收」的现状句改为
「CI 门禁全绿 + 发布矩阵演练通过」。从源码构建 Linux 的运行期依赖（libva /
libvdpau / libpulse 闭包，指向 pr.yaml 装步）一并写明。

## 四、已知取舍

- **CI 首绿签名是 332 而非 341**：首绿 run 42718530280 验证的是 R3 的
  提交集；R4 新增的 9 条用例尚未推送，推送后的 CI 预期签名
  **341 passed / 1 skipped**（本地 341+1 实测口径与 CI 历史口径自洽：
  341 = 332 + 5（mpv live）+ 4（audio l10n），33 = 32 + 1 个新文件）。
- **alpha 被发布为非预发布的 Latest**：`release.yaml` 的
  `softprops/action-gh-release@v2` 步未设 `prerelease` 参数（默认 false），
  v2.0.0-alpha 以正式版语义占据 Latest 位。对用户行为的影响当前是正确的
  （2.0 的 UpdateChecker 查 `releases/latest`，用户不会收到「有新版」提示），
  但后续打 beta/rc 时应决策是否给 workflow 加 `prerelease` 参数——已列入
  代码侧待办。
- **产物验收停留在「job 绿 + 资产在 + 字节数」级**：9 个资产均未做逐平台
  安装/解压验证（Windows / macOS / Android 实体机验证与 R1–R3 一致仍是
  ☐）；Linux deb 的安装级验证此前在容器内做过（R3），发布产物的 deb 与
  其同脚本同参数产出。
- **APK 与 Windows 产物未签名**、iOS 仍在发布矩阵外、AppImage 未做——
  与既有已知限制一致，本轮无变化。
- **打包脚本注释「115-library ldd closure」口径**维持 R3 状态：核心覆盖
  声明已独立复现成立，115 本身标注为未复现、待施工方确认口径。
- **i18n 只有页签壳与音频设置两处**：其余页面字符串迁移仍在路线图 ☐。
