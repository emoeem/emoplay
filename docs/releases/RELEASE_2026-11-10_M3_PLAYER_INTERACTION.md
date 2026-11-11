# 更新说明 · 2026-11-10（M3 播放器交互 R9）

> 播放器交互三件套上线：**章节导航**（底板章节面板 + Page Up / Page Down 跳章）、
> **字幕管理**（轨道切换 / 外挂字幕加载 / 关闭字幕 + 字幕延迟 ±0.5s 步进 HUD）、
> **A-B 循环与逐帧步进**（mpv 内置惯例键位 L / `.` / `,`）。三件事的属性读取
> 通道全部在出货 fork 的 libmpv（v0.41.0-11-gf011d73d5-dirty）上逐条实测考证：
> chapter-list 的 JSON 形态、sid 才是选轨真相源、frame-back-step 在命令表里，
> 不是照着 API 文档猜的。44 文件 411 用例全绿，其中 7 条 live 用例用真
> libmpv 真跑（逐帧步进 17 秒实测走帧）。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `2e5d73d`（2026-11-12 00:52 CST，R9: ab-loop + frame-step）。本轮三个提交（`f2b7754` 11-11 08:20 / `a8cb844` 11-12 00:08 / `2e5d73d` 11-12 00:52）落在 11-11~11-12 窗口，文档沿用 2026-11-10 计划窗口命名（同 R1-R7 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试（含 7 条真 libmpv live 用例）/ CI 探测（详见[工作报告 §3](../reports/WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md)）；Windows / macOS / Android / arm64 待 CI 与实体机验证 |
| 自动化测试 | **44 文件 / 411 通过 + 1 平台条件跳过，全绿**（上轮 37 文件 / 355 通过 + 1 跳过；+7 文件 / +56 用例。56 的构成：章节 14+2、字幕 7+2、A-B 循环 26、逐帧 live 3、键位守护 2，逐文件单独实测计数，与全量差值交叉核对一致，见工作报告 §3） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 5.7s)`，2026-11-12 本文档窗口实测）                                                                 |
| CI         | 本窗口不可测：`gh run list -R emoeem/emoplay` EOF（api.github.com 不可达，2026-11-12 实测）；R9 三提交未推送（本地 origin/main 跟踪引用在 `3dcfb6a` = R8，远端当前状态因 EOF 不可复核）。推送后预期签名 **411 passed / 1 skipped**（1 skip = Windows-only 探针，见工作报告 §3） |

## 一、章节导航（`f2b7754`）

结论：mpv 的 `chapter-list` / `chapter` 属性全链读通，章节跳转在底板面板与
快捷键两个入口生效。这也是 3.0 路线图 M3 阶段第一个落地的路线图内任务
（M3-T2 的主体；验收面还差进度条刻度一半，见 §五-1）。

- **属性读取通道是实测考证的，不是照 API 猜的**：fork 以 MPV_FORMAT_NONE
  注册观察、事件到达后经 `readNativeString`（MPV_FORMAT_STRING）回读字符串
  交给监听器。字符串形态实测：`chapter-list` 序列化为 JSON
  （`[{"title":"第一章 开场","time":0.000000},…]`，无章节文件为 `[]`），
  `chapter` 为整数字符串。整段考证注释随行落在
  `lib/mpv/config/mpv_player_properties.dart:37`（沿 1.x「考证注释随行平移」
  铁律的格式）。解析端任何非该 JSON 形态（如旧 mpv 的 `%len%` 转义打印）
  一律降级为空章节表而不是崩：`parseMpvChapterList`
  （`lib/pages/player/controller/chapters_model.dart:53`）。
- **默认值的选择理由**：attach 时机取 `player.open` 之后，因为 mpv 对每个
  观察属性都先发一次初始事件，文件加载完成后的表不丢（同注释实测）；
  末章 `endTime` 恒为 `null`（「播到片尾」，不做容器里没有的臆造值）。
- **跳章查找用上界二分**（`chapterIndexAt`，`chapters_model.dart:102`）：
  章节表按时间有序，二分把任意播放位置映射到当前章，毫秒边界做了双舍入
  处理（有专项用例锁住）。
- **UI 走 Kazumi 同款交互**：底板自适应面板 + ListTile（当前章高亮 +
  播放图标），点击跳转后收起；入口在「更多选项」菜单，**无章节的文件优雅
  隐藏**（`lib/pages/player/chapters_sheet.dart:9`；observable 读取让菜单在
  章节加载 / 清空时自动重建，`player_item_panel.dart:535`）。
- **键位**：`nextchapter` = Page Down、`prevchapter` = Page Up
  （`lib/utils/constants.dart`）。取位依据：出货 libmpv 内嵌的默认 input.conf
  里带着同位置的（注释态）建议绑定 `#PGUP add chapter 1` /
  `#PGDWN add chapter -1`（本轮 `strings build/linux/x64/debug/bundle/lib/libmpv.so.2`
  实测可见），EmoPlay 把这两个 mpv 惯例槽位显式化；Kazumi 的快捷键表与
  1.x 的应用级 Shortcut 表都没有占用 PgUp/PgDn（两库 grep 实测零命中）。
  无章节文件上这两个动作是安全空操作（`player_item.dart:380`）。

