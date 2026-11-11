# 工作报告 · 2026-11-10（M4 媒体库升级 R10）

| 项           | 值                                                                                    |
| ------------ | ------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-12（文档收网窗口）                                                            |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                     |
| 版本         | git `5fedee0`（HEAD，本轮施工四提交的最后一个）                                       |
| 对应更新记录 | [`RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md`](../releases/RELEASE_2026-11-10_M4_MEDIA_LIBRARY.md) |
| 相关         | 任务书：[EMOPLAY-3.0-ROADMAP.md](../EMOPLAY-3.0-ROADMAP.md) §五 M4（M4-T6 为 2026-11-12 用户增补原文）与 §三参考映射（12/13 行）；发布上文：v2.1.0-alpha 已发布（R9 轮后 `789ed0e` bump + `e9bf692` 补 ffmpeg，release run 43069322152 ✓） |

## 1. 本轮范围

3.0 路线图 M4 阶段整体施工 + R9 挂账的 M3-T0 清偿：四个提交加一个文档
收网（本报告）。依据是 EMOPLAY-3.0-ROADMAP.md §五 M4 任务表（T0/T2/T3/
T4/T5 路线图内任务，T6 用户增补）与 §三参考映射第 12/13 行（Kazumi
SliverGrid 网格、PiliPlus ReorderableListView 排序）：

1. `c9245f8` M3-T0 拆 player_item 上帝类（13 文件，+2111/−1501 行）：
   R9 报告 §6 建议 2（「优先级高于任何新功能」）的清偿。`player_item.dart`
   1614 → 484 行（验收线 <500），拆出 10 个职责文件，
   `player_screenshot_sheet.dart`（1052 行）随拆复审到 855 行。纯搬移
   不改行为。
2. `0da4a95` 统一媒体模型 + 元数据缓存（9 文件，+1756/−30 行）：M4-T0
   （`lib/models/media_item.dart` / `playback_session.dart` /
   `media_item_mappers.dart` + 播放队列收编进
   `player_page_controller.dart`）与 M4-T4（`lib/media/media_meta_cache.dart`，
   两段 ffprobe 链 + `media_meta.json`）。
3. `25dd830` 网格分组 + 收藏 + 目录树（12 文件，+2171/−97 行）：M4-T2
   （SliverGrid + pinned 分组头，目录/年月两种）、M4-T3
   （`lib/media/favorites_store.dart` + `favorites.json` + 收藏弹层 +
   卡片角标）、M4-T5（目录侧栏 + 树组件，复用 `scanOptions` 派生）。
4. `5fedee0` 本地 NFO/海报/剧集分组（15 文件，+2845/−47 行）：M4-T6
   用户增补（「Kodi NFO 解析…容错解析（损坏 XML 跳过字段不崩溃），纯
   逻辑服务可测」「本地海报发现…NFO 内 `<thumb>` URL 仅记录不下载
   （本地优先）」「剧集分组：文件名 SxxEyy 季集解析（纯逻辑）→ 剧-季-
   集三级分组服务」，增补原文随注记落 `nfo_parser.dart:5` 等头注释）。
   新建 `nfo_parser.dart` / `nfo_meta_cache.dart`（`media_nfo.json`）/
   `poster_finder.dart` / `episode_grouper.dart` + `nfo_details_sheet.dart`
   详情弹层；网格新增剧集 / 电影两种分组与海报展示。
5. 文档收网（本轮）：发布说明 + 本报告 + HANDOVER 刷新 +
   docs/README.md 索引登记 + CHANGELOG 补 Unreleased R10 节。**路线图
   M3-T0/M4 六任务的 ☐→✅+哈希回填已在工作树**（2026-11-12 收网窗口
   实测 `git status` 唯一 markdown 改动即它，12 插入/9 删除，勾选状态与
   四提交逐一相符；未提交，随本轮文档提交一并入库），另含 §六「改向
   纳入」注记：联网元数据由「明确不做」改排期第 11 轮（用户决策）。

