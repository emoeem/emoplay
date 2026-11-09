# 工作报告 · 2026-11-10（转绿补账 R2）

| 项           | 值                                                                                      |
| ------------ | --------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-10（写作时 06:28 CST）                                                          |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                        |
| 版本         | git `b61dff2`（HEAD，R2: remaining debts；origin/main 停在 `2aaa10d`，R2 两个提交待推送） |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md`](../releases/RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md) |

## 1. 本轮范围

OVERNIGHT-LOOP §二轮次结构的 R2 轮（开工检查 → 缺口分析 → 施工 → 文档）。
开工检查实测上一轮推送产出的 CI 首跑（run 42706655830）为红灯，施工按
R1 报告 §6 下一步建议与 OVERNIGHT-LOOP §四积压取项：

1. **CI 红灯定位与修复**（建议 1）：`3379d7a`——VA/VDPAU 运行库缺失，
   依赖安装步前移 + 补装（pr.yaml / release.yaml）。
2. **补账**（建议 4 / 积压 6 / 积压 8 / 积压 4 后半）：`b61dff2`——
   健壮性测试（损坏媒体 / 空结果 / 权限拒绝）、`test_settings_service.cpp`
   两槽位语义、i18n en/zh 骨架、`UPGRADE_ROADMAP_2026-11-10.md` 建立。
3. **文档收网**（本轮）：按 DOC-STANDARD 出发布说明 / 工作报告、更新
   HANDOVER、修正路线图在本轮施工后滞后的数字、CHANGELOG 补 R2 条目、
   docs 索引登记。全部数字本轮实测，未跑的门禁如实标注。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 红灯 | CI 首跑 failure：runner 缺 VA/VDPAU 运行库，media_kit 捆绑 `libmpv.so.2` 加载失败（`libva-drm.so.2: cannot open shared object file`），`equalizer_test.dart:212/:271` 两条真开 libmpv 的用例挂掉 | ✅ 已修（`3379d7a`，待推送验证首绿） | `gh run view 42706655830 --log-failed`：`##[error]311 tests passed, 2 failed, 1 skipped.` + libva-drm 报错原文；`git show 3379d7a`：pr.yaml 装步前移 + 补装 `libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1`，release.yaml 同步 |
