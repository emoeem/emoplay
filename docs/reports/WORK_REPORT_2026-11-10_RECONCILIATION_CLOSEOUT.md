# 工作报告 · 2026-11-10（对账收网 R1）

| 项           | 值                                                                                     |
| ------------ | -------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-10（写作时 05:50 CST）                                                          |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                        |
| 版本         | git `a7488d9`（HEAD，R1: test parity；origin/main 停在 `6247f2e` M8，R1 三个提交待推送） |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md`](../releases/RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md) |

## 1. 本轮范围

M1–M8 主流程结束后的第一轮收尾（OVERNIGHT-LOOP §二轮次结构），按 §四起始积压清单
取前三项做缺口分析并施工：

1. **CI 收敛与触发**（积压 1 的遗留缺陷）：发现并修复 pr.yaml 触发分支笔误。
2. **测试对账**（积压 3）：按 PORT-MAP §4 把旧仓库 26 个 C++ 测试文件与 Dart 测试
   逐一对账，补平移 `UpdateChecker`（含测试）与 3 个画质控制器测试面。
3. **文档收网**：按 DOC-STANDARD 建立发布记录 / 工作报告 / HANDOVER / docs 索引，
   CHANGELOG 补 R1 条目。全部数字本轮实测，未跑的门禁如实标注。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 缺陷 | CI 自建仓起零 run：pr.yaml `on.push.branches` 写 `master`，实际分支 `main`，每次推送被静默跳过 | ✅ 已修（`916c2d6`，1 行） | `git show 916c2d6 -- .github/workflows/pr.yaml`：`-      - master` → `+      - main`；`gh run list --json` 返回 `[]` |
| 缺口 | 1.x `src/update/UpdateChecker.cpp` 未平移（PORT-MAP §1 A 类表内承诺项），设置页留 M8 占位注释 | ✅ 已补（`d1866dd`） | `git show 6247f2e:lib/services/update_checker.dart` → `exists on disk, but not in '6247f2e'`；新增 335 行实现 + 381 行测试 + `update_settings.dart` / `main.dart` 装配 |
| 缺口 | 三个画质控制器（quality / interpolation / icc）无 Dart 测试面（对应 1.x `test_quality_controller.cpp` / `test_interpolation_controller.cpp` / `test_icc_controller.cpp`） | ✅ 已补（`a7488d9`，合入 `quality_engine_test.dart` 294 行） | 该文件 import `quality_controller.dart` / `interpolation_controller.dart` / `icc_controller.dart`（test/quality_engine_test.dart:15-18） |
| 缺陷 | MobX 镜像不随持久化设置重读，外部写入者的改动在下次 apply 被忽略（1.x Q_PROPERTY 实时重读语义丢失） | ✅ 已修（`a7488d9`） | `lib/quality/interpolation_controller.dart:172`、`lib/quality/quality_controller.dart:375` 每次 apply 入口 `runInAction` 重同步，注释注明 1.x 行号依据 |
| 对账 | PORT-MAP §2 `MediaBrowser` 行与现状不符（迁移中曾按"落地"对待） | ✅ 已对账（`d1866dd` 改 PORT-MAP 1 行） | `docs/PORT-MAP.md:37`：**N/A（不落地）**，职责由 file_picker + LibraryStore 覆盖，判定日期 2026-11-10 |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 2.2s)**——0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test` | **All tests passed!**：28 文件 / **313 通过 + 1 skipped**（`test/mpv_profile_scanner_test.dart:217` 的 Windows-only 探测，非 Windows 跳过） |
| Linux 构建 | `flutter build linux --debug` | **✓ Built build/linux/x64/debug/bundle/emoplay** |
| CI | `gh run list -R emoeem/emoplay --limit 6` 及 `--json` 形式 | **空**（0 run；修复待推送，首跑未发生） |
| 推送状态 | `git fetch origin && git log origin/main..HEAD --oneline` | 3 个 R1 提交未推送（`916c2d6`/`d1866dd`/`a7488d9`）；HEAD 无落后（`git log HEAD..origin/main` 为空） |
| 用例数对比 | `git ls-tree --name-only 6247f2e test/ \| grep -c '_test.dart'` | M8 时 26 个测试文件 → 现存 28（`ls test/*_test.dart \| wc -l`）；用例级增量未在 M8 留实测记录，无法对比 |

