# 工作报告 · 2026-11-10（性能实测与设置收尾 R7 · 文档收网）

| 项           | 值                                                                                    |
| ------------ | ------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-11（文档收网窗口 03:40-03:55 CST）                                            |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                     |
| 版本         | git `0a3436c`（HEAD，本轮施工三提交的最后一个）                                       |
| 对应更新记录 | [`RELEASE_2026-11-10_PERF_AND_SETTINGS.md`](../releases/RELEASE_2026-11-10_PERF_AND_SETTINGS.md) |
| 相关         | 施工件 A 的定量报告：[`WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md`](WORK_REPORT_2026-11-11_PERF_MEASUREMENT.md)；路线图 `UPGRADE_ROADMAP_2026-11-10.md` §4.1 |

## 1. 本轮范围

三个施工提交加一个文档收网（本报告），依据是路线图 §四 未做项与 1.x 对账
清单的最后一行：

1. `87b3760` 性能实测（施工件 A）：路线图 §4.1「性能实测」☐→✅，容器
   环境定量（扫描吞吐 / 首帧装载 / 缩略图串行链）。数字、夹具与标定声明
   全在施工件 A 的独立报告里，本报告不重复，只记门禁与对账结论。
2. `d971af0` 设置收尾（施工件 B）：1.x `SettingsService::restoreDefaults`
   的 UI 槽位落地（设置 → 通用「恢复默认设置」），顺带把通用设置页整体
   迁到 AppLocalizations（第三个迁移页）。
3. `0a3436c` 打包注记：tag 发布改 draft 制（release.yaml + BUILD_GUIDE
   §四 流程文档）、deb control 注释补库数口径考证。
4. 文档收网（本提交）：本轮发布说明 + 本报告 + HANDOVER 刷新 +
   docs/README.md 索引登记 + CHANGELOG 补 R7 节。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 路线图 | §4.1「性能实测」四轮悬空（R3 只交了响应性守卫） | 完成（施工件 A 回写 ☐→✅） | `UPGRADE_ROADMAP_2026-11-10.md:99`-`:110`；施工件 A 报告 §3-§5 |
| 对账 | 1.x `restoreDefaultsKeepsMediaAndHistory` 槽位无对应（旧仓库 `tests/test_settings_service.cpp:102`，2.0 无恢复默认 UI） | 完成（对账清单清零） | `lib/settings/emoplay_settings.dart:500`；`test/settings_service_semantics_test.dart:139`（断言 library.json / history.json 逐字节不变，本轮全量跑内实测通过） |
| i18n | 通用设置页整页硬编码中文/英文双轨字符串 | 完成（第三个迁移页） | `lib/pages/settings/general_settings.dart` + `lib/l10n/app_zh.arb:193`-`:202`（恢复默认四键）；`test/general_settings_l10n_test.dart` 5 用例挂真实页面 |
| 发布语义 | tag 触发的 release 直接公开，alpha 曾占 Latest 位（R4 遗留） | 完成（draft 制，全验待下次 tag run） | `.github/workflows/release.yaml:341` `draft: true`；流程文档 `docs/guides/BUILD_GUIDE.md:37` §四 |
| 文档 | deb 注释「115 库」孤例口径（历史五口径 250/234/166/64/113 与它互相矛盾） | 完成（注释考证） | `.github/scripts/package-linux.sh:58`-`:78` 注释段（63 直连 NEEDED / 125 ldd 闭包 / 116 外部 / 3 个 dlopen-only） |
| 文档 | 路线图勾选滞后三处（见 §5） | 挂账（本轮不改路线图） | `UPGRADE_ROADMAP_2026-11-10.md:119`（AppImage ☐，R6 已落地）、`:120`-`:122`（i18n 清单缺通用设置页）、`:125`-`:127`（对账残余 ☐，本轮已消账） |

