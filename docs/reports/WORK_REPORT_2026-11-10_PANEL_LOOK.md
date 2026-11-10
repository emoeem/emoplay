# 工作报告 · 2026-11-10（面板观感 R5）

| 项           | 值                                                                                             |
| ------------ | ----------------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-11（写作时 01:24 CST；窗口为 2026-11-10 夜间，文件名沿用窗口日期）                      |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                                |
| 版本         | git `8ed84c4`（HEAD）；origin/main 停在 `63d9f59`，本轮 `d446bb8` / `8ed84c4` 两个提交未推送   |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_PANEL_LOOK.md`](../releases/RELEASE_2026-11-10_PANEL_LOOK.md)     |

## 1. 本轮范围

OVERNIGHT-LOOP §二轮次结构的 R5 轮文档收网（第 5 轮，主题「面板观感」）。
开工检查受阻：`gh run list` 两次连接 EOF（api.github.com 不可达），上一轮
推送后的 CI 结论在本窗口无法核实（见 §3，按红线记「不可测」而非引用旧
run）。施工面为本轮五个提交（`c38c83d` 是 R4 文档轮的路线图收尾，纯
markdown，不计入本轮施工）：

1. `ec1c91e` 播放页快捷键 + 壳层浮层两处整页失效修复，附音频诊断探针
   `test/audio_probe_test.dart`（71 行）。
2. `aeda939` 恢复 Kazumi 内置 MiSans 为全局字体。
3. `63d9f59` 字体按 Kazumi useSystemFont 设计端到端（系统字体默认 + 开关
   + 显式 CJK 兜底），SPEC §1 字体行同步。
4. `d446bb8` 播放面板按 Kazumi@`7265274` 逐槽位重组（取代上轮 PiliPlus 式
   手机 6 键行 + 底部更多面板）。
5. `8ed84c4` CI 九个 job 超时上限 + Windows 版本单一来源（choco 装 yq 后
   恢复 `flutter-version-file`）。

文档收网（本轮）：本报告 + 发布说明 + HANDOVER 刷新 + docs 索引登记 +
CHANGELOG「面板观感轮」小节。上轮（移动端播放修复轮）的 CHANGELOG 与
HANDOVER 已由当轮更新，本轮不重复；本轮显式记录对上轮手机面板描述的取代
关系。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 红灯 | 播放中快捷键全部失效：门禁守在自建 `keyboardFocus` 节点上，该节点永远不会成为 primaryFocus，条件永假 | ✅ 已修（`ec1c91e`） | `lib/pages/player/player_keyboard_shortcuts.dart:134,142-148`：门禁改 route.isCurrent + 焦点不在 EditableText（PiliPlus player_focus 语义）；提交信息根因原文「a node nobody ever focused, so every shortcut died during playback」 |
| 红灯 | 播放页导航浮层残留（该隐藏不隐藏）：Observer builder 内 `&&` 短路，observable 未被读取，Observer 从未订阅 | ✅ 已修（`ec1c91e`） | `lib/pages/menu/menu.dart:163-179,213` 无条件读 observable + `_fullBleed`；`player_page_controller.dart:101-108` 新增 `pageCurrent`（ModalRoute.isCurrent 驱动，`.g.dart` +31 行同提交） |
| 观感 | CJK 落楷体（LXGW ZhenKai）：M1 删内置字体且未设 fontFamily，fontconfig 猜错 | ✅ 已修（`aeda939` + `63d9f59`） | `assets/fonts/MiSans-Regular.ttf` 8,122,324 B + `pubspec.yaml:113-116`；`theme_provider.dart:8-13` kAppFontFamilyFallback 显式 Noto Sans CJK SC；`settings_keys.dart:212-216` useSystemFont 默认 true；`theme_settings_page.dart:231-245` 开关 + 静态主题重发射；`docs/SPEC.md:20` |
| 观感 | 面板组成与 Kazumi 不一致：手机/桌面两套代码路径（PiliPlus 6 键行 + 底部 sheet），槽位顺序无对照 | ✅ 已重组（`d446bb8`） | `git show --stat d446bb8`：player_item_panel.dart 单文件 402 插入 / 485 删除（现 611 行）；文件头注释（`:24-34`）声明逐槽位对照 Kazumi `_buildBottomControls`/`_buildTopControls`；compact 分支实测（`:200` 宽控件收起、`:467-472` 更多菜单 compact 子集） |
| 工程 | release/pr workflow 无 job 超时上限；Windows 版本钉死 `flutter-version: '3.47.9'`（R4 权宜） | ✅ 已修（`8ed84c4`） | `git show 8ed84c4`：9 个 job 补 timeout-minutes（linux-ci 20；test/analyze 15；Android/Linux amd64/arm64 40；Windows/macOS 45；Release job 15）；Windows 前置 `choco install yq` + 恢复 `flutter-version-file: pubspec.yaml`（Kazumi release workflow 同款先例） |
| 诊断 | 2026-11-11「无声」报告缺乏定位手段 | ✅ 探针落地并真跑（问题本身未复现） | `test/audio_probe_test.dart`（fixture 缺失即早退，`:14-17`）；本轮 fixture 在、探针真跑：pinned 趟 `ao="pulse"` + `AO: [pulse] 44100Hz stereo 2ch float`；首趟 `default-ao=""` 未深究（§5） |
| 阻塞 | 上轮推送后的 CI 结论无法核实 | ⚠️ 本窗口不可测 | `gh run list -R emoeem/emoplay --limit 6` 两次 EOF（01:18 / 01:22 CST，api.github.com 不可达）；不引用旧 run 冒充本轮结论 |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 代码生成幂等 | `dart run build_runner build --delete-conflicting-outputs` | **wrote 0 outputs**，跑后 `git status --porcelain` 为空：`ec1c91e` 提交的 `.g.dart` 与生成器输出一致 |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 5.7s)**：0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test`（全量） | **00:20 +342 ~1: All tests passed!**：34 文件（`ls test/*_test.dart \| wc -l` = 34）/ 342 通过 + 1 平台条件跳过（`Skip: Windows-only probe (1.x QSKIP contract)`，`test/mpv_profile_scanner_test.dart` 的 `locateOnWindowsUsesAppData`） |
| 用例增量对账 | 342 − 341 = 1；34 − 33 = 1 | 自洽 ✓：+1 文件 / +1 用例 = `audio_probe_test.dart`（R4 口径 33 文件 / 341 + 1） |
| Linux 构建（debug） | `flutter build linux --debug` | **✓ Built build/linux/x64/debug/bundle/emoplay** |
| ldd 审计 | `ldd build/native_assets/linux/libmpv.so.2 \| grep -c 'not found'` | **0**：容器内依赖闭包完整（与 R3/R4 口径一致） |
| 音频探针 | `flutter test` 内真跑（`/tmp/emoplay-test/` 四个 fixture 存在） | `AUDIO_PROBE default-ao=""`（首趟空串）；`AUDIO_PROBE pulse-pinned ao="pulse"` + `AO: [pulse] 44100Hz stereo 2ch float`（PulseAudio audio output） |
| CI（main） | `gh run list -R emoeem/emoplay --limit 6`（后改 `--limit 4` 重试） | 两次 `failed to get runs: ... api.github.com ... EOF`（01:18 / 01:22 CST）：**本窗口不可测** |
| 推送状态 | `git log origin/main..HEAD --oneline` | **2 个提交未推送**（`8ed84c4` 01:11 / `d446bb8` 01:05）；origin/main = `63d9f59`（`ec1c91e` / `aeda939` / `63d9f59` 已推送，其 CI 结论同受网络阻塞所限无法核实） |
| 树干净度 | `git status --porcelain`（文档写作前） | **空** |

