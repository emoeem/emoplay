# 工作报告 · 2026-11-10（M6 插件安全 + M3-T1 帧预览 R12）

| 项           | 值                                                                              |
| ------------ | ------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-13（文档收网窗口，门禁由本报告轮重跑实测）                              |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写）                                       |
| 版本         | git `3514db3`（R12 施工尾提交，2026-11-13 00:30 CST）                            |
| 对应更新记录 | [`RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md`](../releases/RELEASE_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md) |

## 1. 本轮范围

第 12 轮施工收网。施工面是 [EMOPLAY-3.0-ROADMAP.md](../EMOPLAY-3.0-ROADMAP.md)
§五 M6 插件安全全部四任务（M6-T1 清单完整性 / T2 操作审计 / T3 暴力面
收缩 / T4 插件页 catalog）+ M3 残留首项 M3-T1 帧预览，外加一条用户
报告的 compat 层修复。五个施工提交 + 本轮文档收网（发布说明、轮级工作
报告、HANDOVER 刷新、docs/README.md 索引登记、CHANGELOG R12 节；路线图
M6 四任务与 M3-T1 的 ☐→✅+哈希回填已在工作树，随文档提交入库）。

- `757d130` R12: manifest sha256 + plugin audit（M6-T1/T2）：6 文件
  +882/-4（plugin_manifest +107、plugin_git_runner +146、plugin_manager
  +192、三个测试文件 +541，其中 plugin_audit_test 为新文件）
- `0919ccc` R12: destination fuzz + operations whitelist（M6-T3）：
  2 文件 +317/-4（plugin_manager 白名单 +39、plugin_manager_test fuzz 段
  +282）
- `07427f8` fix(compat): strip inline comments from mpv.conf values
  applied at runtime：4 文件 +109/-5（mpv_config_parser.runtimeOptionValue
  +32、mpv_import_rules +18、两个测试文件 +64；提交信息含完整根因链与
  用户报告日期）
- `7b89bb0` R12: plugin catalog view（M6-T4）：6 文件 +1406/-355
  （plugins_page 577→485 行、四个新职责文件、plugin_catalog_test 新 396 行）