范围纪律核实：`git diff e9bf692..HEAD --stat -- lib/media/history_store.dart
lib/settings/ .github/ pubspec.yaml android/ test/data_compat_spec7_test.dart`
输出为空（2026-11-12 实测），三份 §7 schema 与发布/CI 配置零触碰；本轮
全部改动集中在媒体层、库页、模型层与播放页拆分。基线取 `e9bf692`（R9
尾提交）而非 `2e5d73d`（R9 主体），避免把 `789ed0e`（CHANGELOG + pubspec
bump）与 `e9bf692`（CI 装 ffmpeg）混进本轮账目。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 路线图 | M3-T0 上帝类：`player_item.dart` 1538→1614 行持续膨胀，M3 其余任务的前置 | 完成 | `wc -l lib/pages/player/player_item.dart` = **484**（<500 达标，2026-11-12 实测）；拆出 10 文件全部 <600 行（最大 `player_item_gestures.dart` 302）；489 用例全绿护航「纯搬移不改行为」 |
| 路线图 | M4-T0 统一模型/队列收编缺失 | 完成（验收线 ≥8 → 实测 11 用例） | `lib/models/media_item.dart`（135 行）/`playback_session.dart`（89）/`media_item_mappers.dart`（86）；`test/media_item_mappers_test.dart` 11 用例；`data_compat_spec7_test.dart` 全量跑内绿 |
| 路线图 | M4-T4 元数据缓存缺失（ffprobe 事实不可见） | 完成（验收线 ≥6 → 实测 9 用例） | `lib/media/media_meta_cache.dart`（566 行）；缓存键 sha1(path+mtimeMs) 与缩略图链逐字节同输入（`:255`）；命中零进程契约在测试头注释；`test/media_meta_cache_test.dart` 9 用例 |
| 路线图 | M4-T2/T3/T5 网格观感/收藏/目录树缺失 | 完成（验收线 ≥3/≥6/≥4 → 实测 6/7/5 用例） | `library_grid_groups.dart`（201 行）/`favorites_store.dart`（228）/`library_folder_tree.dart`（239）+`library_directory_sidebar.dart`（221）；三测试文件逐一对应 |
| 用户增补 | M4-T6 本地 NFO/海报/剧集分组（2026-11-12 用户提出） | 完成 | `nfo_parser.dart`（577）/`nfo_meta_cache.dart`（462）/`poster_finder.dart`（96）/`episode_grouper.dart`（205）/`nfo_details_sheet.dart`（238）；5 个新测试文件 40 用例（parser 10 + nfo cache 10 + grouper 13 + poster 6 + UI 1），另随本提交给 `library_grid_grouping_test.dart` 增补 2 用例（电影按 NFO 标题大小写不敏感分组、剧集模式不走分组键路径，`git show 5fedee0` 实测） |
| 文档 | 路线图勾选滞后（R9 遗留 + 本轮六任务） | 完成（工作树已回填，待随文档提交） | `git diff docs/EMOPLAY-3.0-ROADMAP.md`：M3-T0 与 M4-T0/T2/T3/T4/T5/T6 全部 ✅+哈希；§六「改向纳入」注记（第 11 轮联网兜底） |
| 沿袭挂账 | 快捷键设置页缺章节/循环/逐帧两组（R9 §5 遗留） | 未做（本轮零触碰 settings 页） | `git diff e9bf692..HEAD --stat -- lib/settings/` 输出为空（实测）；`keyboard_settings.dart:25` 分组表仍缺三组 |

## 3. 工程状态（实测）