### 3.1 测试对账表（本轮核心交付）

旧仓库 `/home/emo/code/mpv-emo/tests/`（只读枚举，26 文件）→ 新仓库 `test/`（28 文件）：

| 1.x C++ 测试 | Dart 测试 | 状态 |
| --- | --- | --- |
| `test_app_settings.cpp` | `emoplay_settings_test.dart` | ✅ 直译 |
| `test_compat_controller.cpp` | `compat_controller_test.dart` | ✅ 直译 |
| `test_compat_scanner.cpp` | `mpv_profile_scanner_test.dart` | ✅ 直译（Windows 用例按 QSKIP 契约条件跳过） |
| `test_config_parser.cpp` | `mpv_config_parser_test.dart` | ✅ 直译 |
| `test_history_store.cpp` | `history_store_test.dart` | ✅ 直译 |
| `test_icc_controller.cpp` | `quality_engine_test.dart`（ICC 段） | ✅ R1 补齐 |
| `test_import_rules.cpp` | `mpv_import_rules_test.dart` | ✅ 直译 |
| `test_interpolation_controller.cpp` | `quality_engine_test.dart`（插值段） | ✅ R1 补齐 |
| `test_interpolation_decision.cpp` | `interpolation_decision_test.dart` | ✅ 直译 |
| `test_library_store.cpp` | `library_store_test.dart` | ✅ 直译（R1 +22 行） |
| `test_lrc_parser.cpp` | `lrc_parser_test.dart` | ✅ 直译 |
| `test_media_browser.cpp` | — | ☑️ **N/A**：MediaBrowser 不落地（PORT-MAP §2:37 判定，职责由 file_picker + LibraryStore 覆盖） |
| `test_media_classifier.cpp` | `media_classifier_test.dart` | ✅ 直译 |
| `test_mpv_engine.cpp` | `mpv_player_properties_test.dart` | ⚠️ 半覆盖：纯逻辑半边（默认选项表 + scripts append）有测试（文件头注释明示）；`apply()` 半边需 live libmpv，由真实播放器启动路径承担 |
| `test_mpv_key_name.cpp` | `mpv_key_name_test.dart` | ✅ 直译 |
| `test_music_controller.cpp`（纯函数） | `equalizer_test.dart` | ✅ 直译（R1 +113 行） |
| `test_music_page.cpp` | `music_lyrics_page_test.dart` | ✅ 直译（R1 +94 行） |
| `test_playback_controller.cpp` | `pending_resume_seek_test.dart`（resume 语义） | ✅ 对应（resume 挂起/一次性消费是 1.x 该测试的核心断言） |
| `test_plugin_manager.cpp` | `plugin_manager_test.dart` | ✅ 直译 |
| `test_plugin_manifest.cpp` | `plugin_manifest_test.dart` | ✅ 直译 |
| `test_quality_controller.cpp` | `quality_engine_test.dart` | ✅ R1 补齐 |
| `test_quality_profile_engine.cpp` | `quality_profile_engine_test.dart` | ✅ 直译 |
| `test_remote_manifest_source.cpp` | `remote_manifest_source_test.dart` | ✅ 直译 |
| `test_settings_service.cpp` | — | ❌ 未一对一落地（见 §5 代码侧待办） |
| `test_thumbnail_service.cpp` | `thumbnail_service_test.dart` | ✅ 直译 |
| `test_update_checker.cpp` | `update_checker_test.dart` | ✅ R1 补齐（381 行） |

无 C++ 对应、随 Kazumi 骨架或 SPEC 新增的 Dart 测试（6 个）：`async_rate_limiter` /
`async_session` / `async_single_flight` / `dialog_helper` / `dialog_task`（Kazumi
通用件）、`data_compat_spec7_test`（SPEC §7 数据契约，M8 新增）。