## 4. 确认无问题的部分

- **生成物与提交一致**：`ec1c91e` 给 `player_page_controller` 加的
  `pageCurrent` observable 连同 `.g.dart`（+31 行）同提交，build_runner
  重跑 wrote 0 outputs、树净：CI 不需要额外生成步骤（R3/R4 结论的再验证）。
- **面板重组是单文件手术**：`d446bb8` 只动 `player_item_panel.dart`，
  周边（`player_transport_bar.dart` / `player_progress_bar.dart` /
  `player_panel_hold.dart` 等）未动，342 用例全绿未见回归。
- **skip 口径与 R4 完全一致**：同一用例（Windows-only probe）同一理由，
  无新增 skip，探针不产生第二个 skip（fixture 缺失走早退通过而非 skip）。
- **字体资产与声明一致**：`pubspec.yaml` family `MI_Sans_Regular` 对
  `assets/fonts/MiSans-Regular.ttf`（8,122,324 B）一一对应；
  `theme_provider.dart` 头注释与 `docs/SPEC.md:20` 互相印证（同提交
  `63d9f59` 改写）。
- **workflow 改动范围可控**：`git show 8ed84c4` 全文核对，只有
  timeout-minutes、yq 安装步与版本源切换；无 secrets、无 dart-define、
  无新第三方 action（choco 是 runner 自带包管理器）。