以下全部为本文档窗口（2026-11-12）在本容器实跑，命令可复制
（构建前 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | `No issues found! (ran in 4.8s)`，0 告警 |
| 全量测试 | `flutter test` | `00:25 +489 ~1: All tests passed!`，**54 文件 / 489 通过 + 1 跳过** |
| 测试文件数 | `ls test/*.dart \| wc -l` | 54（R9 基线 44 + 本轮 10 个新文件） |
| 新用例逐文件计数 | `flutter test test/<file>_test.dart`（10 个新文件逐个跑） | media_item_mappers 11、media_meta_cache 9、favorites_store 7、library_folder_tree 5、library_grid_grouping 6、episode_grouper 13、library_nfo_ui 1、nfo_meta_cache 10、nfo_parser 10、poster_finder 6，合计 **78** = 489 − 411（套件差值交叉核对一致） |
| 1 skip 身份 | `flutter test --reporter expanded test/mpv_profile_scanner_test.dart` | `Skip: Windows-only probe (1.x QSKIP contract)`，`00:00 +8 ~1: All tests passed!`；Linux 上按设计跳过，非降级 |
| 基准夹具 | `ls -d /tmp/emoplay-perf-lib` / AUDIO_PROBE | 均不存在（R7 夹具随 /tmp 清理消失）：perf 基准 4 段与音频探针按 skip-打印降级通过（计数不变）；重建命令 `tools/gen_perf_fixture.sh` |
| live 用例 | 全量输出（frame_step_live 段） | 真 libmpv 真跑（`00:11 +488 ~1` 处 ab-loop live 逐条执行后 `00:25` 收尾），live 通道不受夹具缺失影响 |
| CI（main） | `gh run list -R emoeem/emoplay --limit 3` | **gh 本窗口恢复可达**：43069322152 release/v2.1.0-alpha success 14m25s、43069268623 main（`e9bf692`）success 2m47s、43068258121 release 首跑 failure（缺 ffmpeg，`e9bf692` 修复） |
| release 状态 | `gh release view v2.1.0-alpha --json isDraft,assets` | `isDraft: false`、11 资产（3 APK + Linux amd64/arm64 各 deb/tar.gz/AppImage + macOS zip + Windows zip）、publishedAt 2026-11-11T17:50:14Z（= 01:50 CST 11-12） |
| 推送状态 | `git status -sb` / `git log origin/main..HEAD --oneline` | ahead 4：`c9245f8` / `0da4a95` / `25dd830` / `5fedee0`；本地 origin/main 跟踪引用在 `e9bf692`（R9 尾提交已推送且 CI 绿） |
| 版本号 | `grep '^version' pubspec.yaml` | `2.1.0-alpha+2010000`，本轮未动（`789ed0e` 为 R9 发版 bump，不在本轮账目） |
| M3-T0 行数验收 | `wc -l lib/pages/player/*.dart`（12 文件） | player_item **484**（<500 ✓）；pip 264 / audio_binding 83 / keyboard_shortcuts 526（既有文件收拢）/ menu_binding 32 / gestures 302 / panel_hold 288 / progress_pipeline 164 / screenshot_actions 165 / filmstrip 211 / super_resolution_prompt 120（新文件全部 <600 ✓）；screenshot_sheet 855（复审后） |
| R10 净范围 | `git diff e9bf692..HEAD --stat` | **45 文件 / +8839 / −1631**；schema/CI/pubspec/android 零触碰（§1 核实命令输出为空） |
| store 层增改 | `git diff e9bf692..HEAD -- lib/media/library_store.dart` | 仅 +5 行（`scanOptions` getter，`:209`），无 JSON 键改动；`library_model.dart` 为可选 `nfoMeta` 参数的加法式扩展 |

完整 linux 构建与 build_runner 未在本轮重跑（无原生构建面改动、无新增
生成物面；`player_page_controller.g.dart` 随 `0da4a95` 入库且 analyze
0 告警为一致性佐证，同 R9 报告口径）。

## 4. 确认无问题的部分

- **三份 §7 schema 零触碰**：§1 的 diff 范围核实输出为空；
  `test/data_compat_spec7_test.dart` 在全量跑内实测通过（SPEC §7 发布
  承诺）。本轮三个新增落盘文件（favorites.json / media_meta.json /
  media_nfo.json）走「新增文件 ≠ 改 schema」先例，各自带损坏降级 +
  原子写用例（favorites_store 7 用例、media_meta_cache 9、
  nfo_meta_cache 10 中均有损坏/降级场景）。
- **78 用例的账目闭环**：逐文件实测计数（§3 第 4 行）之和 = 全量差值
  （489 − 411），没有暗账。路线图各任务的用例下限全部达标：M4-T0
  ≥8→11、M4-T2 ≥3→6、M4-T3 ≥6→7、M4-T4 ≥6→9、M4-T5 ≥4→5。
- **M3-T0 验收线达标**：player_item 484 < 500、新文件全部 <600
  （§3 逐文件 wc -l 实测），与路线图工作树回填的行数注记逐一相符
  （本报告 §3 独立复测，非抄注记）。
- **分组契约与守卫**：分组保持 caller 输入序、无标记条目不丢（
  `episode_grouper.dart:5` 注释 + 13 用例）；R3 的三条媒体库响应性守卫
  （取消延迟/进度节流/缩略图串行）在全量跑内绿，目录树「不加新扫描」
  的验收在守卫语义下成立。
- **收藏与 §7 数据的双向隔离**：favorites_store 头注释声明渲染期 join、
  不复制 §7 字段；`test/favorites_store_test.dart` 锁「lastPlayed 不受
  影响」与损坏降级；失效收藏降级显示文件名不丢条目。
- **NFO 缓存失效语义**：video mtime + 目录 mtime 双键（海报/NFO 增删
  只动目录 mtime 的坑在 `nfo_meta_cache.dart:26` 注释提前处理）；串行
  链与失败守卫沿用缩略图链的既有契约形态。