- `3514db3` R12: seek preview controller（M3-T1）：10 文件 +1229/-23
  （seek_preview_controller 403 行新、player_progress_bar +147、
  settings 两键、seek_preview_controller_test 396 行新、
  performance_guards +131）

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 施工 | M6-T1 清单完整性：sizeBytes+sha256 缺一拒装 + 装前内容校验 | 完成 | `757d130`；`integrityGateError()`（`lib/plugins/plugin_manifest.dart`）、校验点在 install/update 链最前（`lib/plugins/plugin_manager.dart`）、`PluginContentIntegrity`（`lib/plugins/plugin_git_runner.dart`）；`plugin_manifest_test` +5（integrityPairIncompleteRefusedForInstall / malformedIntegrityFieldsRejectedAtParse / integrityFieldsRoundtrip / replaySameHashPasses / contentHashMismatchRejected，验收线 ≥4）+ `plugin_manager_test` +4（installRefusedBeforeAnyGitWhenIntegrityIncomplete / installWithPinnedContentVerifiesAfterClone / installWithTamperedContentRefusedAndCleaned / replaceUpdateVerifiesStagedContentBeforeSwap） |
| 施工 | M6-T2 操作审计：plan/operation 双事件 append-only 落盘 | 完成 | `757d130`；`PluginAuditLog`（`lib/plugins/plugin_manager.dart` 尾部）；新 `test/plugin_audit_test.dart` 5 用例（appendOnlyGrowsAndKeepsHistory / corruptedLinesAreSkippedOnRead / planOperationChainIsAudited / porcelainRefusalIsAudited / auditFileStaysInsideAppData，验收线 ≥4） |
| 施工 | M6-T3 暴力面收缩：destination 防穿越 fuzz + 操作白名单 | 完成 | `0919ccc`；`allowedOperations` 常量 + 默认拒绝（`lib/plugins/plugin_manager.dart`）；fuzz 语料 `kHostileDestinations` 12 条 + `kLookalikeDestinations` 4 条（`test/plugin_manager_test.dart:67,86`，验收线 ≥10）+ fuzzSymlinkedInstallTargetRefusedAndUntouched / fuzzIntegrityDigestIgnoresSymlinksPointingOutside + operationsWhitelistExplicitAndDefaultDeny，plugin_manager_test 共 +6 |
| 施工 | M6-T4 插件页 catalog 重组，三段式语义不变（不变量 6） | 完成 | `7b89bb0`；plugins_page 577→485 行 + 四新件（137/228/244/138 行，全部 <600）；新 `test/plugin_catalog_test.dart` 9 用例（7 逻辑 + 2 testWidgets：filterAndSearchShapeTheDirectoryWithoutMergingSections / executeConfirmedOperationIsTheOnlyFunnelToTheManager 等，验收线 ≥2） |
| 修复 | 带注释 mpv.conf 致无声（用户报告，两 alpha 版可复现） | 完成 | `07427f8`；根因 `MpvConfigParser.runtimeOptionValue`（`lib/mpv/config/mpv_config_parser.dart:137`）复刻 mpv 文件语义（空白前导 `#` 起注释、紧贴值首 `#` 保留为颜色码）；回归测试 5 条（mpv_config_parser_test +4 / mpv_import_rules_test +1）取自报告人真实 conf 行 |
| 施工 | M3-T1 帧预览：第二解码实例 + hover/拖动帧图 | 完成（属性层实测；画面效果待 GUI 人工验收） | `3514db3`；`seekPreviewMpvProperties` 等价表（`lib/pages/player/controller/seek_preview_controller.dart:62`，mpvpreview.cpp:21-38 逐项对照，差异考证随文件头）；新 `test/seek_preview_controller_test.dart` 10 用例（验收线 ≥6）+ `performance_guards_test` +2（实例数守卫）；属性集 live probe 2026-11-13 实测全过（控制器文件头记录） |
| 文档 | 路线图勾选回填 | 完成（工作树，随本轮文档提交入库） | `git diff docs/EMOPLAY-3.0-ROADMAP.md`：M3-T1 ✅（`3514db3`）、M6-T1/T2 ✅（`757d130`）、T3 ✅（`0919ccc`）、T4 ✅（`7b89bb0`），与五提交逐一相符 |
| 文档 | R12 文档收网五件 | 完成 | release + 本报告 + HANDOVER 刷新 + docs/README.md 索引 + CHANGELOG `[Unreleased]` R12 节（一轮一节） |

## 3. 工程状态（实测）

门禁全部在 2026-11-13 文档窗口由本文档轮重跑（命令先 `source /opt/emoplay-env.sh`）：

| 门禁 | 结果 |
| --- | --- |
| `flutter analyze` | **0 告警**（`No issues found! (ran in 7.6s)`） |
| `flutter test` | **63 文件 / 585 通过 + 1 平台条件跳过全绿**（reporter 尾行 `00:25 +585 ~1: All tests passed!`） |
| 测试文件计数 | `ls test/*_test.dart \| wc -l` = **63**（R11 为 60，+3：plugin_audit / plugin_catalog / seek_preview_controller）；`git ls-tree -r b87e1c8 --name-only test/` 计 54 = R10 底数核对一致 |
| 账目闭环 | 逐文件点数新增用例（`grep -cE '^\s*(test\|testWidgets)\('`，新文件全数、存量对 b87e1c8 差分）：plugin_manager 24-14=+10、seek_preview_controller 10（新）、plugin_catalog 9（新）、plugin_manifest 19-14=+5、plugin_audit 5（新）、mpv_config_parser 17-13=+4、performance_guards 5-3=+2、mpv_import_rules 13-12=+1，**合计 46 = 585-539** ✓ |
| 1 skip 身份 | `test/mpv_profile_scanner_test.dart:217` `locateOnWindowsUsesAppData`（skip 文案 `Windows-only probe (1.x QSKIP contract)`，与 R9-R11 同一身份） |
| CI（gh） | **本窗口不可测**：`gh run list -R emoeem/emoplay` EOF（api.github.com 不可达，2026-11-13） |
| 提交状态 | `git log origin/main..HEAD --oneline` = 2（`7b89bb0` / `3514db3`，ahead 2；origin/main 在 `07427f8`，即 R12 前三提交已推送、后两提交待推送） |
| 行数守卫 | plugins_page 577→485 行，四个新职责文件 137/228/244/138 行，seek_preview_controller 403 行，全部 <600（路线图 M3-T0 先例的行数约定延续） |