## 二、字幕管理（`a8cb844`）

结论：字幕轨道切换、外挂字幕加载、关闭字幕、字幕延迟 ±0.5s 步进四件事
全通，选轨状态的真相源是 mpv 的 `sid` 属性，这一步是修正确性，不是照
media_kit 的表面 API 写。

- **为什么不用 `Player.state.track.subtitle` 当真相源**：fork 只在
  `Player.setSubtitleTrack` 里更新它，而外挂字幕经裸 `sub-add` 命令加载后
  该字段保持 stale（fork 上实测探针：sub-add select 报 `sid=1` 而字段停留
  `'auto'`）。控制器改为观察 `sid` 属性：`'no'` 关闭、`'auto'`/空串 未显式
  选轨（mpv 自动选择可能仍在播）、其余为轨道 id（
  `lib/pages/player/controller/player_subtitles_controller.dart:13` 头注释
  记录了探针过程）。
- **外挂字幕加载**：复用播放页文件选择器，扩展名限定
  srt/ass/ssa/vtt/sub；`sub-add` 的 `select`（加载并激活）与 `auto`（加载
  并交给 mpv 正常选轨）两旗标按 mpv 手册语义实现并常量化。
- **字幕延迟步进 ±0.5s**（mpv 惯例）：步进结果舍入到一位小数，根因是
  mpv 以 `%.6f` 形态回报 `sub-delay`，重复 ±0.5 累加会攒出二进制小数漂移
  （0.30000000000000004 型），HUD 会如实显示脏数字；一位小数比 0.5s 步长
  更细，舍入永不改变步长量级（`lib/pages/player/controller/player_subtitles_model.dart:8`
  的 `nextSubDelay`，含 -0.0 归一）。HUD 文本 `+0.5s` / `-1.0s` / `0.0s`。
- **键位偏离说明（为什么不是 mpv 的 z/Z）**：本表按 `keyLabel` 分发、
  不区分 Shift（`player_keyboard_shortcuts.dart` 的 `_keyIdentity`），字母键
  label 恒为大写，mpv z/Z 双键惯例在本表结构下不可用；且 Z 已被 Kazumi 的
  倍速减占用（SPEC §10 取 Kazumi 现状），故取 mpv z/x 邻位的 **C / V**
  承接 -/+（`constants.dart` 注释随行记录）。快捷键设置页新增「字幕」分组
  收录两键（`lib/pages/settings/keyboard_settings.dart:25`）。
- **轨道标签规则**：标题（含外挂文件名）→ 语言 tag → 第 N 条轨道，三级
  回退（`describeSubtitleTrack`）；fork 合成的 `'auto'`/`'no'` 空态项被
  过滤，面板自己渲染「关闭字幕」行。

## 三、A-B 循环与逐帧步进（`2e5d73d`）

结论：mpv 的 `ab-loop-a/b` 属性与 `frame-step` / `frame-back-step` 命令
全链落地，三键全部沿用 mpv 内置 input.conf 惯例且与既有键位表零冲突
（专项用例锁住）。

- **A-B 循环三态机**（`lib/pages/player/controller/ab_loop_model.dart`）：
  none（A/B 均 `no`）→ aSet → looping → clear，`cycle` 动作复现 mpv 内置
  `ab-loop` 循环命令的语义，并补上 mpv 留为未定义的守卫：**B 点 ≤ A 点在
  客户端拒绝**（拒绝理由中文、OSD 可直接显示）。纯逻辑零 mpv 依赖，26 条
  单测覆盖状态机与字符串解析。
- **L 键的出处考证**（`constants.dart` 注释随行）：2.0 的 defaultShortcuts
  与 1.x 的应用级 Shortcut 表（mpv-emo `Main.qml:471-508`）都没有 L；1.x
  当年该键经 `Main.qml:109-125` 的未消费按键转发落到 mpv 内置绑定
  （L = ab-loop）才生效，本条等于把 1.x 的实际行为在 Flutter 层显式化，
  不是新发明键位。
