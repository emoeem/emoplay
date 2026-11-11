# 更新说明 · 2026-11-10（M5 音乐与在线元数据兜底 R11）

> 音乐模式补全三件套：循环模式三态（顺序 / 单曲 / 列表）+ music 形态队列
> 面板、replaygain 与 gapless 音频偏好（1.x 明文遗留项清偿）、歌词页两处
> 精度修复 + 翻译列 + 离开播放页的常驻迷你条；第 11 轮用户改向的在线元
> 数据兜底以**框架**形态落地（默认关、五道门禁、无 key 优雅降级）。修掉
> 的隐患：列表循环若沿用引擎 `loop-playlist`，在 media_kit 单 entry 装载
> 下会让 mpv 无限回卷同一文件、completed 永远到不了应用层；回卷因此改在
> 应用层实现，队列续播语义保持可达。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `eb3b2bf`（2026-11-12 06:55 CST，R11: online metadata fallback framework (M4-T7)）。本轮四提交（`2115183` 05:51 / `ec456b3` 06:14 / `a539866` 06:36 / `eb3b2bf` 06:55，均 2026-11-12）落在 11-11 至 11-12 窗口，文档沿用 2026-11-10 计划窗口命名（同 R1-R10 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试 / CI 与 release 状态（gh 本窗口可达，详见[工作报告 §3](../reports/WORK_REPORT_2026-11-10_M5_MUSIC_METADATA.md)）；Windows / macOS / Android / arm64 待 CI 与实体机验证 |
| 自动化测试 | **60 文件 / 539 通过 + 1 平台条件跳过，全绿**（上轮 54 文件 / 489 通过 + 1 跳过；+6 文件 / +50 用例。50 的构成逐文件实测点数：emoplay_settings 12、tmdb_provider 10、online_meta_service 10、music_queue 7、music_lyrics_page 3、music_mini_bar 2、mpv_player_properties 2、audio_properties_settings 2、library_online_ui 1、audio_settings_l10n 1、library_nfo_ui 0（仅注释随行），合计与全量差值 539-489 一致，见工作报告 §3） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 5.3s)`，2026-11-12 07:00 CST 本文档窗口实测）                                                       |
| CI         | gh 本窗口可达：v2.2.0-alpha 的 main run 43101040926 ✓（3m36s）、release run 43101070581 ✓（13m34s），release 已公开（非 draft、11 资产，`gh release view` 实测）。本轮四提交未推送（ahead 4），推送后预期签名 **539 passed / 1 skipped**（未测：远端尚未载入 R11） |

## 一、循环模式三态与音乐队列面板（`2115183`，M5-T1）

结论：路线图 §五点名的 `player_playback_controller.dart:443` 处
`PlaylistMode.none` 硬编码提升为三态设置（settings.json `behavior.playlistMode`，
`none` / `single` / `playlist`），三个动线全部可切：设置 → 播放页「循环模式」
下拉（`lib/pages/settings/player_settings.dart:346`）、播放面板「更多」菜单
三态入口（标签随当前值变化，`none→single→playlist→none` 循环，切换即落盘 +
对存活 Player 即时下发）、music 形态的「播放队列」底板面板（带循环模式头部）。

- **默认值为什么是 `none`（顺序播完）**：原硬编码即 `PlaylistMode.none`，
  默认 none 保持 1.x/Kazumi 现状，老用户行为零变化；新键走 §四红线
  （settings.json 允许追加键、1.x 读取方忽略未知键），默认值与往返用例随行
  （`test/emoplay_settings_test.dart`）。
- **列表循环为什么刻意不开引擎 `loop-playlist`**（本节开头引语的根因）：
  media_kit 的 `open(Media)` 只向 mpv 装载一个 entry 的内部 playlist
  （fork real.dart `open(): playlist.add(playable)`），`loop-playlist=yes`
  会让 mpv 在文件结尾回卷到这**唯一** entry，即文件自身无限循环、
  completed/eof 永远到不了应用层，队列无法续播。映射与考证注释随行
  （`_playlistModeFor`，`lib/pages/player/controller/player_playback_controller.dart:604`
  起）。因此 `playlist` 档同样映射 `PlaylistMode.none`（引擎 loop 关），
  回卷在应用层实现：队列事实源是 `PlaybackSession`（§四统一模型），每文件
  一个 Player 实例，completed 时由 `PlayerProgressPipeline` 调用纯决策函数
  `resolveQueueNextIndex`（`lib/music/music_queue.dart:82`）推进，队尾回卷
  到第 0 首。单曲循环则走引擎原生 `loop-file`（mpv 自己重复文件，completed
  不触发、队列不前进：media_kit `PlaylistMode.single` 的属性映射原样利用）。
- **music 形态队列面板**：music（音频）形态的面板入口标签改为「播放队列」，
  打开的是复用 M3-T3 底板组件（showAdaptiveBottomSheet + Observer 列表）的
  `music_queue_panel.dart`（188 行），头部带三态循环切换；视频形态维持既有
  「播放列表」面板，语义分离。

## 二、replaygain 与 gapless（`ec456b3`，M5-T2）

结论：设置 → 音频新增「音频属性」分组：**响度均衡（ReplayGain）**三档
`off` / `track` / `album`（默认 off）；**无间隙播放**以 `gapless-audio=weak`
钉为全局预置项。二者都经 `mpv_player_properties.dart` 既有通道下发
（`lib/mpv/config/mpv_player_properties.dart:188-191`）。

- **replaygain 默认 off 的理由**：1.x 从未实现该属性（grep mpv-emo 的
  src/ qml/ mpv.md 两词零命中），off = 1.x 现状、行为零变化；off 仍显式钉
  mpv 的 `'no'` 而非不写键：与 load-scripts 的同一先例，让生效选项表
  （审计视图）陈述意图，而不是靠「没写 = 默认」的隐式约定。未知/损坏取值
  回落 `'no'`（绝不臆测一个增益档）。用户导入的 mpv.conf 显式项依旧后写者
  胜（compatOptions 在 build() 里最后 addAll）。
- **gapless 为什么钉 `weak` 而不是 `yes`**：mpv 自身默认就是 weak（shipped
  libmpv idle core 回读实测），钉住 = 行为与改造前逐位一致 + 意图进审计表 +
  防 fork 默认漂移；`yes` 档会把首个文件的输出参数锁死给后续文件（音质陷阱），
  weak 只在解码输出格式变化时才重开设备：同参数编码连播无缝，是 mpv 自己
  选定的折中。考证（mpv v0.41.0 options.rst 手册 + fork pre-init/post-init
  属性表均不含二者）整块随行在 `mpv_player_properties.dart:51-90`。
- **修掉的 1.x 遗留**：gapless 是旧仓库明文遗留项（mpv-emo
  docs/roadmap.md「遗留项：…gapless/loop 行为」、architecture.md 音乐模式
  小节；nativeization-plan.md 曾计划 `gapless-audio=weak` 配合音乐模式无缝
  切歌但未落地），本轮以最小面兑现。
- **现场实测边界**：runtime `setProperty` 被接受且回读一致（live 用例
  `replaygainThreeStatesAndGaplessApplyToLiveCore` 真跑）；但接受 + 回读一致
  ≠ 行为层已重读（load-scripts 的同一教训），增益 / 无缝的**听感**生效留待
  SPEC §9 人工验收（见 §五）。

## 三、歌词升级与常驻迷你条（`a539866`，M5-T3）

结论：音乐歌词页两处精度修复 + 翻译列；离开播放页后底部出现常驻迷你条，
点击回播放页。

- **首帧定位修复（根因）**：此前歌词滚动只跟随 `lyricIndex` 变化：歌词
  文件加载晚于首帧（mpv 探测后才有 .lrc）时，第一行高亮不定位，直到下一行
  时间戳才恢复跟随。现在首次构建即按当前 index 定位一次，加载时序不再影响
  首帧。滚动动画时长与滚动距离成比例（120-420 ms 夹紧）：跨长间歇的大跳
  不再 240 ms 硬拉、相邻行切换不再拖尾。
- **翻译列（双语对照）**：双语 .lrc 通行约定：同一时间戳的相邻行为一组，
  第一行原文、其余为译文；多时间戳展开产生的是不同时间相同文本，不会误入
  分组。行高全为常量（40 + 24×译文数），滚动定位保持确定性；无同时间戳行
  时布局退化为单语，与升级前一致。
- **常驻迷你条**（`lib/pages/player/music_mini_bar.dart`，148 行）：可见性
  条件 `currentIndex >= 0 && !pageCurrent`，即有活动条目且不在播放页；竖屏
  挂 NavigationBar 之上、横屏挂 outlet 之下（`lib/pages/menu/menu.dart:231,322`）；
  显示当前曲目 / 播放暂停 / 进度，点击经 shell 注入的 `_selectDestination`
  回播放页（与点 tab 完全同一条切页路径）。**视频条目同样适用**（标题 /
  进度 / 暂停均通用）：文件名保留 `music_mini_bar` 只是跟随路线图命名，
  见 §五。

## 四、在线元数据兜底框架（`eb3b2bf`，M4-T7，第 11 轮用户改向）

结论：本地 NFO / 海报（M4-T6）之后的联网补全**框架**轮。`lib/media/online/`
三件：provider 接缝（`metadata_provider.dart`）、TMDB /search/multi 适配器
（注入 http.Client，全部失败形态收束为一个类型化异常）、`OnlineMetaService`
（`lib/media/online/online_meta_service.dart:10-31` 门禁注释随行）。

- **五道门禁，每一道都不发网络请求**（`test/online_meta_service_test.dart`
  逐条锁定）：总开关关 → 无 API key → 本地 NFO 覆盖 → `media_online.json`
  缓存命中 → 才发起联网。本地优先是**构造保证**而非约定：目录里已有 NFO
  的视频永远不联网。
- **缓存语义**：唯一新 AppData 文件 `media_online.json`（沿用 M4-T6 的
  新文件先例，三份 §7 schema 一个字段不改，`data_compat_spec7_test.dart`
  在全量跑内通过）。正命中与**明确未命中**（格式良好的空结果）都落盘；
  传输失败（断网 / 超时 / HTTP 错误 / 损坏响应）**永不缓存**，下一次查询
  可在网络恢复后重试。原子写（兄弟临时文件 + rename）、损坏 / 缺失降级为
  空内存缓存。
- **设置与 UI**：设置中心新增「在线元数据」分类：总开关**默认关**（本地
  优先）+ TMDB API key 输入项（掩码显示，settings.json 增 `online` 段）；
  媒体库 NFO 详情弹层挂「联网补全」动作，收藏角标（badge）拓宽到全部视频
  格子（无 NFO 格子 tooltip 即联网补全），七种结果（关 / 无 key / 本地覆盖 /
  缓存命中 / 未命中 / 命中 / 网络 failure）各有优雅提示。
- **可达性实测（施工轮，2026-11-12）**：api.themoviedb.org 可达：
  curl 0.83 s / Dart HttpClient 1.04 s；无效 key 恰返 HTTP 401 标准错误体
  （2026-11-11 GitHub API 的 TLS ECONNRESET 未复现于 TMDB）。**真实联网
  数据流待用户填入有效 TMDB key 后人工验收（pending）**：这是框架轮的
  边界，不是遗漏。

## 五、已知取舍

1. **replaygain / gapless 的听感未人工验收**：runtime setProperty 接受 +
   回读一致只到属性层，增益与无缝的听感生效属 mpv 选项自身契约
   （SPEC §9 人工验收挂账）。
2. **TMDB 真实数据流未测**：mock 全绿 + 可达性实测到位，但没有有效 key
   就没有真联网验收；上线前用户必须自测一轮。
3. **迷你条命名与覆盖面**：`music_mini_bar` 对视频条目同样生效（文件名
   跟随路线图 M5-T3 命名）；播放页自身不显示迷你条（pageCurrent 排除），
   设计如此。
4. **病态双语 lrc**：`[t][t] 同文` 这类同时间戳同文本行照原样重复显示，
   与文件内容一致，不做纠偏。
5. **列表循环不走引擎多 entry playlist**：回卷在应用层（每文件一个 Player
   实例，沿用播放页架构），换来 completed 语义可达与队列事实源统一；代价
   是回卷依赖应用层管线（`PlayerProgressPipeline`），引擎侧单文件语义不变。
6. **CI 签名 539 / 1 为预期值**：R11 四提交未推送（ahead 4），远端尚未
   载入本轮；推送后按坑 2 的归因链核对（run 标题只显示头提交）。
7. **路线图勾选回填在工作树**：M4-T7 补哈希、M5-T1/T2/T3 ☐→✅+哈希，随
   本轮文档提交入库（同 R10 惯例）。
