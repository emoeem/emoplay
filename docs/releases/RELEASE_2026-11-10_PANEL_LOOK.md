# 更新说明 · 2026-11-10（面板观感 R5）

> 播放页两处「整页失效」修掉了：播放中快捷键全灭、导航浮层压在视频上。
> 根因都不在播放器本身，而是一个永远没人聚焦的焦点节点和一次 `&&` 短路。
> 字体观感定案：M1 删除内置字体引发的楷体事故，按 Kazumi 的 useSystemFont
> 设计端到端收尾（默认系统字体 + 显式 CJK 兜底 + 设置开关）。播放面板上下
> 两条按 Kazumi 逐槽位重组，手机与桌面共用一套组合。发布矩阵九个 job 补齐
> 超时上限，Windows 版本恢复 pubspec 单一来源。34 文件 342 用例全绿。

| 项         | 值                                                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `8ed84c4`（2026-11-11 01:11 CST，R5: ci timeouts + flutter-version-file）。本轮五个提交（`ec1c91e` / `aeda939` / `63d9f59` / `d446bb8` / `8ed84c4`）落在 11-11 00:19-01:11 CST，文档沿用 2026-11-10 夜间窗口命名 |
| 平台       | Linux 容器内实测 analyze / 全量测试 / Linux debug 构建 / ldd 审计 / 音频探针；Android 本轮未重跑 assembleDebug（本轮无 Android 原生改动）；Windows / macOS / Android 待 CI 与实体机验证 |
| 自动化测试 | **34 文件 / 342 通过 + 1 平台条件跳过，全绿**（上轮 33 文件 / 341 通过 + 1 跳过；+1 文件 / +1 用例 = 音频诊断探针）               |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 5.7s)`）                                                              |
| CI         | 本窗口不可测：`gh run list -R emoeem/emoplay` 两次连接 EOF（api.github.com 不可达，01:18 / 01:22 CST 实测）；`d446bb8` / `8ed84c4` 未推送。推送后预期签名 **342 passed / 1 skipped**（探针用例在 runner 上因 fixture 缺失按早退通过） |

## 一、字体定案：从楷体事故到 Kazumi 的系统字体设计

### 1.1 事故链与两层修复

结论：默认字体是**系统字体**；设置 → 主题提供「使用系统字体」开关（默认开），
关闭后切换到内置 MiSans。无论哪条路，CJK 兜底都显式钉死，不再信任
fontconfig 的猜字体。

- **第一层（`aeda939`，恢复字体）**：M1 剥离 Kazumi 业务时把内置字体一并
  删掉、主题未设 fontFamily（CHANGELOG 2.0.0-alpha 小节「系统默认字体，无
  Mi Sans」）。在部分 Linux 环境里 fontconfig 把中文 dump 到 LXGW ZhenKai
  （楷体风格），观感「像坏了」。修复恢复 Kazumi 的 MiSans-Regular.ttf
  （8,122,324 字节，`pubspec.yaml:113`-`116` 声明 family
  `MI_Sans_Regular`）并挂到全局主题。
- **第二层（`63d9f59`，设计对齐）**：恢复 MiSans 后用户报告「字体仍然不
  对」，期望值其实是系统字体。修复把 Kazumi 的 useSystemFont 设计端到端
  实现：
  - `lib/bean/settings/theme_provider.dart:8`-`13`：`kAppFontFamily` =
    MiSans；`kAppFontFamilyFallback` 显式钉 `Noto Sans CJK SC` /
    `Noto Sans SC` / `sans-serif`。**fontFamily 为空也必须带显式 CJK 兜底**
    ：这正是楷体事故的根因，兜底列表是防止 fontconfig 重新猜错的那道闸；
  - `lib/services/storage/settings_keys.dart:212`-`216`：`useSystemFont`
    默认 `true`（系统字体）；
  - `lib/pages/settings/theme_settings_page.dart:231`-`245`：「使用系统字
    体」开关；切换后对静态主题重发射一次 `setTheme`（静态 light/dark
    ThemeData 只在 setTheme 时重建，漏掉这一步开关在非动态配色下不生效，
    提交信息记录的坑）；
  - `lib/app_widget.dart` 三条 ThemeData 路径（静态 light/dark、动态配色
    light/dark）全部携带 fontFamily；
  - `docs/SPEC.md:20` 字体行同步改写为该设计。

### 1.2 为什么默认系统字体

规格未覆盖字体默认值，按兜底规则取最接近 Kazumi 现状（SPEC §10）：Kazumi
的 useSystemFont 默认就是系统字体，内置字体是可选项而非强制。对用户的实际
意义：桌面跟随系统字体偏好（HiDPI / 多语言环境不吃亏），楷体事故不再可能
复发（系统字体路径同样带着显式 CJK 兜底）；MiSans 资产（8 MB）仍在包内，
偏好 Kazumi 观感的用户关掉开关即得。

## 二、播放页两处「整页失效」的根因（`ec1c91e`）

### 2.1 播放中快捷键全灭

现象：进入播放页后键盘快捷键无响应。根因：早期键盘处理器把「是否处理」
门在 primaryFocus 位于 `keyboardFocus` 内。那是面板自建的 Focus 节点，
**没有任何交互会让它成为 primaryFocus**，条件永假，快捷键整页失效。修复
改为「当前路由 isCurrent + 焦点不在任何 EditableText」（PiliPlus
player_focus 语义），见 `lib/pages/player/player_keyboard_shortcuts.dart:134`
与 `:142`-`148`。播放页快捷键恢复工作。

### 2.2 导航浮层压在视频上

现象：播放页在某些时机导航条 / rail 残留在视频上方（该隐藏时不隐藏）。
根因：`menu.dart` 在 Observer builder 里用 `&&` 短路读状态。短路发生在
读取 observable 之前，**Observer 从未建立订阅**，壳层对播放页可见性变化
永远无感。修复：observable 全部无条件读取；`player_page_controller.dart:101`-`108`
新增 `pageCurrent` observable，由 `ModalRoute.isCurrent` 驱动；全出血条件
= 播放页 isCurrent 且有活动媒体（`lib/pages/menu/menu.dart:163`-`179`、
`:213`）；页签高亮随路由状态派生（`menu.dart:177`）。

## 三、播放面板按 Kazumi 逐槽位重组（`d446bb8`）

结论：上下两条控制条的组成、顺序与样式逐槽位照抄 Kazumi@`7265274` 的
`_buildBottomControls` / `_buildTopControls`，手机（compact）与桌面共用
一套组合，**取代上一轮「手机 6 键行 + 底部更多面板」的 PiliPlus 式做法**。
单文件改动：`player_item_panel.dart` 402 插入 / 485 删除（净 -83 行，现
611 行）。

- 底条：鼠标保持区（`PlayerPanelHoldMouseRegion`）包 `PlayerTransportBar`
  ：播放/暂停（`PlayPauseIcon`）、下一集、Observer 圈定的进度条（拖拽
  三件套）+ 等宽数字时间标签、宽控件（桌面）、全屏
  （`lib/pages/player/player_item_panel.dart:139`-`201`）。手机上宽控件
  收起（`:200`），底条 = 播放/暂停、下一集、进度 + 时间、全屏。
- 顶条：返回 / 拖动标题 / 前进 / 截图 / 画中画 / 「更多」菜单锚点
  （`:227`-`287`）。「更多」菜单的 compact 子集 = 视频比例 / 倍速 /
  超分辨率三个子菜单（`:467`-`472`），公共项 = 加载字幕 / 播放列表 /
  上一集 / 视频详情 / 截图（移动）/ 挑选截图（移动）/ 锁定控制 / 定时
  关闭。
- 弹幕与 Syncplay 槽位 EmoPlay 不存在，有意缺席（文件头注释
  `player_item_panel.dart:24`-`34`）。
- 上一轮的可用性成果保留：上下渐变遮罩（Kazumi `_buildScrim` 同款
  black45）与安全区 insets 垫底（`:139`-`152`）。
- 性能细节：播放 tick 只重建进度条与时间标签（Observer 圈定
  `progressBuilder` / `timeLabel`），不再整面板重建。

## 四、发布管线与诊断（`8ed84c4` + 探针）

### 4.1 九个 job 补齐超时上限

pr.yaml 的 linux-ci 20 分钟；release.yaml 的 flutter-test 15 /
flutter-analyze 15 / Android 40 / Windows 45 / macOS 45 / Linux amd64 40 /
Linux arm64 40 / GitHub Release 15 分钟。挂死的 job 不再吃满默认上限烧
私有仓库的 Actions 分钟数。

### 4.2 Windows 版本单一来源恢复

R4 的权宜（钉 `flutter-version: '3.47.9'`）替换为正解：Windows job 前置
`choco install yq`，flutter-action 恢复 `flutter-version-file:
pubspec.yaml`，与其余所有 job 一致。升级 Flutter 时不再需要手改
release.yaml（HANDOVER 坑 8(c) 已同步更新）。

### 4.3 音频诊断探针（`test/audio_probe_test.dart`）

针对 2026-11-11「无声」报告新增的诊断用例：fixture（`/tmp/emoplay-test/
audio.mp3`）存在才真跑，runner 上缺失即早退通过（`audio_probe_test.dart:14`-`17`）；
双趟探测 default ao 与 pinned `ao=pulse`。本轮实测：探针真跑，pinned 趟
`ao="pulse"`、mpv 日志 `AO: [pulse] 44100Hz stereo 2ch float`，捆绑
libmpv 的音频输出在本机可达宿主 pipewire-pulse；首趟 default-ao 读数为
空串（见已知取舍）。

## 五、已知取舍

- **面板新组合的观感未做像素级验收**：模拟器视觉回归仍跑不了（本机无
  emulator 系统镜像且 dl.google.com 不可达，与 R5 移动轮同款限制）；
  Linux debug 构建可运行但本轮未做人手点验。342 用例锁行为不锁观感
  （无 golden 测试）。
- **探针首趟 default-ao 读数为空串**：与 `ec1c91e` 提交信息所述
  （default ao=pulse）不一致，未深究；探针断言只覆盖 pinned 趟。若「无声」
  报告再现，先从这条查。
- **CI 本窗口不可测**：api.github.com 不可达（两次 EOF）；`d446bb8` /
  `8ed84c4` 未推送，推送后预期 342 passed / 1 skipped。
- **上轮 CHANGELOG 的手机面板描述已被取代**：以本说明 §三为准，CHANGELOG
  本轮小节已注明。
- 与既有已知限制一致、本轮无变化：产物未签名 / 实体机验证 ☐ / AppImage
  未做 / i18n 已迁页签壳与音频设置两页。