| 缺口 | 损坏媒体 / 非媒体目录 / 空库 / 权限拒绝目录等边界输入无测试（积压 6） | ✅ 已补（`b61dff2`） | `test/robustness_test.dart`（463 行）单独跑 **11 用例全绿**（`flutter test test/robustness_test.dart` → `+11: All tests passed!`） |
| 缺口 | 1.x `test_settings_service.cpp` 两槽位无 Dart 对应（R1 报告 §3.1 ❌ 行） | ✅ 已补（`b61dff2`） | `test/settings_service_semantics_test.dart`（167 行）单独跑 **2 用例全绿**；槽位映射与未伪造项见文件头注释（`restoreDefaultsKeepsMediaAndHistory` 因 2.0 无对应 UI 控件而明确不伪造） |
| 缺口 | i18n 骨架未建（积压 8，SPEC §1 预留） | ✅ 已补（`b61dff2`） | `l10n.yaml`（zh 模板 / 非 synthetic 生成目录）+ `lib/l10n/app_zh.arb`（28 行）+ `app_en.arb` + `lib/l10n/generated/` 4 文件（170+28+28 行）+ `pubspec.yaml` `generate: true` + `lib/app_widget.dart` delegates 切换 |
| 缺口 | 路线图未建立（积压 4 后半） | ✅ 已补（`b61dff2`） | `docs/UPGRADE_ROADMAP_2026-11-10.md`（139 行）+ HANDOVER §路线图回填指向 |
| 文档滞后 | 路线图快照写于 `3379d7a` 时点：基线数字停在 28 文件 / 313 用例、"本轮零 Dart 改动"、R2 行缺补账内容——与同提交 `b61dff2` 的实际内容矛盾 | ✅ 本轮修正 | `git show b61dff2 --stat`（test/ 新增 2 文件、lib/ 与 pubspec 有改动）对照路线图 §一/§三 旧文；本轮实测 30 文件 / 326 用例后改写 |
| 记录澄清 | HANDOVER 旧坑第 2 条「纯 markdown 推送不触发 CI」与 run 42706655830 由文档提交 `2aaa10d` 触发的事实表面冲突 | ✅ 本轮澄清并改写 | `git diff --name-only 6247f2e 2aaa10d` 含 **11 个非 markdown 文件**——R1 三个代码提交与文档提交同一次 push，`paths-ignore` 按 push 整体 diff 评估；run 标题只显示头提交。坑条目改为「混合 push 会触发 CI，别按 run 标题判断触发者」 |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 2.2s)**——0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test`（全量） | **All tests passed!**：30 文件（`ls test/*_test.dart \| wc -l`）/ **+326 ~1**——326 通过 + 1 平台条件跳过（`test/mpv_profile_scanner_test.dart` 的 Windows-only 探测） |
| 新用例单独跑 | `flutter test test/robustness_test.dart` | **+11: All tests passed!** |
| 新用例单独跑 | `flutter test test/settings_service_semantics_test.dart` | **+2: All tests passed!** |
| Linux 构建 | `flutter build linux --debug` | **✓ Built build/linux/x64/debug/bundle/emoplay**（R2 改了 Dart/pubspec/l10n，故本轮重测；路线图"R1 实测未重跑"的说法已随之修正） |
| CI | `gh run list -R emoeem/emoplay --limit 10` | **仅 1 条：run 42706655830 completed failure**（2m17s，2026-11-09T21:52:50Z UTC = 05:52 CST）；`gh run view 42706655830 --log-failed` 提取到 `311 tests passed, 2 failed, 1 skipped` 与 libva-drm 报错 |
| 推送状态 | `git log origin/main..HEAD --oneline` / `git log HEAD..origin/main --oneline` | **2 个 R2 提交未推送**（`3379d7a` 06:05 / `b61dff2` 06:23 CST）；HEAD 无落后 |
| 树干净度 | 门禁后 `git status --porcelain` | **空**——测试与构建无生成物漂移（l10n 生成类与提交物一致） |
| 用例增量 | 326 − 313 = 13 = 11（robustness）+ 2（settings 语义） | 计数自洽 ✓ |

### 3.1 CI 失败归因链（避免误诊）

1. `gh run list` 唯一 run 的头提交是 `2aaa10d`（纯文档提交）——若只看标题
   会误判为"文档触发了 CI"或"paths-ignore 失效"。
2. 实际触发源：同一次 push 还含 R1 三个代码提交（`git diff --name-only
   6247f2e 2aaa10d` 亦可见 11 个非 md 文件）；GitHub 对 push 事件的
   paths 过滤按**整段 push 的 diff** 评估。
3. 失败点不在这 11 个文件本身，而在 runner 环境：唯一依赖原生
   `libmpv.so.2` 的两条均衡器用例（`test/equalizer_test.dart:212/:271`，
   文件头注释自证"drive a real (idle) libmpv core"）加载失败。
4. 其余 311 条纯 Dart 用例全部通过——与本地 313+1 全绿一致
   （本地 313 通过 = CI 311 通过 + 2 失败）。

## 4. 确认无问题的部分

- **数据兼容契约**：`test/data_compat_spec7_test.dart` 在 326 全绿内——
  1.x 三份 JSON 直接可读的发布承诺继续被锁定。
- **R2 对既有测试零改动**：`git show b61dff2 --stat` 中 test/ 仅为两个
  **新增**文件，全量套件绿即既有用例无回归。
- **l10n 生成链**：`generate: true` 下 `flutter test` / `flutter build`
  自动跑 gen-l10n，门禁后 `git status --porcelain` 为空——生成物与提交
  的 `lib/l10n/generated/` 一致，CI 无需额外生成步骤。
- **发布矩阵无密钥泄漏**：`3379d7a` 仅改动依赖安装步，未引入任何
  dart-define / secrets；workflow 仍为 `permissions: contents: read`
  （`git show 3379d7a` 全文核对）。
- **依赖锁定未变**：`b61dff2` 对 `pubspec.yaml` 仅加 `generate: true`
  及注释，media-kit Predidit fork 锁 `83b7ca6`、Kazumi `7265274` 不变
  （docs/UPSTREAM.md 记录仍有效）。
- **健壮性测试的覆盖边界诚实**：`robustness_test.dart` 头注释逐项列出
  "已在别处锁定的不重复测"（无 ffmpeg 降级、存储 JSON 损坏、空目录列表），
  避免双份维护。

## 5. 已知限制与未做项

**需要人工操作的**
- R2 两个提交（`3379d7a` / `b61dff2`）与本轮文档的推送（本轮职责边界止于
  文档，推送由收尾流程执行）；推送后需人工确认 **CI 首绿**。
- GUI 实机验收与 Windows / macOS / Android 实体机验证；Android 签名密钥
  接入——均与 R1 报告相同，本轮无变化。

**代码侧待办**
- 页面字符串逐页迁移到 `AppLocalizations`（本轮只立了骨架与 zh 模板键）。
- `test_settings_service.cpp` 的 `restoreDefaultsKeepsMediaAndHistory`
  槽位仍无对应（2.0 无恢复默认 UI，测试侧明确不伪造，待控件落地后补）；
  `test_mpv_engine.cpp` 的 `apply()` 半边仍需 live libmpv，无自动化覆盖。
- 打包（linux deb / AppImage 进 release.yaml）与性能轮（大库扫描 isolate
  分片、缩略图并发上限、首帧时间）——OVERNIGHT-LOOP §四积压 5 / 7 未动。
- build_runner 门禁本轮未单独跑（生成文件均为提交物且树净），见 §3 表注。

**固有限制**
- Windows 专属扫描探测在非 Windows 平台永远 skipped（QSKIP 契约对应物）。
- CI 对纯 markdown 推送不触发，但与代码混在同一次 push 时会触发且 run
  标题只显示头提交——文档轮次的 CI 信号判断要按 §3.1 归因链走。
- 私有仓库 Actions 分钟数有限，全平台矩阵只能随 tag 跑。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送并盯 CI 首绿**：`git push origin main` 后
   `gh run list -R emoeem/emoplay`。若仍红灯：下一步最可能失败点是
   Linux 构建步（GTK/ayatana 包名差异），而非测试步——VA/VDPAU 已装齐。
2. **打包**：linux deb（参照 Kazumi CI 的 deb 产物链）或 AppImage 进
   release.yaml（OVERNIGHT-LOOP §四-5）。
3. **i18n 第一页迁移**：从设置页挑一类把字符串换成 `AppLocalizations`
   取用，验证生成链在真实页面可用后再批量铺开。
4. **性能轮**：大库扫描 isolate 分片与取消延迟、缩略图并发上限、首帧时间
   （OVERNIGHT-LOOP §四-7）。
5. **GUI 实机验收**：SPEC §9 冒烟约定的"显示待人工验收"部分。