- **逐帧步进**：`frame-step`（前进一帧并暂停；播放中也可用，mpv 会
  解暂停恰好一帧再重新暂停）与 `frame-back-step`（倒退一帧并暂停，mpv
  注明倒退是 seek 基、可偏差一帧内小数）。fork 支持性实测：出货 libmpv
  命令表含两命令（`strings` 可见，本轮复核过），且 mpv 0.38.0 才有原生
  `frame-back-step`，**fork 若降级到 0.38 以下必须复检**（
  `lib/pages/player/controller/player_frame_step_controller.dart:1` 头注释
  记录）。
- **UI 落点**：底部控制条暂停态显示上一帧 / 下一帧按钮（mpv OSC 惯例位：
  播放键两侧，播放态不占位，`player_transport_bar.dart`）；「更多选项」
  菜单的 A-B 循环项标签随三态变化（设 A → 设 B（显示 A 点时间）→ 清除
  （显示 A→B 时间），`player_item_panel.dart:499`）；循环标记/清除经
  PlayerAbLoopHud 出 OSD 提示（`player_adjustment_hud.dart:1065`）。
- **键位**：`abloop` = L、`framestep` = `.`、`framebackstep` = `,`。
  `test/player_shortcut_keys_test.dart`（2 用例）锁两件事：三键的
  keyLabel 与 Flutter `LogicalKeyboardKey` 身份一致（分发按 keyLabel，
  Flutter 改名会静默失配，同样的失配模式正是字幕 z/Z 不可用的根因）、
  新键与既有单键绑定零冲突。

## 四、修复与根因（`a8cb844`）

- **library_store_test 的竞态等待**：`test/library_store_test.dart:364` 在
  断言扫描静止态之前补 `pumpUntil(() => !store.isScanning)`。根因：扫描
  管线是链式的，`_startScan` 在发送时快照文件夹列表，worker 握手慢时
  第一趟扫描已经覆盖两个文件夹、`_applyScanResults` 随后再串接挂起的
  第二趟请求，旧断言在管线未排干时就读静止态，偶发红灯。纯测试侧修复
  （等待排干），产品代码零改动。

## 五、已知取舍

1. **M3-T2 验收面未收口**：路线图 M3-T2 的进度条章节刻度（rowCount*20<宽
   规则）、hover 章节标题、中键跳章都未做（`player_progress_bar.dart` 里
   grep `chapter` 零命中，2026-11-12 实测）；本轮交付的是面板 + 快捷键 +
   属性链的「能跳章」半边。收口项挂账在[工作报告 §5](../reports/WORK_REPORT_2026-11-10_M3_PLAYER_INTERACTION.md)。
2. **M3-T0（player_item.dart 拆分）仍未做，且文件继续膨胀**：1538 行 →
   **1614 行**（本轮三个提交各加了几十行入口接线，`wc -l` 2026-11-12 实测）。
   路线图把 T0 定为 M3 其余任务的前置，再拖后续任务都在大文件上施工。
3. **快捷键设置页分组没跟上**：章节 / A-B 循环 / 逐帧五键已生效
   （dispatch 在 `player_item.dart:380-385`），但 `keyboard_settings.dart`
   的分组表本轮只加了「字幕」组，章节、循环 / 逐帧两组缺席，设置页看不到
   这五键（不影响功能，影响可发现性）。
4. **路线图勾选未回填**：EMOPLAY-3.0-ROADMAP.md 的 M3 任务全部仍是 ☐
   （本轮未改路线图，沿 R7「文档轮不动路线图」惯例），M3-T2 的部分完成
   状态靠本说明与工作报告携带。
5. **字幕延迟键位偏离 mpv z/X 惯例**（取 C/V）：根因与守卫见 §二，属
   SPEC §10 兜底（表结构不区分 Shift + Z 被 Kazumi 占用），不是疏忽。
6. **CI 与推送状态**：三提交未推送（本地 ahead 3），gh 全窗口 EOF，CI
   签名结论**未测**；预期 411 passed / 1 skipped。
7. **测试环境的两处降级**：本轮全量跑在无 `/tmp/emoplay-perf-lib` 夹具的
   窗口（R7 的夹具随 /tmp 清理消失），性能基准 4 段按 skip-打印降级通过
   （计数不变，设计如此）；AUDIO_PROBE 夹具同样缺失降级。章节 / 字幕 /
   逐帧三件 live 用例不受影响、真 libmpv 真跑。夹具可用 `tools/gen_perf_fixture.sh`
   重建。
