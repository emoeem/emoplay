# 更新说明 · 2026-11-10（M4 媒体库升级 R10）

> 媒体库从「文件列表」升级为「媒体库」：统一的 `MediaItem` 数据模型 +
> ffprobe 元数据缓存、网格四种分组（目录 / 年月 / 剧集 / 电影）、收藏集
> （拖拽排序）、目录树侧栏，以及用户增补的**本地 NFO / 海报 / 剧集分组**，
> 全部事实来自本地文件，`<thumb>` URL 只记录不下载（本地优先纪律）。
> 顺带清偿 R9 挂账第一项：1614 行的 `player_item.dart` 拆到 484 行。
> 54 文件 489 用例全绿，三份 §7 schema 一字段未改（`data_compat` 契约测试
> 在全量跑内实测通过）。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `5fedee0`（2026-11-12 04:50 CST，R10: local nfo posters episode grouping）。本轮四提交（`c9245f8` 03:14 / `0da4a95` 03:36 / `25dd830` 04:18 / `5fedee0` 04:50，均 2026-11-12）落在 11-11~11-12 窗口，文档沿用 2026-11-10 计划窗口命名（同 R1-R9 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试 / CI 探测（gh 本窗口恢复可达，详见[工作报告 §3](../reports/WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md)）；Windows / macOS / Android / arm64 待 CI 与实体机验证 |
| 自动化测试 | **54 文件 / 489 通过 + 1 平台条件跳过，全绿**（上轮 44 文件 / 411 通过 + 1 跳过；+10 文件 / +78 用例。78 的构成逐文件实测点数：mappers 11、meta cache 9、favorites 7、folder tree 5、grid grouping 6、episode grouper 13、NFO UI 1、NFO meta cache 10、NFO parser 10、poster finder 6，合计与全量差值 489−411 一致，见工作报告 §3） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 4.8s)`，2026-11-12 本文档窗口实测）                                                                 |
| CI         | gh 本窗口恢复可达：R9 尾提交 `e9bf692` 已推送，main run 43069268623 ✓（2m47s）；v2.1.0-alpha release run 43069322152 ✓（14m25s；首跑 43068258121 ✗ 缺 ffmpeg，`e9bf692` 补装后全绿），release 已公开（11 资产，2026-11-12 01:50 CST）。本轮四提交未推送（ahead 4），推送后预期签名 **489 passed / 1 skipped**（未测：远端尚未载入 R10） |

## 一、统一媒体模型与元数据缓存（`0da4a95`，M4-T0/T4）

结论：媒体库、历史与播放队列从此共享一个不可变事实集 `MediaItem`，ffprobe
能看到的容器 / 编码 / 分辨率进 `media_meta.json` 缓存；三份 §7 JSON 的落盘
层零触碰。

- **为什么要有统一模型**：M4 的每个新功能（分组、收藏、NFO、目录树）都
  需要「一个媒体文件是谁」这同一份事实。没有模型，每个功能各带一套临时
  字段、各写一次 join，后续每个功能都在放大不一致。`MediaItem` 的基础
  字段（title/type/size/duration/lastPlayed）逐字段对齐 §7 store 的既有
  语义（type 用分类器词汇、duration 0.0 = 未知、lastPlayed ISO 8601），
  3.0 扩展槽（容器/编码/宽高）全部可空且**永不写回三份 JSON**（
  `lib/models/media_item.dart:6` 头注释声明契约）。
- **播放队列收编**：播放页以 `PlaybackSession` 为事实源，observable 列表
  从 `items` 派生；对外的 playlist / currentIndex / setPlaylist 接口保持
  M1-M3 调用方原样。resume 语义仍归 `PendingResumeSeek`（SPEC §4.4
  不变量 4），session 只携带 `startPosition` 数据、不碰挂起 seek 的
  装填与消费（`lib/models/playback_session.dart:5` 注释随行）。
- **映射器是无损纯拷贝**：§7 样例文档进出 `MediaItem` 不丢字段，由
  `test/media_item_mappers_test.dart`（11 用例，超出路线图 ≥8 的验收线）
  锁住；`HistoryEntry.position` 是 resume 事实而非媒体事实，由
  open 时的 startPosition 承载，映射器头注释逐条写明取舍。
- **元数据缓存（M4-T4）**：两段 ffprobe 链（`-show_format` 容器 →
  `-show_streams` 编码 + 宽高），串行逐文件、30s 超时强杀（与缩略图链
  同一预算，SPEC §4.7 同一契约）。缓存键 `sha1(path + mtimeMs)` 与
  `ThumbnailService.cachePathFor` 的哈希输入逐字节相同，改一个文件，
  两套缓存同时失效。**默认值的选择理由**：部分失败仍缓存可用信息
  （format 段成功、streams 段失败 → 只缺编码不缺容器）；音频文件宽高
  为 null 而非 0；封面流（attached_pic）不算视频编码。无 ffprobe 时
  `probe` 报 available=false、请求直接丢弃不拉进程，**已缓存条目继续
  服务**（`lib/media/media_meta_cache.dart:176` 注释随行）；
  性能契约：缓存命中零进程（`metaFor` 一次 stat + map 查询）。

## 二、网格分组、收藏集与目录树（`25dd830`，M4-T2/T3/T5）

结论：媒体库网格改 SliverGrid + pinned 分组头，新增收藏集（独立
`favorites.json`）与目录侧栏（面包屑 + 树），三者全部复用既有数据源，
不加新扫描。

- **网格分组**：分组键 / 分桶 / 输入序保持的契约在
  `lib/pages/library/library_grid_groups.dart` 头注释声明（caller 的输入
  序除组内确定性排序外从不重排）；search / typeFilter / sortMode 既有
  语义不变（在过滤后的列表上分组）。初始交付目录 / 年月两种分组
  （Kazumi popular_page 的 SliverGrid + pinned 范式），剧集 / 电影两种
  随 §三的 M4-T6 到场。
- **收藏集（M4-T3）**：`favorites.json` 是**新增 AppData 文件**，文档
  形态 `{"version":1,"entries":[{"path":…,"addedAt":…}]}`，持久化的
  恰是路线图说的「条目 = MediaItem path + addedAt」，其余字段不复制：
  标题 / 类型 / lastPlayed 继续住在 §7 store，UI 渲染时对库索引做 join。
  这样收藏永远不会复制或改写 §7 数据，库重扫与 notePlayed 也碰不到
  收藏文件，反之亦然（`test/favorites_store_test.dart` 7 用例锁定隔离、
  去重、损坏降级、原子写）。**排序即数据**：列表顺序就是用户的收藏
  顺序，`FavoritesSheet` 用 ReorderableListView + 显式拖拽柄（桌面友好
  形态，PiliPlus fav_folder_sort 范式），每次拖动即时落盘。失效收藏
  （文件已移出库）降级显示文件名，收藏本身保留到用户手动移除
  （`lib/pages/library/favorites_sheet.dart:8` 注释）。
- **目录树侧栏（M4-T5）**：数据源是 `LibraryStore` 已有的目录事实 +
  新暴露的 `scanOptions`（`lib/media/library_store.dart:209` getter），
  树的深度剪枝与扫描器语义一致（树在扫描停的地方结束），**不加新
  扫描**：这是路线图验收原文，也是性能守卫（R3 三用例）仍绿的原因。

## 三、本地 NFO / 海报 / 剧集分组（`5fedee0`，M4-T6·用户增补）

结论：Kodi 约定的本地刮削数据全链落地，NFO 容错解析、海报四名约定
定位、剧集名 `SxxEyy` 分组、`media_nfo.json` 缓存与详情弹层；全程零
网络请求（代码里没有 http import，按构造保证）。

- **NFO 解析是手写的容错读取器，不是 XML 包**：真实世界的 .nfo 是
  敌意的：根元素前有刮削器残留垃圾（`1http://forum.xbmc.org/` 这类）、
  BOM、注释、CDATA 包裹、截断下载、实体转义标题。严格 XML 包会把整份
  文件拒掉，而这里的契约是**降级不崩溃**：哪个字段解析坏了就跳过哪个，
  记录保持可用。Kodi 语义逐条对齐：类型看根元素（`<movie>` / `<tvshow>`
  / `<episodedetails>`）不看文件名；跳过首个根元素之前的垃圾；一份文件
  多个根时第一块赢（Kodi 首集行为）；`<thumb>` 带属性且可重复，全部
  原样收集（`lib/media/nfo_parser.dart:5` 注释随行）。