计数自洽：24 个 C++ 文件有 Dart 落点（26 − N/A − 未落地），其中 3 个合入同一
`quality_engine_test.dart`，占 22 个 Dart 文件；加 6 个 Dart 独有 = 28 ✓。

## 4. 确认无问题的部分

- **CI workflow 配置本身**（修复后复读）：push/PR 单 job Linux gate，
  `paths-ignore: '**.md'`（纯文档推送不烧分钟数）、`concurrency` 取消在途、
  `permissions: contents: read`、无任何 dart-define 密钥；全平台打包仅 `v*` tag
  触发（`.github/workflows/pr.yaml`、`release.yaml` 头注释与正文核对）。
- **数据兼容契约**：`test/data_compat_spec7_test.dart` 在 313 全绿内，含
  `lastPlayed` 为 null 的外来写入者情形——1.x 三份 JSON 直接可读的承诺仍被锁定。
- **R1 两处控制器改动**：diff 均为 apply 入口重读 + 注释，无逻辑分叉；含 M8
  既有用例在内的全量套件绿（313 通过）即回归证据——本轮未做逐用例的
  "改前/改后"对照跑，这一点如实说明。
- **写路径重定向**：`mpv_player_properties_test.dart` 的
  `presetCarriesEngineDefaultsAndRedirects` 在全绿内——watch_later/screenshots/
  shader_cache 等不写用户 mpv 目录的不变量有测试锁定。
- **依赖锁定**：media-kit Predidit fork 锁 commit `83b7ca6`、Kazumi 导入
  `7265274`（docs/UPSTREAM.md 记录），本轮无依赖变更（`git log --stat` 复核）。

## 5. 已知限制与未做项

**需要人工操作的**
- R1 三个提交与本轮文档的推送（本轮职责边界止于文档，推送由收尾流程执行）；
  推送后需人工确认 CI 首绿。
- GUI 实机验收：容器内仅验证了进程与构建产物，显示效果待人工（SPEC §9 冒烟约定）。
- Windows / macOS / Android 产物实体机验证；Android 签名密钥接入。

**代码侧待办**
- `test_settings_service.cpp` 无一对一 Dart 测试（1.x SettingsService 是运行时
  应用层，对应语义散落在 Dart 设置页/控制器，未逐一断言）。
- `test_mpv_engine.cpp` 的 `apply()` 半边需 live libmpv，无自动化覆盖。
- `UPGRADE_ROADMAP_2026-11-10.md` 尚未建立（OVERNIGHT-LOOP §四积压 4 的一半）。
- 积压 5–8：linux deb/AppImage 打包；损坏媒体/无 ffmpeg/空库等健壮性用例；
  大库扫描 isolate 分片与缩略图并发上限；en arb 骨架。
- 用例级数字的持续记录：M1–M8 未留下逐轮测试数，本轮起发布说明按规范记录。

**固有限制**
- Windows 专属扫描探测在非 Windows 平台永远 skipped（QSKIP 契约的对应物）。
- CI 对纯 markdown 推送不触发（paths-ignore），文档轮次无 CI 信号，属设计取舍。
- 私有仓库 Actions 分钟数有限，全平台矩阵只能随 tag 跑。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送并盯 CI 首绿**：`git push origin main` 后 `gh run list -R emoeem/emoplay`；
   红灯优先修（`ubuntu-latest` 首跑可能暴露 GTK/ayatana 依赖的包名差异，
   workflow 内 `sudo apt-get install` 步骤是最可能失败点）。
2. **建立 `UPGRADE_ROADMAP_2026-11-10.md`**（DOC-STANDARD 4.4 格式，M0–M8 ☐/✅
   + 提交哈希回填），替换 HANDOVER 中的临时路线指向。
3. **打包**：linux deb（参照 Kazumi CI 的 deb 产物链）或 AppImage，进 release.yaml。
4. **健壮性轮**：损坏媒体文件 / 无 ffmpeg 降级 / 空库 / 超长路径用例，
   顺带补 `test_settings_service` 的语义断言。
5. **i18n**：en arb 骨架（SPEC §1 预留）。
