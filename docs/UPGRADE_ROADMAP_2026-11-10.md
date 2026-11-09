# EmoPlay 2.0 迁移路线图（M0–M8 现状快照与后续待办的权威清单）

| 项       | 值                                                                                     |
| -------- | -------------------------------------------------------------------------------------- |
| 状态     | 生效中（2026-11-10 R2 轮建立；R2 文档轮修正滞后数字与轮次表）                             |
| 日期     | 2026-11-10（最后实质性更新）                                                             |
| 适用版本 | git `b61dff2`（2.0.0-alpha+2000000，未发布；`pubspec.yaml:4`）                            |
| 相关     | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[HANDOVER.md](HANDOVER.md)、[R1 工作报告](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md)、[R2 工作报告](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)、[CI run 42706655830](https://github.com/emoeem/emoplay/actions/runs/42706655830) |

## 一、当前基线（实测）

结论：迁移主流程 M0–M8 与对账收网 R1 已全部完成；本地门禁全绿，唯一红灯在
CI（首跑因缺 VA/VDPAU 运行库挂掉，修复已提交待推送验证）。

| 门禁       | 结果                                                              | 来源                                                                 |
| ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- |
| 版本       | 2.0.0-alpha+2000000，git HEAD `b61dff2`（领先 origin/main 2 提交） | `git log -1`、`git log origin/main..HEAD`（2026-11-10 R2 文档轮实测） |
| 静态检查   | **0 告警**（`No issues found! (ran in 2.2s)`）                    | `flutter analyze`（2026-11-10 R2 文档轮实测）                        |
| 自动化测试 | **30 文件 / 326 通过 + 1 平台条件跳过，全绿**（`+326 ~1: All tests passed!`） | `flutter test`（2026-11-10 R2 文档轮实测；R1 报告为 28/313+1，R2 补账 +2 文件 / +13 用例） |
| Linux 构建 | debug 构建通过（`✓ Built build/linux/x64/debug/bundle/emoplay`）  | `flutter build linux --debug`（2026-11-10 R2 文档轮重测——`b61dff2` 改动了 Dart/pubspec/l10n，R1 的"零 Dart 改动免重跑"已失效） |
| CI         | **run 42706655830 failure**（2m17s，analyze ✓、Run tests ✗ 于 311 通过 / 2 失败 / 1 跳过） | `gh run list` / `gh run view 42706655830`（R2 本轮实测）             |

CI 红灯细节（`gh run view 42706655830 --log-failed`）：失败用例为
`test/equalizer_test.dart` 的 `equalizerAppliesToEngine`（:212）与
`equalizerDisableClearsChain`（:271），报错
`Failed to load dynamic library '.../libmpv.so.2': libva-drm.so.2: cannot open
shared object file`——CI runner 缺 media_kit 捆绑 libmpv 的 VA/VDPAU 运行时
依赖，两个真开 libmpv 核心的均衡器用例因此挂掉，与其余 311 条纯 Dart 用例无关
（本地 313 通过 = CI 311 通过 + 2 失败，用例数自洽）。该 run 由 R1 代码与文档
混合 push 触发，标题只显示头提交 `2aaa10d`（docs）——归因链见
[R2 工作报告 §3.1](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)。
修复 `3379d7a`（R2: ci libva deps）在 pr.yaml 把依赖安装步挪到 `flutter test`
之前并补装 `libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1`，
release.yaml 同步补同一步；**首绿待本修复推送后确认**。

## 二、阶段划分：M0–M8（✅ 全部完成）

结论：提交哈希与时间均取自 `git log --format='%h %ci %s'` 实测（2026-11-10
R2 回填）；内容一句话取自 [CHANGELOG.md](../CHANGELOG.md) 2.0.0-alpha 小节。

| 阶段 | 状态 | 提交 | 时间（CST）       | 内容一句话 |
| ---- | ---- | ---- | ----------------- | ---------- |
| M0 环境准备（脚本内 S0） | ✅ | **无仓库提交**（先于首提交完成） | 2026-11-10 | 工具链三档解析、Flutter ≥3.47.9 装入 /opt、写 `/opt/emoplay-env.sh`、克隆 Kazumi@`7265274` 与 PiliPlus（宿主机零污染）；依据迁移工作流脚本 S0 阶段（`.zcode/workflow-drafts/EmoPlay-2.0-全量迁移.dwf.ts`「准备环境与克隆上游」）与 [UPSTREAM.md](UPSTREAM.md) |
| M1 骨架 | ✅ | `160da3c` | 11-10 01:48 | Kazumi 工作树导入（不带上游历史），剥番剧业务，五页签导航，品牌化，规格文档入 docs/ |
| M2 播放器 | ✅ | `49d58ce` | 11-10 02:16 | media-kit（Predidit fork 锁 `83b7ca6`）接入：音轨/字幕/倍速/手势/截图/PiP/DLNA/外部播放器接管 |
| M3 本地媒体 | ✅ | `a74cc2e` | 11-10 02:31 | 文件/目录打开、拖拽导入、媒体分类器、扫描 isolate（skipHidden、maxDepth、进度与取消） |
| M4 媒体库与历史 | ✅ | `3ef5081` | 11-10 03:05 | `library.json`/`history.json` 落盘（SPEC §7 逐字段一致）、ffmpeg 两段式缩略图、首页最近播放/继续观看 |
| M5 mpv 兼容 | ✅ | `cb30627` | 11-10 03:30 | conf 解析、首启导入向导、三张规则表、写路径全部重定向（绝不写用户 mpv 目录）、诊断页 |
| M6 画质引擎 | ✅ | `1456144` | 11-10 03:57 | Anime4K 链序表照抄 1.x、SSimSuperRes、HDR tone-mapping、插值六预设 + 掉帧自动降档、ICC 恢复快照 |
| M7 插件/设置/音乐 | ✅ | `38559d7` | 11-10 04:29 | PluginManager 三段式 + 6 内置插件、设置中心 11 类、10 段均衡器 + .lrc 歌词 |
| M8 交付 | ✅ | `6247f2e` | 11-10 04:43 | 双语 README、NOTICE.md、SPEC §7 数据兼容测试、CI 改造（单 job Linux gate + tag 触发全平台矩阵）、MIT→GPL-3.0 |

## 三、收尾轮次（R1 / R2）

结论：R1 三提交与 R2 修复均为 `git log --oneline` 实测；R1 的缺口分析结论
见 [R1 工作报告 §2](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md)。

| 轮次 | 提交 | 内容 | 对应缺口 |
| ---- | ---- | ---- | -------- |
| R1 | `916c2d6` | 修 CI 触发分支 `master`→`main`（此前 CI 零 run） | 积压 1 遗留缺陷 |
| R1 | `d1866dd` | 平移 `UpdateChecker`（lib/services/update_checker.dart + 测试 + 装配）；PORT-MAP MediaBrowser 行改判 N/A | 积压 3 |
| R1 | `a7488d9` | 画质三控制器测试面合入 `quality_engine_test.dart`；修 MobX 镜像不随设置重读（`interpolation_controller.dart:172`、`quality_controller.dart:375`） | 积压 3 |
| R1 文档 | `2aaa10d` | 发布说明 / 工作报告 / HANDOVER / docs 索引 / CHANGELOG R1 条目 | 积压 4 前半 |
| R2 | `3379d7a` | CI 红灯定位与 libva/VDPAU 运行库修复（pr.yaml 装步前移 + release.yaml 同步），待推送验证 | R1 下一步建议 1 |
| R2 | `b61dff2` | 健壮性测试（`test/robustness_test.dart` 11 用例：损坏媒体 / 空结果 / 权限拒绝）+ `test_settings_service.cpp` 两槽位语义（`test/settings_service_semantics_test.dart` 2 用例）+ i18n 骨架（l10n.yaml / en+zh arb / 生成类 / app_widget 装配）+ 本路线图建立与 HANDOVER 回填 | 积压 6 / 8 / 4 后半 |
| R2 文档 | 本轮 `docs:` 提交（哈希待回填） | R2 发布说明 / 工作报告 / HANDOVER 刷新 / 本文件滞后数字修正 / CHANGELOG R2 条目 | 收尾流程（OVERNIGHT-LOOP §二-4） |

## 四、未做项（☐）

结论：按下述优先级推进；R1 报告「下一步建议」5 条中——建议 2 已消化、
建议 4 已消化（R2 `b61dff2`：健壮性 + settings 语义）、建议 5 骨架已立
（页面迁移另列 ☐）、建议 1 部分消化（修复 `3379d7a` 已提交待推送）、
建议 3 未动，其余全部在列。

### 4.1 需要人工/实机的

- ☐ **Windows / macOS / Android 产物实体机验证**；Android 签名密钥接入
  （R1 报告 §5；CHANGELOG「已知限制」：APK 发布为未签名产物）。
- ☐ **GUI 手感人工验收**：容器内仅验证了进程与构建产物（SPEC §9 冒烟约定：
  显示不可达时以进程存活 + 日志判定，并在报告中标注「显示待人工验收」）。
- ☐ **iOS 构建进发布矩阵**：workflow 留注释，待签名方案（CHANGELOG「已知限制」）。
- ☐ **推送 R2 提交（`3379d7a` / `b61dff2`）与 R2 文档并确认 CI 首绿**
  （R1/R2 报告「需要人工操作的」）。

### 4.2 代码侧待办（按优先级）

- ☐ **CI 首绿**（R1 下一步建议 1 的未消化尾巴）：R2 提交推送后盯
  `gh run list -R emoeem/emoplay`；`ubuntu-latest` 若仍红灯，下一个最可能失败点
  是 Linux 构建步的 GTK/ayatana 包名差异（R1 报告 §6-1 的预判；测试步的
  VA/VDPAU 缺失已由 `3379d7a` 处理）。
- ☐ **打包**：linux deb（参照 Kazumi CI 的 deb 产物链）或 AppImage，进
  release.yaml（R1 下一步建议 3；OVERNIGHT-LOOP §四-5）。
- ☐ **性能**：大库扫描 isolate 分片与取消延迟、缩略图并发上限、首帧时间
  （OVERNIGHT-LOOP §四-7）。
- ☐ **i18n 页面迁移**：en/zh arb 骨架与生成链已立（R2 `b61dff2`，SPEC §1
  预留），页面字符串逐页替换为 `AppLocalizations` 取用（R2 下一步建议 3）。
- ☐ **测试对账残余**：`test_settings_service.cpp` 的
  `restoreDefaultsKeepsMediaAndHistory` 槽位无对应（2.0 无恢复默认 UI，
  测试侧明确不伪造）；`test_mpv_engine.cpp` 的 `apply()` 半边需 live libmpv，
  无自动化覆盖（其余槽位已由 R2 `b61dff2` 补齐；R1 报告 §3.1 表 + §5）。

已消化待办（留痕，勿重复施工）：**健壮性轮**（损坏媒体 / 空库 / 拒绝权限
目录 11 用例 + settings 语义 2 用例，R2 `b61dff2`）；**无 ffmpeg 降级 /
存储 JSON 损坏 / 空目录列表**此前已由 `thumbnail_service_test.dart` /
`library_store_test.dart` / `history_store_test.dart` 等锁定
（`robustness_test.dart` 头注释有覆盖图）。

## 五、验收标准

结论：任何一轮施工在宣布完成前，须同时满足以下各条；做不到的在文档里如实
写「未测/未达」，不允许填绕过值。

1. **门禁序列**（SPEC §9）：`source /opt/emoplay-env.sh` →
   `dart run build_runner build --delete-conflicting-outputs` →
   `flutter analyze` → `flutter test` → `flutter build linux --debug`；
   发布 tag 走 `--release` 与 release.yaml 矩阵。
2. **静态检查**：0 error 维持（R1 起实测 0 告警，`No issues found!`）；
   出现新告警当场清零，不积压。
3. **自动化测试**：`flutter test` 全绿——当前底数 30 文件 / 326 通过 + 1
   条件跳过（R2 文档轮实测），只增不减；Windows-only 用例按 QSKIP 契约
   在非 Windows 平台 skipped 不计失败。
4. **数据兼容**：`test/data_compat_spec7_test.dart` 必须保持绿——1.x 的
   `history.json` / `library.json` / `settings.json` 直接可读是发布承诺
   （SPEC §7）。
5. **CI**：含代码改动的推送必须以 `gh run list` 绿灯收尾（run 42706655830
   的教训：本地全绿 ≠ CI 绿，runner 环境差异要修 workflow 而不是跳过用例）。
6. **发布验收**：`v*` tag 触发 release.yaml 全平台矩阵产物可用；Linux
   deb/AppImage 接入后按同标准验收（当前未做，见 §4.2）。
7. **冒烟**：按 SPEC §9——后台启动产物 20 秒读 stderr 无未捕获异常；
   桌面显示不可达时以进程存活判定并标注「显示待人工验收」。

## 六、贯穿约定（门禁与红线）

结论：以下约定对每一轮生效，与轮次主题无关；冲突时按第 2 条的优先级裁决。

1. **环境红线**：宿主机零污染（SPEC §3，不调用宿主包管理器、PUB_CACHE 走
   /opt）；`/home/emo/code/mpv-emo` 只读；一切构建前
   `source /opt/emoplay-env.sh`。
2. **决策优先级**：SPEC §4 九条不变量 > 其他一切产品决策；规格未覆盖处按
   SPEC §10 兜底（UI 细节取最接近 Kazumi 现状；播放器交互优先 PiliPlus
   摘取件；环境阻塞升级提问，不硬编）。
3. **平移铁律**：1.x 源文件的考证注释（mpv v0.37 源码级）必须随行平移；
   `history.json` / `library.json` / `settings.json` 字段名一个不改
   （PORT-MAP 头部）。
4. **文档纪律**（DOC-STANDARD）：文档提交与代码提交分开（`docs:` 前缀），
   文档只动 markdown 与 CHANGELOG.md；三条底线——数字必须实测写来源、
   结论要讲为什么、坏消息（未做项/已知限制）单列成节。
5. **备份承诺**（OVERNIGHT-LOOP §五）：每轮收尾必须
   `git push origin main`，哪怕只改文档；纯 markdown 推送不触发 CI
   （pr.yaml `paths-ignore: '**.md'`）属设计，不是故障。
6. **数字留痕**：自 R1 起，发布说明按规范记录测试文件数与用例数
   （M1–M8 未留逐轮数字，是既成缺口，不再重犯——R1 报告 §5）。