- **海报四名约定**：sidecar（`<文件名>-poster.jpg`，如 S01E02.mkv 旁边
  的 S01E02-poster.jpg）→ `poster.jpg` → `folder.jpg` → `fanart.jpg`，
  最具体的优先；fanart 按 Kodi 语义是背景图，排末位。**只有这四个**
  （png 变体、父目录、`<名>-fanart.jpg` 都不探测），增补清单枚举的就是
  这四个，不做超集（`lib/media/poster_finder.dart:5` 注释）。
- **剧集分组**：文件名 `S01E02`（大小写 / 补零不敏感）与 `1x02` 两种
  惯例，**词边界守卫**（标记前不能是字母数字，所以 `M4S01E02` 是文件名
  而不是「M4 剧的 1 集」）；剧 → 季 → 集三级（季 0 特典排最前，集号升序），
  无标记的条目原样落「未分组」桶，**一行都不丢**，怎么展示由调用方
  决定（`lib/media/episode_grouper.dart:5` 注释）。网格里剧集视图用嵌套
  SliverMainAxisGroups + pinned 头；电影视图把无剧集标记的视频按电影
  标题分组（NFO 有标题时覆盖文件名）。
- **缓存失效的坑提前想过了**：`media_nfo.json` 的条目同时携带视频 mtime
  与**目录** mtime，因为增删 poster.jpg / `<视频>.nfo` / tvshow.nfo 改的是
  目录的 mtime 而不是视频的，只看视频 mtime 会永远端着旧海报
  （`lib/media/nfo_meta_cache.dart:26` 注释）。请求走串行链（一次一扫，
  等待者并入在途路径），扫库级请求风暴不会交错。