## 3. 工程状态（实测）

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze`（03:40 CST） | `No issues found! (ran in 8.3s)`，0 告警 |
| 全量测试 | `flutter test`（03:41 CST） | `00:19 +355 ~1: All tests passed!`，**37 文件 / 355 通过 + 1 平台条件跳过**（R6 基线 35/345+1，本轮 +2 文件 +10 用例，只增不减） |
| 测试文件数 | `ls test/*_test.dart \| wc -l` | 37（35 + `perf_scan_benchmark_test.dart` + `general_settings_l10n_test.dart`） |
| 基准段口径 | `ls -d /tmp/emoplay-perf-lib` | 夹具在场：本轮全量里的 4 段基准按真实 2000 文件夹具执行（非 skip 降级） |
| CI | `gh run list -R emoeem/emoplay --limit 5`（03:41 CST） | `failed to get runs: ... EOF`，api.github.com 不可达，本窗口不可测 |
| 推送状态 | `git log --oneline origin/main..HEAD` | 3 个：`87b3760` / `d971af0` / `0a3436c`；本地 origin/main 跟踪引用已到 `e1db680`（最后一次 fetch/push 时点远端已含 R5/R6 六提交，远端当前状态因 EOF 不可复核） |
| 1.x 规格来源核实 | `grep -n restoreDefaults`（只读旧仓库） | `mpv-emo/src/settings/SettingsService.cpp:72`、`mpv-emo/tests/test_settings_service.cpp:102` 两处实存 |

完整 linux 构建与 build_runner 未在本文档轮执行（无原生构建面改动；
R5 实测 Linux debug 构建通过仍为底数）。基准数字均为施工件 A 的容器
Isolate 计时口径，本报告未复跑采集，只复跑通过性（上表第 3 行）。

## 4. 确认无问题的部分

- **恢复默认的数据安全契约**：`restoreDefaultsKeepsMediaAndHistory` 在
  全量跑内实测通过；测试体核实过（`test/settings_service_semantics_test.dart:139`-`:242`）：
  seed 全部非默认值 + 真实扫出一个 entry 的 library.json + 一条记录的
  history.json，恢复后断言两文件逐字节不变。1.x 同名用例的契约
  （`tests/test_settings_service.cpp:102`）逐条对得上。
- **CHANGELOG 一轮一节结构**：R6 收网修复后维持完好（R6 / R5 / R5-移动 /
  2.0.0-alpha 各自成节，互不卷入），本轮 R7 节按同一结构追加。
- **HANDOVER 坑 8(d) 与 release.yaml 一致**：`0a3436c` 预先写入的 draft
  制坑条与 workflow `draft: true` 行为、BUILD_GUIDE §四流程三处口径一致
  （本轮逐处核对）。
- **基准测试的降级路径**：施工件 A 已实测「夹具改名挪走后 4 用例仍全绿
  （skip 打印 + 合成降级）」；本轮夹具在场路径亦全绿（§3 第 4 行），
  两条路径都真跑过。
- **l10n 生成文件与 arb 同步**：`d971af0` 把生成文件一并提交，本轮
  analyze 0 告警 + l10n 测试 5 用例全绿证明生成物与 arb 一致（未单独跑
  `flutter gen-l10n` 幂等性验证，如实说明）。

## 5. 已知限制与未做项

**需要人工操作的**

- 推送 R7 三提交与本文档提交，盯 CI 签名是否 **355 passed / 1 skipped**
  （本地实测口径的推算值；CI 无 /tmp 夹具时基准段 skip-打印降级，计数
  不变）。
- 下次 tag 发布走 draft 流程：跑完核对产物集后手动
  `gh release edit <tag> --draft=false`（忘 publish = 新流程主要失效模式，
  `docs/guides/BUILD_GUIDE.md:37`）。
- GUI 手感人工验收与宿主基线性能（SPEC §9）：容器 Isolate 计时不能替代
  实机墙钟；发布产物实体机验证 ☐ 继续挂账。

**代码侧待办**

- 路线图勾选收网回写三处：§4.1 AppImage ☐（R6 `e1a2df0` 已落地）、
  §4.2 i18n 清单补通用设置页（R7 `d971af0`）、§4.2 测试对账残余 ☐
  （R7 已消账）。本轮文档轮按惯例不动路线图，挂账下次收网（R6 同例：
  HANDOVER 坑 4 的「以路线图下次收网为准」）。
- `test/kazumi_alignment_ui_test.dart` 头注释称 CI 有 hardcoded-color
  grep 把关，实测两个 workflow 无此步（R6 挂账延续，本轮仍未处理）。
- `connectivity_plus` 去留评估（R6 挂账延续）。

**固有限制**

- 性能数字为容器 Isolate 计时，非宿主基线；arm64 打包仅 CI 可验；
  api.github.com 在本窗口不可达（三轮连续实测），推送后 CI 结论只能
  事后核对。

## 6. 下一步建议

1. **推送并盯 CI**（最高优先）：9 个未推送提交（3 施工 + 文档轮）推
   origin/main，CI 预期 355 passed / 1 skipped；红灯按 HANDOVER 坑 2 的
   归因链处理，预期签名若出现偏差先查基准段在 runner 上的降级行为。
2. **路线图收网回写**：把 §2 表列出的三处滞后勾选态修进
   `UPGRADE_ROADMAP_2026-11-10.md`（一处 ✅、两处条目内容更新），并
   补 R6/R7 轮次表行。
3. **hardcoded-color grep 二选一**：在 pr.yaml 补 grep 步骤，或修
   `test/kazumi_alignment_ui_test.dart` 头注释（R6 报告 §5 的二选一，
   已拖一轮）。
4. **prerelease 语义决策**：draft 制落地后，beta/rc 打 tag 前把
   `softprops/action-gh-release` 的 prerelease 按 tag 后缀自动判定补上
   （路线图 §4.2 首项）。
5. **i18n 第四页**：沿 audio/general 两页先例继续迁移其余设置页
   （`flutter analyze` 0 告警 + l10n 测试挂真实页面的既有模式照抄）。
