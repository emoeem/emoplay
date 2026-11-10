# HANDOVER · EmoPlay 2.0 交接现状

| 项     | 值                                                                          |
| ------ | --------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-11 R6 打磨轮之后）                                           |
| 日期   | 2026-11-11（最后实质性更新）                                                 |
| 适用版本 | git `e1a2df0` + R6 打磨工作区改动（`988122f` / `e1a2df0` 与打磨改动均未推送；origin/main 停在 `63d9f59`） |
| 相关   | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[docs/README.md](README.md) |

## 现状一句话

M1-M8 迁移主流程、R1-R4 四轮收尾、R5 两小轮（移动端播放修复 / 面板观感）
与 R6 打磨轮（AppImage 打包 / Kazumi 空态与徽章对齐 / README 对账）全部
完成：Kazumi 骨架上重建的 Flutter/mpv 本地播放器功能对等（播放 / 本地
媒体 / 媒体库 / 历史 / mpv 兼容导入 / 画质引擎 / 插件 / 11 类设置 / 更新
检查），**CI 首绿已达成**（run 42718530280，`332 tests passed, 1 skipped`），
**v2.0.0-alpha 已公开发布**（tag 指向 `bd36f70`，GitHub Release 9 资产）；
本地 35 个测试文件 345 用例全绿（R6 实测，含 3 个新 Kazumi 对齐守护用例）、
analyze 0 告警；origin/main 停在 `63d9f59`，`d446bb8` / `8ed84c4` /
`988122f` / `e1a2df0` 与打磨改动待推送（推送后预期 CI 签名
**345 passed / 1 skipped**），版本仍是 2.0.0-alpha。

## 最近实质性变更（R6·打磨，2026-11-11）

两个已提交（`988122f` 卫生与依赖收敛、`e1a2df0` AppImage 打包）+ 本轮
UI 打磨与 README 对账（工作区改动，随工作流统一 checkpoint 提交）。

- AppImage 打包（`e1a2df0`）：`.github/scripts/package-appimage.sh`
  （linuxdeploy；amd64 extract-and-run 冒烟实测通过，arm64 仅 CI 可验），
  release.yaml 挂 `*.AppImage`。
- Kazumi 对齐（仅样式层）：关于页「GPL-3.0 许可证」tile 从 Kazumi 仓库
  LICENSE 改指本项目（`about_page.dart`，Kazumi 同槽位本就链自家仓库）；
  首页 / 播放页 / 媒体库空态按钮从裸 `FilledButton` 换成已平移的
  `StateActionButton(.tonal)`（64×48 药丸，`state_presentation.dart`）；
  插件页「已定制」徽章改 `errorContainer` 容器对（旧硬编码深棕两主题下
  不可读）、次要文案改 `bodySmall + onSurfaceVariant` 弱化。
- 新增守护测试 `test/kazumi_alignment_ui_test.dart`（3 用例：许可证 tile
  真链接断言经 UrlLauncherPlatform 假体捕获、首页 / 媒体库空态按钮 idiom）。
- README 对账：功能清单与实际对齐（设置行补更新检查）、构建依赖补
  `libasound2-dev`（ALSA 头，与 pr.yaml 装步一致）、发布产物表补 AppImage、
  新增「截图」占位说明（GUI 截图待桌面空闲窗口，不产占位假图）、上游
  声明逐项核实（Kazumi `7265274` / media-kit `83b7ca6…` / Anime4K MIT）。
- 门禁实测（R6）：`flutter analyze` 0 告警；`flutter test` 35 文件
  **345 通过 / 1 skipped** 全绿。Linux debug 构建未在本轮重跑（纯样式 +
  文档改动，工作流收尾会跑完整 gate）。

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
6. **打包产物别留在仓库根**：`package-linux.sh` 把 deb/tar.gz/打包目录写在
   当前目录且不在 `.gitignore` 里 - 容器内验证后删掉再提交，CI 里靠
   release.yaml 的 upload-artifact 路径收集。
7. **品牌化改名要跨全平台目录核对**：M1 改了应用名/applicationId，但
   `macos/Runner.xcodeproj/project.pbxproj` 的 Kazumi.app 引用漏网，直到
   发布演练才在 CI 炸出（drill#1）；改平台工程文件时逐平台 grep 旧品牌名
   （Kazumi / com.example.kazumi）再收工。
8. **发布语义三件事**：(a) `v2.0.0-alpha` 已是公开的 Latest release - 再演练
   要先删 release 与 tag，且移动 tag 重跑会连烧三次矩阵分钟数（本轮
   46 分钟+）；(b) **发布产物对应 tag 指向的提交，不是 main HEAD** - 推送
   R4 后不重打 tag 就不会有新产物；(c) Windows 上 flutter-action 的
   `flutter-version-file` 需要 yq（runner 不预装），版本钉在
   release.yaml（升级 Flutter 时与 `pubspec.yaml` 同步手改）。`8ed84c4`
   起已转正：Windows job 前置 `choco install yq`，版本恢复
   `flutter-version-file: pubspec.yaml` 单一来源，升级 Flutter 只改
   `pubspec.yaml`。
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

## 接手第一步清单

1. `source /opt/emoplay-env.sh && cd /home/emo/code/emoplay && flutter analyze && flutter test`
    - 预期 0 告警 + 345 通过 / 1 skipped（35 文件，R6 实测底数），达不到先查环境再查代码。
2. `git fetch origin && git log origin/main..HEAD --oneline` 与
   `gh run list -R emoeem/emoplay --limit 5`（gh 需要外网，收网窗口内
   api.github.com 不可达） - 确认 `d446bb8` / `8ed84c4` / `988122f` /
   `e1a2df0` 与本轮打磨改动是否已推送、推送后 CI 是否
   **345 passed / 1 skipped**；红灯按坑 2 的归因链处理。
3. 通读 [SPEC.md](SPEC.md) §4 不变量与 [PORT-MAP.md](PORT-MAP.md) 头部铁律。
4. 待办从 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) §四
   未做项清单取（发布产物实体机验证 → prerelease 语义 → i18n 第三页 →
   签名/公证 → 性能实测；其中 AppImage 打包已在 R6 `e1a2df0` 落地，
   路线图 §四-108 的勾选态以路线图下次收网为准），以及
   [最新工作报告 §6](reports/WORK_REPORT_2026-11-10_PANEL_LOOK.md)
   的优先级建议。
5. 改完代码跑 SPEC §9 gate（build_runner → analyze → test → build linux）。

## 路线图

路线图的权威来源是 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)
（M0-M8 ✅+提交哈希、R1-R4 收尾轮次、未做项 ☐、验收标准与贯穿约定）；
逐里程碑的内容细节另见 [CHANGELOG.md](../CHANGELOG.md) 的 2.0.0-alpha 小节，
轮次结构与积压清单见 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四。
