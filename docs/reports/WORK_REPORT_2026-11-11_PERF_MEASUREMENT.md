# 工作报告 · 2026-11-11（R7 施工件 A · 性能定量实测）

| 项           | 值                                                                 |
| ------------ | ------------------------------------------------------------------ |
| 报告日期     | 2026-11-11                                                          |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）   |
| 基线         | git `e1db680`（HEAD，R6 卫生与交付形态）                            |
| 对应路线图   | `UPGRADE_ROADMAP_2026-11-10.md` §4.1「性能实测」（本轮 ☐→✅）        |
| 执行环境     | 容器（/opt/emoplay-env.sh 工具链，无 GUI、无显示、宿主零污染）      |

## 1. 本轮范围

ROADMAP §4.1 的「☐ 性能实测」悬了四轮（R3 只交付了响应性守卫
`test/performance_guards_test.dart`，报告明确墙钟数字与首帧时间"需实机"）。
本轮把三件事变成实测数字，全部容器内可完成、不依赖 GUI：

1. 大库扫描吞吐（2000 文件夹具，wall-clock + 进度回调次数）；
2. 首帧路径（runApp 之前同步 IO 静态清单 + 2000 条目 jsonDecode/装载耗时）；
3. 缩略图节流（串行生成链的实测吞吐段，守卫测试保持不动）。

**标定声明（每段数字同口径）**：以下全部数字为**容器 Isolate 计时**，即
`flutter_tester` 进程内 `DateTime.now()` 墙钟，跑在本次施工容器上。**不是
宿主基线**：共享核、容器文件系统与测试 harness 都会移动它。数字回答的是
"2000 条目量级下算法成本多大"（逐文件让出事件循环的遍历、32 步长进度节流、
启动同步 JSON 装载），宿主实机数字仍归 SPEC §9 人工验收轮。

## 2. 夹具

`tools/gen_perf_fixture.sh`（新增，幂等，夹具只进 /tmp 不进仓库）：

- 路径 `/tmp/emoplay-perf-lib`，标记文件 `.perf-fixture-ok`；
- 2000 个 4KiB 随机字节文件（扫描只看扩展名 + stat，不读内容，
  `lib/media/library_store.dart:405-440`）；
- 布局：根目录 + 16 个 group × 10 个 sub = 176 目录；文件分布
  深度 0/1/2 = 400/600/1000（全部落在默认 `ScanOptions.maxDepth=2` 包络内）；
- 实测生成 ~14.5s（`dd` urandom），7.9MB；重跑走幂等分支直接保留。

测试文件 `test/perf_scan_benchmark_test.dart`（新增）按 audio_probe 模式
skip-if-fixture-missing：夹具缺失时 1/3 段打印 `PERF ... skipped` 直接通过
（已实测验证：把夹具改名挪走后全套 4 用例仍全绿，首帧段自动降级为合成
2000 条目文档继续给数，数字与真实扫描输出同量级）；夹具恢复后重跑正常。

## 3. 扫描吞吐实测

### 3.1 生产路径（worker isolate 端到端，`LibraryStore.requestScan()`）

含 isolate 首次孵化 + 目录添加 + 持久化 + 结果应用的通知开销，即 UI 真实
支付的路径：

| 跑次 | 首扫（含 isolate spawn） | 热扫 | 热扫吞吐 |
| --- | --- | --- | --- |
| 1 | 204 ms | 125 ms | 16000 files/s |
| 2 | 221 ms | 125 ms | 16000 files/s |

两次扫描期间 store 共通知 135 次，`scanFileCount` 终值 2000。整进程 RSS
提示（VmRSS，整 tester 进程口径，非泄漏计量）：128.4→139.4 MB（跑次 1）、
128.9→146.9 MB（跑次 2）。

### 3.2 直连遍历（`LibraryStore.scanDirectories` + 真实 progress 回调）

| 跑次 | 冷 | 热 | 冷/热吞吐 | 进度回调次数（冷/热） |
| --- | --- | --- | --- | --- |
| 1 | 160 ms | 166 ms | 12500 / 12048 files/s | 63 / 63 |
| 2 | 179 ms | 150 ms | 11173 / 13333 files/s | 63 / 63 |

63 次正是节流形状的实数：中间步 2000÷32=62 次（每第 32 个文件一步，
`library_store.dart:437`）+ 收尾 1 次（`:464`）。逐文件洪泛会是 2000 次。
守卫测试的"不逐文件"上限（`performance_guards_test.dart:129`）在本量级下
有了实测值。测试内同时断言 `calls.length == 2000 ~/ 32 + 1`。

## 4. 首帧路径

### 4.1 静态清单（runApp 之前的同步 IO，逐点核实）

启动链：`main()`（`lib/main.dart:26`）→ `MediaKit.ensureInitialized()`
（`:28`）→ **`await MediaStores.init()`（`:35`，首帧临界路径）** → Hive +
GStorage（`:49-51`）→ windowManager（`:79-96`）→ `runApp`（`:101`）→
首帧。`MediaStores.init`（`lib/media/media_stores.dart:115`）内的同步 IO：