- **取代关系已写明**：上轮 CHANGELOG 的「手机传输行 6 键 + 更多底部面板」
  描述被本轮 CHANGELOG 小节与发布说明 §三显式取代，两处互相引用，不留
  两套口径。

## 5. 已知限制与未做项

**需要人工操作的**
- 推送 `d446bb8` / `8ed84c4` 与本轮文档提交（推送由收尾流程执行）；推送后
  核对 CI 签名 **342 passed / 1 skipped**（本窗口 api.github.com 不可达，
  无法自查）。
- 面板与字体的实机 / 模拟器观感验收：手机 + 桌面各过一遍播放面板（重组后
  手机底条为播放/暂停、下一集、进度+时间、全屏，确认无溢出遮挡）；字体
  开关开/关各看一次 zh + en。模拟器视觉回归仍未跑（无 emulator 镜像 +
  dl.google.com 不可达）；Android assembleDebug 本轮未重跑（无 Android
  原生改动，风险低但未验）。

**代码侧待办**
- 探针首趟 `default-ao` 读数空串的排查（12 秒等待后读 ao 为空，可能与
  pinned 趟 3 秒即得矛盾；或改读 `current-ao` / 加 readiness 等待）。
- 面板观感无 golden 测试：342 用例锁行为不锁观感，如需锁观感可从桌面
  面板起步加 golden 基线。
- 既有账目不变：release.yaml prerelease 语义决策、AppImage、i18n 第三页
  起、Windows URL 转发、1.x 对账最后一条
  （`restoreDefaultsKeepsMediaAndHistory`）。

**固有限制**
- 纯 markdown 推送不触发 CI（pr.yaml `paths-ignore: '**.md'`）；混合
  push 触发时 run 标题只显示头提交（R2/R3/R4 连续证实）。
- api.github.com 本窗口不可达：凡 CI 结论一律标「不可测」，不得拿旧 run
  冒充本轮。
- 私有仓库 Actions 分钟数有限：job 超时上限（本轮 `8ed84c4`）只能止血
  挂死 job，不能省正常矩阵的分钟数。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送并盯 CI 签名**：`git push origin main` 后
   `gh run list -R emoeem/emoplay`，预期 **342 passed / 1 skipped**；红灯
   按 pr.yaml ldd 审计步的全量清单处理。
2. **观感验收**：有 emulator 后跑 Android 模拟器过一遍手机播放面板 +
   旋转自动全屏 + 字体开关；桌面 Linux 实机点验底条/顶条槽位与楷体是否
   绝迹（`fc-match` 可辅助核对 CJK 解析）。
3. **default-ao 排查**：探针首趟空串读数定位（优先改读 `current-ao` 或
   等 `file-loaded` 事件后再读），让探针对「无声」报告真正可用。
4. **i18n 第三页**：从设置页再挑一类完成迁移并配 l10n 链路用例（生成链
   已在页签壳 + 音频设置两页验证可用）。
5. **golden 测试起步（可选）**：桌面播放面板两态（全屏/非全屏）先建
   基线，锁住本轮重组成果。