## 4. 确认无问题的部分

- **§7 三份 schema 零触碰**：本轮唯一新落盘文件是
  `plugin_audit.jsonl`（第 5 个独立 AppData 文件，plugins/ 的兄弟文件）；
  state.json / manager.json 字段形状对未声明完整性字段的清单逐位不变
  （`toMap()` 条件输出 + `integrityFieldsRoundtrip` 锁定）；
  `data_compat_spec7_test.dart` 在全量跑内通过（585 绿的一部分）。
- **验收下限全达标**：M6-T1 5≥4（缺 hash 拒绝 / hash 不符拒绝 /
  重放同 hash 通过 / 字段往返四项各有专名用例）、M6-T2 5≥4（append-only、
  损坏行跳过、porcelain 拒绝留痕、不写用户目录逐项对上验收原文）、
  M6-T3 fuzz 12+4≥10 且白名单有专门用例、M6-T4 9≥2、M3-T1 10≥6 且
  性能守卫（关闭开关时 Player 实例数不增 / 开启恰建一个且关即拆）入
  performance_guards_test。
- **拒绝路径全部留痕**：integrityGate 拒绝、porcelain 防线拒绝、busy /
  已安装拒绝都流经 `_reportFinished`（`plugin_manager.dart`）单一出口
  落审计；`porcelainRefusalIsAudited` 专门锁定「porcelain 拒绝也留痕」
  这条验收原文。
- **fuzz 断言打在最深处**：敌意 destination 不止 parse 拒绝，还验证
  整目录摄入 fail-closed（`manager.allManifests()` 空、错误信息
  `cannot read plugin catalog`）、planOperation 得 unknown plugin、
  plugins/ 下无目录落地、**一条 git 命令都没跑**（`git.calls` 空）；
  形似对照组逐段断言 entry 路径不含 `..`/`.`/反斜杠且不出内容根。
- **M3-T1 激活门禁与 Haruna 同条件同顺序**：`activationGateMatchesHarunaConditions`
  逐项对照 HProgressBar.qml 的五条件；`harunaPropertySetCoversMpvPreviewTable`
  把 mpvpreview.cpp 属性表钉成测试常量，生产与断言共表（漂移即红）。
- **预览开销边界**：关闭开关不建实例（guard 用例锁定「关闭时零第二
  解码实例开销」，正是 M7-T3 要求的「预览实例停用零开销」的一半，
  另一半的耗时上限断言仍留 M7-T3）。
- **compat 修复保留编辑器往返**：`parseMpvConf` 仍存原始行，清洗只
  发生在 runtime 应用值上（`runtimeOptionValue` 独立纯函数），
  fullLineCommentsNeverReachHere 等四用例锁定边界（含 `#F8F8F2` 颜色码
  不误伤）。

## 5. 已知限制与未做项

**需要人工操作的**

1. 帧预览画面效果人工验收（linux GUI 构建，SPEC §9 挂账）：hover 出
   帧图、拖动双 seek、气泡宽度随设置、章节标题显示。属性层探针与
   10 逻辑用例只到实例与门禁层，纹理路径 flutter_test 覆盖不了。
