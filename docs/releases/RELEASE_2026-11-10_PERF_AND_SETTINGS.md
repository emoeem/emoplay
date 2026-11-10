# 更新说明 · 2026-11-10（性能实测与设置收尾 R7）

> 设置 → 通用新增「恢复默认设置」：危险确认后画质 / 常规 / 均衡器三分区
> 回安装时默认，媒体库与观看历史一根手指都不碰（1.x 对账最后一项消账）。
> 性能无行为变化，交付量化证据：2000 文件量级的扫描 / 装载 / 缩略图串行
> 链实测数字落进基准与报告。tag 发布同轮改 draft 制：alpha 产物先落草稿、
> 人工核对才公开，不再直接占 Latest 位。37 文件 355 用例全绿。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `0a3436c`（2026-11-11 03:37 CST，R7: ldd note + draft release）。本轮三个提交（`87b3760` 02:55 / `d971af0` 03:25 / `0a3436c` 03:37）落在 11-11 凌晨窗口，文档沿用 2026-11-10 夜间窗口命名（同 R1-R6 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试（含真夹具基准段）/ CI 探测（详见工作报告 §3）；Windows / macOS / Android / arm64 待 CI 与实体机验证                        |
| 自动化测试 | **37 文件 / 355 通过 + 1 平台条件跳过，全绿**（上轮 35 文件 / 345 通过 + 1 跳过；+2 文件 / +10 用例 = `test/perf_scan_benchmark_test.dart` 4 段基准 + `test/general_settings_l10n_test.dart` 5 用例 + settings 语义 1 用例） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 8.3s)`，2026-11-11 03:40 CST 本文档窗口实测）                                                       |
| CI         | 本窗口不可测：`gh run list -R emoeem/emoplay` EOF（api.github.com 不可达，03:41 CST 实测）；R7 三提交未推送（本地 origin/main 跟踪引用已到 `e1db680`，即最后一次 fetch/push 时点远端已含 R5/R6 六提交；远端当前状态因 EOF 不可复核）。推送后预期签名 **355 passed / 1 skipped**（CI 无 /tmp 夹具时基准段自动降级为 skip-打印，计数不变） |

## 一、设置：恢复默认设置（`d971af0`）

结论：1.x 对账清单的最后一项残余消账，`restoreDefaultsKeepsMediaAndHistory`
槽位在 2.0 有了真实 UI 与真实语义测试。入口在设置 → 通用页底部，走
EmoDialog 危险样式确认（error 前景确认键 + `settings_backup_restore_rounded`
图标），确认后三分区回默认。

**规格来源是 1.x，不是新发明**：行为以旧仓库
`src/settings/SettingsService.cpp:72` 的 `restoreDefaults()` 与
`tests/test_settings_service.cpp:102` 的 `restoreDefaultsKeepsMediaAndHistory`
为规格（本轮在只读旧仓库 grep 实测确认两处存在）。那条契约的核心是
「恢复设置永不破坏用户数据」：

- **动的**：quality（内容模式 / 档位 / tone mapping / 超分覆盖 / deband /
  手动着色器列表 / 插帧 / ICC）、behavior（继续播放 / 扫描深度 / 跳过隐藏
  文件）、music（均衡器开关 / 预设 / 十频段增益）三分区，见
  `lib/settings/emoplay_settings.dart:500` 的 `restoreDefaults()`。
- **不动的**：媒体库 library.json、观看历史 history.json、mpv 配置导入
  决策（导入决策是用户被明确问过一次的选择，重置它在 mpv 配置页有自己
  的「重置导入决策」tile，两件事不混）。
- **默认值的选择理由**：恢复目标一律取构造函数默认值 = 1.x schema 默认
  （`qualityTier: 'off'`、`libraryMaxDepth: 2`、均衡器预设 `flat` 等），
  其中 `qualityTier` / `debandMode` 保留 1.x 的域值字符串以兼容旧配置文件
  解析。理由：恢复的语义是「回到安装时行为」，不趁机夹带新的产品默认；
  若要改默认值那是独立决策，走 SPEC §10 兜底流程，不借恢复入口偷渡。
- **恢复后页面即时刷新**（`lib/pages/settings/general_settings.dart:135`
  的 `_applyRestoreDefaults`）：`save()` 落盘后把新值推进会话控制器
  （画质 / 插帧 / ICC 的 MobX 镜像与均衡器控制器各走 `reloadFromSettings`）
  并 `LibraryStore.setScanOptions` 同步扫描参数。为什么必须推：这些镜像
  只在自家 setter 里重同步，不推进的话画质页与音频页在重启前一直显示旧
  值，「恢复了」看起来像没生效。
- **i18n**：通用设置页是第三个整体迁移到 AppLocalizations 的设置页
  （页签壳 R3、音频设置 R4 之后），zh / en 双语齐备（含恢复默认确认
  文案 `restoreDefaultsDialogTitle/Content/Confirm` 等键）。
- **守护测试**：`test/general_settings_l10n_test.dart`（新增，5 用例）
  headless 挂载真实页面（MediaStores-under-fake-path-provider 自举，
  不碰用户数据），锁双语渲染 + 确认对话框取消不动任何分区 + 确认后
  三分区复位且页面即时刷新；`test/settings_service_semantics_test.dart`
  新增 `restoreDefaultsKeepsMediaAndHistory`（`:139`）：seed 全部非默认值
  后恢复，并断言真实 library.json / history.json 逐字节不变。

## 二、性能实测（`87b3760`）：无行为变化，交付的是证据

结论：路线图 §4.1「性能实测」☐→✅（容器环境实测口径）。功能零变化，
交付的是三段基准资产 + 实测数字，回答「2000 条目量级下算法成本多大」：

- **资产**：`test/perf_scan_benchmark_test.dart`（4 段基准，
  skip-if-fixture-missing，CI 与无夹具环境自动降级通过，不红）+
  `tools/gen_perf_fixture.sh`（2000 文件夹具生成器，幂等，夹具只进
  /tmp 不进仓库）。
- **数字摘要**（全录
  [WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md](../reports/WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md)）：
  worker isolate 生产路径热扫 125ms（16000 files/s）；直连遍历进度回调
  实测 63 次（32 步长 + 收尾，逐文件洪泛会是 2000 次）；2000 条目
  library.json（234KiB）同步装载全程中位 1.70-2.13ms，远低于 >100ms
  阻塞阈值，**判定：不改代码**，十万条目量级前动它是无实测依据的过早
  优化；缩略图串行链 77-81ms/作业、并发重叠实测 0（串行契约成立）。
- **标定声明**：以上全部为容器 Isolate 计时（`flutter_tester` 进程内
  墙钟），**不是宿主基线**；GUI 首帧上屏墙钟与真 ffmpeg 生成速率仍归
  SPEC §9 人工验收轮。

## 三、发布与打包注记（`0a3436c`）

结论：两件事，一是 tag 发布改 draft 制（防 alpha 误占 Latest），二是 deb
打包注释补库数口径考证（面向维护者，无行为变化）。

- **draft 制**（`.github/workflows/release.yaml:341`）：tag 触发的
  `Create release` 步加 `draft: true`，跑完是草稿，不公开、不占
  Latest，草稿也不能被设为 Latest。为什么：v2.0.0-alpha 曾以正式版
  语义占据公开 Latest 位（`softprops/action-gh-release` 未设 prerelease，
  R4 遗留语义问题），draft 让每次 tag run 的产物先经人工核对再公开。
  人工 publish 命令 `gh release edit <tag> --draft=false`，完整流程在
  [guides/BUILD_GUIDE.md](../guides/BUILD_GUIDE.md) §四（本提交新增 76 行）。
  **注意主要失效模式：忘 publish，草稿在公开 Releases 页看不到。**
- **deb control 注释考证**（`.github/scripts/package-linux.sh` 依赖清单
  注释段）：审计 P2 重测的库数口径（直连 NEEDED 并集 63 个 soname、
  ldd 传递闭包 125 路径 = 9 内嵌 + 116 外部、另有 3 个 dlopen-only 内嵌库
  从不进 ldd 输出）与历史五口径（250/234/166/64/113）的分歧逐项写明
  统计范围；64→63 正对应 R6 移除 `screen_brightness_ohos`。这是注释级
  修复：数字本身 R3 已实测，此前注释里的「115」是把不同口径混写成的
  孤例，留着会误导下一个做依赖审计的人。

## 四、已知取舍

- **恢复默认不提供撤销**：确认对话框是唯一防线，恢复后旧值不留档（1.x
  同语义）；用户数据（库 / 历史 / 导入决策）不受影响是测试断言过的底线。
- **draft 制未经过一次真实 tag run 验证**：本轮未打 tag，`draft: true`
  行为以 workflow 语法与 BUILD_GUIDE 流程文档为准，下次 tag 演练实测
  确认（含「草稿不可见、publish 后公开」两步）。
- **性能数字是容器口径**：容器 Isolate 计时 ≠ 宿主基线；宿主实机墙钟
  与 GUI 首帧归 SPEC §9 人工验收轮，本发布说明不宣称任何实机性能结论。
- **CI 本窗口不可测**：api.github.com 不可达（03:41 CST EOF 实测）；
  「推送后预期 355 passed / 1 skipped」是推算值（本地全绿 + R3/R4 两轮
  「预期签名 = 实测签名」先例），非已实测结论。
- **i18n 迁移仍是页面级渐进**：页签壳 / 音频设置 / 通用设置三页已迁，
  其余页面字符串未动，继续按路线图 §4.2 逐页推进。
- 与既有已知限制一致、本轮无变化：产物未签名 / 实体机验证 ☐ / iOS 进
  发布矩阵 ☐ / connectivity_plus 去留待评估。
