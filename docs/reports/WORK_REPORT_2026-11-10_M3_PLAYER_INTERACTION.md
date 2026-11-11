# 工作报告 · 2026-11-10（M3 播放器交互 R9）

| 项           | 值                                                                                    |
| ------------ | ------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-12（文档收网窗口）                                                            |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                     |
| 版本         | git `2e5d73d`（HEAD，本轮施工三提交的最后一个）                                       |
| 对应更新记录 | [`RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md`](../releases/RELEASE_2026-11-10_M3_PLAYER_INTERACTION.md) |
| 相关         | 任务书：[EMOPLAY-3.0-ROADMAP.md](../EMOPLAY-3.0-ROADMAP.md) §五 M3；R8（`3dcfb6a`，纯文档轮：3.0 路线图 / 验证矩阵 / fork 治理三件套）无独立发布记录，作为本轮的上文在此记一笔 |

## 1. 本轮范围

3.0 路线图 M3 阶段的第一批施工：三个提交加一个文档收网（本报告），依据是
EMOPLAY-3.0-ROADMAP.md §五 M3 任务表与参考项目借鉴映射 §三（Haruna 章节模型、
mpv 属性语义）：

1. `f2b7754` 章节导航（11 文件，+1032 行）：M3-T2 主体。`chapter-list` /
   `chapter` 属性读取链（解析 / 二分 / 控制器）、底板章节面板、
   Page Up / Page Down 跳章快捷键、`mpv_player_properties.dart` 补章节属性
   考证注释。**M3-T2 的进度条刻度半边未做**（见 §5）。
2. `a8cb844` 字幕管理（15 文件，+1116/−12 行）：路线图外的播放器交互任务
   （代码内标签「M3 施工件 B」）。轨道切换 / 外挂加载 / 关闭字幕 /
   sub-delay ±0.5s 步进，`sid` 属性作选轨真相源，C/V 键承接，快捷键设置页
   新增「字幕」组；顺带修一处扫描管线竞态的测试等待。
3. `2e5d73d` A-B 循环 + 逐帧步进（15 文件，+1571 行）：路线图外任务（代码内
   标签「M3 施工件 C」）。ab-loop 三态机 + L 键、frame-step /
   frame-back-step + `.`/`,` 键、控制条暂停态逐帧按钮、三态菜单项与 OSD HUD、
   键位守护测试。
4. 文档收网（本轮提交）：发布说明 + 本报告 + HANDOVER 刷新 +
   docs/README.md 索引登记 + CHANGELOG 补 R9 节。

范围纪律核实：`git diff 3dcfb6a..HEAD --stat -- lib/media/ lib/services/storage/ lib/settings/`
输出为空（2026-11-12 实测），三份 JSON schema 的落盘层零触碰；全部改动集中在
播放页、mpv 属性层与键位表。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 路线图 | M3-T2 章节导航缺失（路线图 §2.4：grep chapter 零命中） | 完成（主体：属性链 / 面板 / 快捷键）；进度条刻度 / hover / 中键未做，挂账 §5 | `lib/pages/player/controller/chapters_model.dart`（143 行）、`player_chapters_controller.dart`（177 行）、`chapters_sheet.dart`（84 行）；`test/chapters_model_test.dart` 14 用例 + `test/chapters_live_test.dart` 2 用例真 libmpv 绿 |
| 路线图外 | 字幕轨道管理无 UI（media_kit 表面 API 的选轨字段在 fork 上是 stale 的） | 完成（真相源换成 `sid` 属性） | `lib/pages/player/controller/player_subtitles_controller.dart:13` 头注释探针记录；`test/subtitles_live_test.dart` 2 用例真 libmpv 绿 |
| 路线图外 | A-B 循环 / 逐帧步进无任何入口 | 完成（三态机 + mpv 惯例键位） | `ab_loop_model.dart`（246 行，26 用例）、`player_frame_step_controller.dart`（55 行）+ `test/frame_step_live_test.dart` 3 用例真跑 17s |
| 测试健壮性 | `library_store_test.dart` 扫描静止态断言在链式管线排干前读取（偶发竞态） | 完成（测试侧补排水等待，产品代码零改动） | `test/library_store_test.dart:364` `pumpUntil(() => !store.isScanning)`；本轮全量含该用例绿 |
| 文档 | EMOPLAY-3.0-ROADMAP M3 勾选全部仍 ☐（三提交未回填 ☐→✅+哈希） | 挂账（沿 R7「文档轮不动路线图」惯例；T2 半完成态也不宜勾 ✅） | `docs/EMOPLAY-3.0-ROADMAP.md:206-217` 逐行 ☐（2026-11-12 实测） |
| 文档 | 键位设置页分组缺章节 / 循环 / 逐帧三组（五键生效但设置页不可见） | 挂账（代码侧待办，见 §5） | `lib/pages/settings/keyboard_settings.dart:17-27` 分组表仅含播放控制 / 音量 / 画面与声音 / 倍速 / 字幕；dispatch 实际生效于 `lib/pages/player/player_item.dart:380-385` |