2. R12 后两提交（`7b89bb0` / `3514db3`）+ 本轮文档提交的推送（ahead
   2 + 文档）；推送后核对 CI 签名是否 **585 passed / 1 skipped**
   （CI 本窗口不可测，远端尚未载入 R12 全部提交）。
3. 插件完整性对的真源验证（生产级）：sha256 字段目前无配套生成工具，
   插件作者需自行 `find | sort | sha256sum` 按摘要定义算钉值；建议
   后续补一个 `tools/` 侧小工具（见代码侧待办）。

**代码侧待办**

4. 3.0 施工下一阶段 M7 诊断/测试（T1 运行时诊断 / T2 播放链路 live
   集成 / T3 性能回归基线，其中 T3 依赖本轮 M3-T1 与 M4-T4）；M3 残留
   T2 刻度收口 / T3 悬浮面板 / T4-T9 择机清偿（T4b/T5/T5b/T6/T7/T8/T9
   见路线图 §五）。
5. 版本 bump 与发版决策：R12 目前在 CHANGELOG `[Unreleased]`（版本仍
   `2.3.0-alpha+2030000`），是否随 v2.4.0-alpha 收口待定；沿用 draft
   制时忘 publish 是主要失效模式（BUILD_GUIDE §四）。
6. `test/plugin_audit_test.dart:117` 的损坏行夹具内嵌字面 NUL 字节，
   git 把整文件按二进制处理（`757d130 --stat` 显示 `Bin 0 -> 10024`），
   diff 不可文本评审；建议改为转义写法（如 `String.fromCharCodes`），
   属测试可读性整改，不影响行为。

**固有限制**

7. 完整性校验是 opt-in：不声明 size+hash 的清单（含全部 1.x 存量）不
   受装前校验保护，这是在线源兼容性优先的设计取舍（发布说明 §七-3）。
8. 审计是观察性日志：写失败吞掉、损坏行跳过降级，不构成安全边界；
   三段式确认链与 porcelain 防线才是拦截点。
9. hr-seek 跟随主通道，预览无独立精确 seek 键（Haruna
   accuratePreviewThumbnail 语义未搬，发布说明 §七-2）。
10. 容器内无法验证 CI 矩阵的平台侧（Windows/macOS/Android/arm64
    产物），归 release.yaml 与实体机（CROSS-PLATFORM-VERIFICATION-MATRIX.md）。

## 6. 下一步建议

1. **推送**：R12 两提交 + 文档提交一起推（代码与文档混推会触发 CI，
   run 标题只显示头提交），核对签名 585/1；红灯按 HANDOVER 坑 2 归因
   链处理（本地全绿 ≠ CI 绿，dlopen 只报第一层，看 pr.yaml ldd 审计步）。
2. **帧预览 GUI 验收**：linux 构建真跑，设置 → 播放开「进度条帧预览」
   （默认关），hover/拖动核对帧图、宽度滑杆 120-400 生效、音频零输出
   （mute/aid=no）、章节标题气泡；顺带确认关闭开关后无第二 Player 实例
   （守卫用例已在测试层证明，GUI 层再目验一次）。
3. **插件安全联调**：用带 sizeBytes+sha256 的真实清单走一次
   安装（命中）+ 篡改内容（拒绝且目录被清）+ 缺 hash（拒绝于任何 git
   命令前）三态；开 `plugin_audit.jsonl` 核对 plan/operation 两类事件
   与拒绝留痕。
4. **M7 开工**：按路线图 §五 M7 顺序起手（T1 运行时诊断最小面、
   T2 播放链路 live、T3 性能基线补「预览停用零开销」的耗时断言）；
   M3-T2 刻度收口可穿插（章节面板已就位，只差刻度/hover/中键）。
5. **发版收口**：M7 或用户验收完成后走版本 bump + CHANGELOG 折叠 +
   tag + draft publish 流程（BUILD_GUIDE §四）。