- **UI 克制（Kazumi 风格）**：网格格子上是本地海报、剧集视图用 NFO 集
  标题做格子标题、有 NFO 数据的格子带 info 角标打开详情弹层
  （`nfo_details_sheet.dart`：海报 + 解析字段 + `<thumb>` URL 以**文本**
  展示，告诉用户 NFO 里有什么，抓取留给用户自己或第 11 轮的联网兜底）。
  角标只在 `hasNfo` 时存在，弹层永远有话可说；NFO 损坏的记录照样能开
  （字段降级不崩）。

## 四、播放器拆分（`c9245f8`，M3-T0·内部重构）

结论：R9 挂账第一项清偿，`player_item.dart` 从 1614 行（R9 实测，审计
时 1506）拆到 **484 行**（路线图验收线 <500），拆出 PiP / 音频绑定 /
键盘 / 菜单 / 手势 / 面板持有 / 进度管线 / 截图动作 / 截图胶片 / 超分
提示十个职责文件（全部 <600 行，`player_screenshot_sheet.dart` 复审后
1052 → 855 行）。纯搬移不改行为，用户可感知变化为零；拆分行数逐文件
复测见[工作报告 §3](../reports/WORK_REPORT_2026-11-10_M4_MEDIA_LIBRARY.md)。
版本号本轮未动（仍 `2.1.0-alpha+2010000`，未发版）。

## 五、已知取舍

1. **分组方式是会话态，不持久化**：`_groupMode` 是页面 `setState` 字段、
   无设置键（`lib/pages/library/library_page.dart:76`，默认按目录分组；
   2026-11-12 grep `lib/settings/` 零命中实测），重启回默认。目录侧栏
   开合与收藏弹层同理。是否值得持久化留作产品决策（工作报告 §6 建议 4）。
2. **海报约定只有四个文件名**：png 变体、父目录海报、`<名>-fanart.jpg`
   均不探测；约定之外的库拿不到海报，属增补范围的有意收窄而非缺陷。
3. **`<thumb>` URL 只记录不下载**：本地优先纪律（SPEC §4）在代码构造层
   保证（无 http import）；联网元数据兜底已由用户决策排期第 11 轮、排在
   本地 NFO 之后（路线图工作树改向注记，随本轮文档提交）。
4. **剧集识别只认文件名**：SxxEyy / 1x02 两种惯例 + 词边界；目录名里的
   「第一季」等人类语义、文件内部元数据（mkv 标题轨）都不参与识别；
   无标记条目落「未分组」桶，不猜测。
5. **新增三个 AppData 落盘文件**（`favorites.json` / `media_meta.json` /
   `media_nfo.json`）：**新增文件 ≠ 改 §7 schema**，history.json /
   library.json / settings.json 一字段未动（`data_compat_spec7_test.dart`
   全量跑内绿），三个新文件各带损坏降级与原子写测试；这是 M4-T3/T4
   先例的第三次使用。
6. **CI 与推送状态**：本轮四提交未推送（ahead 4），预期签名
   489 passed / 1 skipped **未测**；gh 可达性是窗口性的（R7-R9 曾整窗
   EOF），推送与盯签名仍是人工步骤。
7. **测试环境两处降级**：`/tmp/emoplay-perf-lib` 与 AUDIO_PROBE 夹具
   缺失（R7 夹具随 /tmp 清理消失），perf 基准 4 段与音频探针按设计
   skip-打印降级通过（计数不变）；live libmpv 用例真跑不受影响。
   夹具可用 `tools/gen_perf_fixture.sh` 重建。
8. **快捷键设置页的章节 / 循环 / 逐帧两组缺口沿袭 R9**：本轮零触碰
   settings 页（`git diff e9bf692..HEAD --stat -- lib/settings/` 输出为空
   实测），五键仍生效但设置页不可见，挂账继续有效。