- **本地优先零网络**：nfo_parser / poster_finder / nfo_meta_cache 三文件
  无 http import（本轮 grep 实测）；`<thumb>` URL 只记录，详情弹层以
  文本展示。
- **CHANGELOG 结构**：R10 内容新增在顶部 `## [Unreleased]` 节（本轮
  施工在 v2.1.0-alpha 发版之后、未发版，按 Keep a Changelog 归
  Unreleased），未卷入 [2.1.0-alpha] 既有小节。

## 5. 已知限制与未做项

**需要人工操作的**

- 推送四提交（`c9245f8` / `0da4a95` / `25dd830` / `5fedee0`）与本轮
  文档（含路线图工作树回填）并盯 CI 签名（预期 489 passed / 1 skipped；
  gh 本窗口可达但属窗口性恢复，EOF 可能随时回来）。
- GUI 手感人工验收（SPEC §9 口径）：四种分组切换、目录树联动、收藏
  拖拽排序、海报显示与 NFO 详情弹层，本轮只有 headless + 逻辑/UI 测试
  证据，显示层未人工过目。
- 重建 `/tmp/emoplay-perf-lib` 夹具复跑 perf 基准段
  （`tools/gen_perf_fixture.sh`），让基准从降级恢复真跑。

**代码侧待办**

- 分组方式/侧栏开合等 UI 态不持久化（`_groupMode` 为 setState 字段，
  `lib/settings/` 零命中实测）：是否落设置键待产品决策（小改动）。
- 快捷键设置页补章节（nextchapter/prevchapter）、循环/逐帧
  （abloop/framestep/framebackstep）两组（R9 挂账延续）。
- M3 剩余任务：T1 帧预览（路线图 P0，依赖 T0 已清）、T2 进度条章节
  刻度收口（R9 半边）、T3 播放列表面板（依赖 T0 已清，可与 M4 收藏
  弹层组件复用）。
- M5 音乐轮（路线图下一阶段，M4-T0 依赖已清：循环模式提升为设置项 +
  music 队列面板 + 均衡器 UI 收编）。
- 第 11 轮联网元数据兜底（用户改向决策，NFO `<thumb>` 抓取排在本地
  NFO 之后作兜底）。

**固有限制**

- 海报四名约定（sidecar/poster/folder/fanart jpg）之外的库拿不到海报；
  png 变体与父目录不探测（增补范围有意收窄，`poster_finder.dart:5`）。
- 剧集识别基于文件名词边界的 SxxEyy / 1x02，目录名人类语义与 mkv
  标题轨不参与；识别不出的落「未分组」桶（不猜测）。
- NFO/海报事实依赖重扫刷新：在 app 外手工改 NFO/海报后，目录 mtime
  变化触发下一轮扫描重建 `media_nfo.json` 条目，不做文件监听。
- headless live 测试受 fork 预置 `vid=no` 约束（R9 考证，夹具须带音频
  轨或显式 `vid=auto`）；本轮新增面全是纯逻辑/IO/UI 测试，无新增 live
  依赖。
- gh 可达性窗口性波动：本窗口 `gh run list`/`gh release view` 可用
  （R7-R9 曾整窗 EOF），不可达窗口内 CI 结论一律「不可测」，不代答。

## 6. 下一步建议

按优先级排序，每条可独立执行：

1. **推送四提交 + 本轮文档（含路线图回填）并核对 CI 签名**：预期
   489 passed / 1 skipped；红灯按 HANDOVER 坑 2 归因链处理（本地全绿
   ≠ CI 绿）。
2. **M5 音乐轮**：路线图 M4 全清后 M5 的依赖（M4-T0 PlaybackSession）
   已就绪；T1 循环模式提升为设置项（`player_playback_controller.dart:443`
   硬编码的收口）是首刀。
3. **M3 续作**：T1 帧预览（P0）→ T2 章节刻度收口 → T3 播放列表面板；
   顺带补快捷键设置页两组（一条 commit 可带上）。
4. **UI 态持久化决策**：分组方式/目录侧栏是否落 `emoplay_settings` 新键
   （对照 R7「恢复默认设置」三分区语义，避免恢复默认漏新键）。
5. **第 11 轮联网元数据兜底**：按用户改向决策实施 `<thumb>` 抓取；
   动手前先定允许列表/超时/失败降级（不破坏本地优先默认）。
6. **重建 perf 夹具并复跑基准段** + **GUI 验收窗口**：分组/海报/弹层/
   拖拽按 CROSS-PLATFORM-VERIFICATION-MATRIX.md 桌面自动化节执行指针
   类用例并回填矩阵。