| 点 | 位置 | 内容 |
| --- | --- | --- |
| settings.load() | `media_stores.dart:123` → `emoplay_settings.dart:332,339` | settings.json `readAsStringSync` + `jsonDecode` |
| CompatController 构造 | `media_stores.dart:129-134` → `mpv_profile_scanner.dart:121,162,167,174` | 默认 mpv 配置目录探测（existsSync 数次） |
| 内置插件目录资产 | `media_stores.dart:142-146` | `rootBundle.loadString`（异步资产读） |
| compat.startupOptions() | `media_stores.dart:160` → `compat_controller.dart:113,162` | 再次 `settings.load()` + `MpvProfileScanner.scan`（用户 mpv 目录 listSync 遍历，`mpv_profile_scanner.dart:289-328`）+ mpv.conf `readAsStringSync` |
| **LibraryStore 构造** | `media_stores.dart:174` → `library_store.dart:729,736,757-766` | **library.json `readAsStringSync` + `jsonDecode` + 2000 条目逐条 fromJson** |
| ThumbnailService | `media_stores.dart:183-184` → `thumbnail_service.dart:110` | mkdirSync + `unawaited(probe())`（异步，不在临界路径） |
| HistoryStore 构造 | `media_stores.dart:186` → `history_store.dart:106,276` | history.json `readAsStringSync` + `jsonDecode` |
| PluginManager 构造 | `media_stores.dart:147` → `plugin_manager.dart:327,333` | 插件安装状态 JSON 同步读 |

另实测确认：**大库扫描不在启动路径上**。`requestScan()` 只由媒体库页两个
按钮触发（`lib/pages/library/library_page.dart:316,402`），`MediaStores.init`
不发起扫描。启动同步 JSON 工作量 = 若干小文件 + 唯一可能大的 library.json。

### 4.2 2000 条目 library.json 装载实测

文档为真实扫描输出回写（234 KiB，`_save()` 同构形）：

| 跑次 | jsonDecode 中位（20 次） | LibraryStore 构造中位（完整同步 `_load`，5 次） |
| --- | --- | --- |
| 1 | 1.44 ms | 1.70 ms |
| 2 | 1.82 ms | 2.13 ms |

夹具缺失时合成文档（254 KiB，同形同量）给出同量级数字：1.90 ms / 2.15 ms。

**判定**：按本轮阈值（>100ms 同步阻塞才考虑改代码），2000 条目量级的
`_load` 全程约 2ms，距阈值两个数量级，**不改代码**。若未来用户库达到
十万条目量级（~100ms 线性外推），再考虑把 `_load` 移入 worker isolate；
现在动它是无实测依据的过早优化。

### 4.3 未测（如实标注）

- **GUI 首帧墙钟**（runApp→首帧上屏）：容器无显示，SPEC §9 人工验收轮口径；
- **真 ffmpeg 缩略图生成速率**（见 §5 的 stub 说明）；
- **宿主基线数字**：见 §1 标定声明。

## 5. 缩略图串行链实测（守卫测试之上的补测段）

守卫测试 `performance_guards_test.dart`（本轮只改文件头注释加指针）已锁
"至多一个 ffmpeg 子进程"不变量；本轮在同形 stub 上补吞吐实测
（24 个夹具文件入队，stub 时长探针 5ms + 取帧 30ms/作业，flock 跨进程
并发标记同口径）：

| 跑次 | 总墙钟 | 单作业 | 吞吐 | ffmpeg 调用数 | 并发重叠 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1850 ms | 77.1 ms | 13.0 jobs/s | 49（= 1 探针 + 24×2） | **0** |
| 2 | 1873 ms | 78.0 ms | 12.8 jobs/s | 49 | **0** |
| 3 | 1953 ms | 81.4 ms | 12.3 jobs/s | 49 | **0** |

读数：stub 自身脚本睡眠 35ms/作业，实测 77-81ms/作业。差额是每作业两段
shell 子进程孵化 + 服务双阶段（探针→取帧）调度开销在容器 tester 里的体现；
关键结论是并发重叠计数恒为 0（串行契约在实测跑里成立），单作业成本线性
可外推（1.x `ThumbnailService.h:16` 串行形状的量化口径）。

## 6. 本轮自查与门禁

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 基准测试（夹具在场） | `flutter test test/perf_scan_benchmark_test.dart` | 4 用例全绿（共跑 4 次，数字见 §3-§5） |
| 基准测试（夹具缺失） | 改名夹具后同命令 | 4 用例全绿（skip 打印 + 合成降级），夹具已恢复原位 |
| 静态检查 | `flutter analyze` | `No issues found!`（自引入 3 条 lint 当场清零） |
| 全量测试 | `flutter test` | **36 文件 349 通过 + 1 跳过，0 失败**（R6 基线 35 文件 345+1 + 本文件 4 用例，只增不减） |

完整 linux 构建与 build_runner 未在本轮执行，按施工指令由工作流统一跑
门禁序列（build_runner → analyze → test → build）；本轮未 git commit。

## 7. 交付物与路线图回写

| 产物 | 说明 |
| --- | --- |
| `test/perf_scan_benchmark_test.dart`（新增） | 4 段基准；skip-if-fixture-missing；每段打印标定声明 |
| `tools/gen_perf_fixture.sh`（新增） | 2000 文件夹具生成器（幂等，夹具只在 /tmp） |
| `test/performance_guards_test.dart`（注释） | 文件头"out of scope"段补指向本基准文件 |
| `UPGRADE_ROADMAP_2026-11-10.md` §4.1 | 「☐ 性能实测」→「✅（容器环境实测）」+ 数字摘要 + 残余范围声明 |
| `docs/README.md` | 报告索引登记本文件 |

ROADMAP 回写后该条目残余范围如实保留：**容器 Isolate 计时 ≠ 宿主基线**；
GUI 首帧上屏墙钟与真 ffmpeg 生成速率仍归 SPEC §9 人工验收轮（§4.3/§5）。