## 3. 工程状态（实测）

以下全部为本文档窗口（2026-11-12）在本容器实跑，命令可复制
（构建前 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | `No issues found! (ran in 5.7s)`，0 告警 |
| 全量测试（第一遍） | `flutter test` | `00:27 +411 ~1: All tests passed!`，**44 文件 / 411 通过 + 1 跳过** |
| 全量测试（第二遍，expanded reporter） | `flutter test --reporter expanded` | `00:25 +411 ~1: All tests passed!`，两次同数 |
| 测试文件数 | `ls test/*.dart \| wc -l` | 44（R7 基线 37 + 本轮 7 个新文件） |
| 新用例逐文件计数 | `flutter test test/<file>_test.dart`（7 个新文件逐个跑） | chapters_model 14、chapters_live 2、subtitles_model 7、subtitles_live 2、ab_loop_model 26、frame_step_live 3、player_shortcut_keys 2，合计 **56** = 411 − 355（套件差值交叉核对一致） |
| 1 skip 身份 | expanded 输出 | `test/mpv_profile_scanner_test.dart:217-219` `locateOnWindowsUsesAppData`，skip 理由「Windows-only probe (1.x QSKIP contract)」，Linux 上按设计跳过，非降级 |
| live 用例 | 上表 7 文件中 3 个 live 文件 | 真 libmpv 真跑：chapters_live 00:03、subtitles_live 00:01、frame_step_live 00:17（走帧实测） |
| 基准夹具 | `ls -d /tmp/emoplay-perf-lib` | 不存在（R7 夹具随 /tmp 清理消失）：全量里的 perf 基准段与 AUDIO_PROBE 按 skip-打印降级通过（计数不变）；重建命令 `tools/gen_perf_fixture.sh` |
| CI | `gh run list -R emoeem/emoplay --limit 3` | `failed to get runs: Get "https://api.github.com/...": EOF`，api.github.com 不可达，本窗口不可测 |
| 推送状态 | `git status -sb` / `git log origin/main..HEAD --oneline` | ahead 3：`f2b7754` / `a8cb844` / `2e5d73d`；本地 origin/main 跟踪引用在 `3dcfb6a`（R8，11-11 04:52，说明 R7 三提交与 R8 已在最后一次 fetch/push 时点进入远端；远端当前状态因 EOF 不可复核） |
| 版本号 | `grep '^version' pubspec.yaml` | `2.0.0-alpha+2000000`，本轮未动 |
| 大文件口径 | `wc -l lib/pages/player/player_item.dart` | **1614 行**（路线图 M3-T0 验收线 <500；审计时 1506，路线图建立时 1538，持续膨胀） |

完整 linux 构建与 build_runner 未在本轮执行（无原生构建面改动、无 MobX
模型外的生成物新增；`.g.dart` 文件随提交入库且 analyze 0 告警为一致性佐证）。

## 4. 确认无问题的部分

- **三份 JSON schema 零触碰**：§1 的 diff 范围核实输出为空；
  `test/data_compat_spec7_test.dart` 在全量跑内实测通过（SPEC §7 契约
  411 之一）。本轮全部新状态（章节表 / sid / ab-loop 相位）是运行时属性，
  不落盘。
- **56 用例的账目闭环**：逐文件实测计数（§3 第 5 行）之和 = 全量差值
  （411 − 355），没有暗账；两遍全量跑同数（411 ~1）。
- **新键位零冲突**：`test/player_shortcut_keys_test.dart` 第 2 用例遍历
  defaultShortcuts 全表断言单键不重复（L / `.` / `,` / C / V 五键全部
  fresh）；keyLabel 身份用例防止 Flutter 改名导致静默失配。
- **无播放器 / 无章节 / 无字幕轨道时的空操作语义**：dispatch 表五个新动作
  全部是安全空操作（`player_item.dart:376-385` 注释逐条声明），章节面板与
  菜单入口在无章节文件上优雅隐藏（`chapters_sheet.dart:9`、
  `player_item_panel.dart:535`）。
- **fork 探针记录随行**：chapter-list JSON 形态 / sid stale / frame-back-step
  ≥0.38 / headless vid=no 夹具约束四处考证都写在对应源文件头注释（
  `mpv_player_properties.dart:37`、`player_subtitles_controller.dart:13`、
  `player_frame_step_controller.dart:1`、`chapters_model.dart:39`），下次
  fork 同步时逐条可复核（FORK-GOVERNANCE 口径）。
- **CHANGELOG 一轮一节结构**：R9 节按既有结构追加，R7/R6 等节未卷入
  （追加后人工核对）。

## 5. 已知限制与未做项

**需要人工操作的**

- 推送 `f2b7754` / `a8cb844` / `2e5d73d` 三提交并盯 CI 签名（预期
  411 passed / 1 skipped）；gh 窗口 EOF 未解除，本轮无法代做。
- GUI 手感人工验收（SPEC §9 口径）：章节面板开关 / A-B 循环 OSD / 暂停态
  逐帧按钮的实际手感与真机键盘事件，本轮只有 headless + live-libmpv（无
  渲染面）证据，显示层未人工过目。
- EMOPLAY-3.0-ROADMAP M3 勾选回填：建议在 M3-T0 落地时统一回填并如实标注
  T2 的部分完成（刻度半边）。

**代码侧待办**

- M3-T0：拆 `player_item.dart`（1614 行，验收线 <500）。M3 其余任务
  （T1/T3-T9）按路线图都在拆出的文件上施工，T0 再拖施工面继续恶化。
- M3-T2 收口：进度条章节刻度（rowCount*20<宽 规则）+ hover 章节标题 +
  中键跳下一章（`player_progress_bar.dart` 目前 grep chapter 零命中）。
- 快捷键设置页分组补齐：章节（nextchapter/prevchapter）、A-B 循环 /
  逐帧（abloop/framestep/framebackstep）两组进 `keyboard_settings.dart`
  的 `_shortcutGroups`。
- M3-T1（帧预览）/ M3-T3（播放列表面板）/ M3-T4 及以后：全部未开始
  （路线图 §五 M3 表逐行 ☐）。

**固有限制**

- CI 可见性依赖 api.github.com，EOF 窗口内 CI 结论一律「不可测」，不代答。
- headless live 测试受 fork 预置 `vid=no` 约束：纯视频夹具会被 mpv
  以「No video or audio streams selected」卸载，live 夹具必须带音频轨或
  显式 `vid=auto`（`mpv_player_properties.dart:37` 考证注释与三个 live
  文件头均已声明）。
- `frame-back-step` 依赖 mpv ≥0.38（fork 当前 v0.41.0-11-gf011d73d5-dirty
  实测可用）；fork 降级时该命令消失，属上游能力边界。
- 字幕延迟往返精度受 mpv `%.6f` 回报形态约束，模型层以一位小数舍入兜住
  （`player_subtitles_model.dart:8`），更细精度无意义（步长 0.5s）。

## 6. 下一步建议

按优先级排序，每条可独立执行：

1. **推送三提交并核对 CI 签名**（gh 恢复可达后）：预期 411 passed /
   1 skipped；红灯按 HANDOVER 坑 2 归因链处理（本地全绿 ≠ CI 绿）。
2. **M3-T0 拆分 player_item.dart**（1614 行，本轮又涨 76 行）：纯搬移不改
   行为，355+56 用例护航；这是 M3 其余任务的前置，优先级高于任何新功能。
3. **M3-T2 收口**：进度条章节刻度 + hover 标题 + 中键跳章，复用
   `chapters_model.dart` 的二分；顺带补快捷键设置页两组分组。
4. **M3-T1 帧预览**（路线图 P0）：第二 Player 实例挂 hover 气泡；注意
   路线图验收要求 T0 先行。
5. **重建性能夹具并复跑基准段**：`tools/gen_perf_fixture.sh` 生成
   `/tmp/emoplay-perf-lib`，让 perf 基准 4 段从降级恢复为真跑（R7 口径）。
6. **GUI 手感人工验收窗口**：章节面板 / AB HUD / 逐帧按钮 / 字幕延迟 HUD，
   按 CROSS-PLATFORM-VERIFICATION-MATRIX.md 桌面自动化节在空闲窗口执行
   指针类用例并回填矩阵。
