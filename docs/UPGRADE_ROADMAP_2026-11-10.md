# EmoPlay 2.0 迁移路线图（M0–M8 现状快照与后续待办的权威清单）

| 项       | 值                                                                                     |
| -------- | -------------------------------------------------------------------------------------- |
| 状态     | 生效中（2026-11-10 R2 轮建立；R2/R3 文档轮先后修正滞后数字与轮次表）                     |
| 日期     | 2026-11-10（最后实质性更新）                                                             |
| 适用版本 | git `c943414`（2.0.0-alpha+2000000，未发布；`pubspec.yaml:4`）                            |
| 相关     | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[HANDOVER.md](HANDOVER.md)、[R1 工作报告](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md)、[R2 工作报告](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)、[R3 工作报告](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)、[CI run 42712702494](https://github.com/emoeem/emoplay/actions/runs/42712702494) |

## 一、当前基线（实测）

结论：迁移主流程 M0–M8 与 R1/R2/R3 三轮收尾全部完成；本地门禁全绿（含
release 构建与 deb 打包），唯一红灯在 CI——两层依赖缺口（VA/VDPAU →
libpulse）均已定位修复，**首绿待 R3 提交推送后确认**。

| 门禁       | 结果                                                              | 来源                                                                 |
| ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- |
| 版本       | 2.0.0-alpha+2000000，git HEAD `c943414`（领先 origin/main 3 提交） | `git log -1`、`git log origin/main..HEAD`（2026-11-10 R3 文档轮实测） |
| 静态检查   | **0 告警**（`No issues found! (ran in 2.3s)`）                    | `flutter analyze`（2026-11-10 R3 文档轮实测）                        |
| 自动化测试 | **32 文件 / 332 通过 + 1 平台条件跳过，全绿**（`+332 ~1: All tests passed!`） | `flutter test`（2026-11-10 R3 文档轮实测；R1 28/313+1 → R2 30/326+1 → R3 +2 文件 / +6 用例） |
| Linux 构建 | debug 与 release 构建通过；deb 打包通过（deb 17,045,202 字节 / tar.gz 20,743,844 字节，`package-linux.sh` 实跑） | `flutter build linux --debug` / `--release` / `bash .github/scripts/package-linux.sh amd64 x64 v2.0.0-alpha`（2026-11-10 R3 文档轮实测） |
| CI         | **run 42712702494 failure**（2m53s，analyze ✓、Run tests ✗ 于 324 通过 / 2 失败 / 1 跳过） | `gh run list` / `gh run view 42712702494`（R3 本轮实测）             |

CI 红灯两层洋葱（归因链全文见
[R3 工作报告 §3.1](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)）：
失败用例始终是 `test/equalizer_test.dart` 的 `equalizerAppliesToEngine`（:212）
与 `equalizerDisableClearsChain`（:271）——全仓唯二真开 libmpv 核心的用例，
报错随修复逐层下钻：第一层 `libva-drm.so.2`（run 42706655830，`3379d7a`
补 VA/VDPAU）、第二层 `libpulse.so.0`（run 42712702494，`7debc83` 按
`readelf -d` 实测直系 NEEDED 一次装全 14 包，并在 pr.yaml 加
`ldd | grep 'not found'` 审计步，缺口以后一次列全）。两个 run 的标题都是
文档提交（混合 push 触发、标题只显示头提交，HANDOVER 坑 2）。
**首绿待 R3 提交推送后确认，预期签名 332 passed / 1 skipped**。

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

## 三、收尾轮次（R1 / R2 / R3）

结论：R1–R3 全部提交均为 `git log --oneline` 实测；R1 的缺口分析结论
见 [R1 工作报告 §2](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md)。

| 轮次 | 提交 | 内容 | 对应缺口 |
| ---- | ---- | ---- | -------- |
| R1 | `916c2d6` | 修 CI 触发分支 `master`→`main`（此前 CI 零 run） | 积压 1 遗留缺陷 |
| R1 | `d1866dd` | 平移 `UpdateChecker`（lib/services/update_checker.dart + 测试 + 装配）；PORT-MAP MediaBrowser 行改判 N/A | 积压 3 |
| R1 | `a7488d9` | 画质三控制器测试面合入 `quality_engine_test.dart`；修 MobX 镜像不随设置重读（`interpolation_controller.dart:172`、`quality_controller.dart:375`） | 积压 3 |
| R1 文档 | `2aaa10d` | 发布说明 / 工作报告 / HANDOVER / docs 索引 / CHANGELOG R1 条目 | 积压 4 前半 |
| R2 | `3379d7a` | CI 红灯定位与 libva/VDPAU 运行库修复（pr.yaml 装步前移 + release.yaml 同步）——后证实只是依赖洋葱第一层 | R1 下一步建议 1 |
| R2 | `b61dff2` | 健壮性测试（`test/robustness_test.dart` 11 用例：损坏媒体 / 空结果 / 权限拒绝）+ `test_settings_service.cpp` 两槽位语义（`test/settings_service_semantics_test.dart` 2 用例）+ i18n 骨架（l10n.yaml / en+zh arb / 生成类 / app_widget 装配）+ 本路线图建立与 HANDOVER 回填 | 积压 6 / 8 / 4 后半 |
| R2 文档 | `4d3eae5` | R2 发布说明 / 工作报告 / HANDOVER 刷新 / 本文件滞后数字修正 / CHANGELOG R2 条目 | 收尾流程（OVERNIGHT-LOOP §二-4） |
| R3 | `7debc83` | CI 红灯第二层修复（libpulse）：readelf 实测直系 NEEDED 后 pr.yaml 一次补装 14 包（release.yaml 同步），步序改 构建→ldd 审计→测试，缺口以后一次列全 | R2 下一步建议 1 续 |
| R3 | `7052260` | deb `Depends` 2 项 → 17 项（GTK 显式钉入），apt 递归闭包覆盖审计（依据入脚本注释）；容器内实测打包通过 | R2 下一步建议 2 / 积压 5 |
| R3 | `c943414` | 页签壳 i18n 第一页迁移（`menuTabLabels()` 双壳同源 + 退出 toast，`test/menu_l10n_test.dart` 3 用例）+ 媒体库响应性守卫（`test/performance_guards_test.dart` 3 用例：取消延迟 / 进度节流 / 缩略图串行） | 积压 7 / 8 可测切片 |
| R3 文档 | 本轮 `docs:` 提交（哈希待回填） | R3 发布说明 / 工作报告 / HANDOVER 刷新 / 本文件滞后数字修正 / CHANGELOG R3 条目 / docs 索引登记 | 收尾流程（OVERNIGHT-LOOP §二-4） |

## 四、未做项（☐）

结论：按下述优先级推进；R1 报告「下一步建议」5 条中——建议 1 已两层修复
（`3379d7a` + `7debc83`，首绿待推送确认）、建议 2 已消化（R3 `7052260`：
deb 依赖审计 + 打包实测）、建议 3 第一页已迁（R3 `c943414`）、
建议 4 已消化（R2 `b61dff2`）、建议 5 仍待实机，其余全部在列。

### 4.1 需要人工/实机的

- ☐ **Windows / macOS / Android 产物实体机验证**；Android 签名密钥接入
  （R1 报告 §5；CHANGELOG「已知限制」：APK 发布为未签名产物）。
- ☐ **GUI 手感人工验收**：容器内仅验证了进程与构建产物（SPEC §9 冒烟约定：
  显示不可达时以进程存活 + 日志判定，并在报告中标注「显示待人工验收」）。
- ☐ **iOS 构建进发布矩阵**：workflow 留注释，待签名方案（CHANGELOG「已知限制」）。
- ☐ **推送 R3 提交（`7debc83` / `7052260` / `c943414`）与 R3 文档并确认
  CI 首绿**（R1–R3 报告「需要人工操作的」）。
- ☐ **性能实测**：大库扫描吞吐墙钟数字与首帧时间需实机（SPEC §9），
  自动化侧能锁的响应性守卫已由 R3 `c943414` 交付。

### 4.2 代码侧待办（按优先级）

- ☐ **CI 首绿**（R1 下一步建议 1 的未消化尾巴）：R3 提交推送后盯
  `gh run list -R emoeem/emoplay`，预期签名 **332 passed / 1 skipped**；
  若仍红灯，pr.yaml 的 ldd 审计步会一次性给出完整缺失清单（R3 起
  「逐层剥洋葱」的排查方式作废），按清单补 pr.yaml 即可。
- ☐ **tag 发布演练**：打 `v2.0.0-alpha` 触发 release.yaml 全平台矩阵，
  验收 deb/tar.gz/APK 产物链（打包脚本容器内已实测，矩阵是最后一环）。
- ☐ **AppImage**：deb 之外的第二种 Linux 交付（OVERNIGHT-LOOP §四-5 后半）。
- ☐ **i18n 其余页面**：页签壳已迁（R3 `c943414`，生成链在真实页面验证
  可用），其余页面字符串逐页替换为 `AppLocalizations` 取用
  （R2 下一步建议 3 续）。
- ☐ **测试对账残余**：`test_settings_service.cpp` 的
  `restoreDefaultsKeepsMediaAndHistory` 槽位无对应（2.0 无恢复默认 UI，
  测试侧明确不伪造）；`test_mpv_engine.cpp` 的 `apply()` 半边需 live libmpv，
  无自动化覆盖（其余槽位已由 R2 `b61dff2` 补齐；R1 报告 §3.1 表 + §5）。

已消化待办（留痕，勿重复施工）：**健壮性轮**（损坏媒体 / 空库 / 拒绝权限
目录 11 用例 + settings 语义 2 用例，R2 `b61dff2`）；**CI 依赖两层洋葱**
（VA/VDPAU `3379d7a` → libpulse 全闭包 + ldd 审计步 `7debc83`）；**deb
依赖审计**（Depends 17 项 + apt 递归闭包覆盖验证，R3 `7052260`）；**媒体
库响应性守卫**（取消延迟 / 进度节流 / 缩略图串行 3 用例；isolate 分片多开
经评估不采，理由在测试文件头注释，R3 `c943414`）；**无 ffmpeg 降级 /
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
3. **自动化测试**：`flutter test` 全绿——当前底数 32 文件 / 332 通过 + 1
   条件跳过（R3 文档轮实测），只增不减；Windows-only 用例按 QSKIP 契约
   在非 Windows 平台 skipped 不计失败。
4. **数据兼容**：`test/data_compat_spec7_test.dart` 必须保持绿——1.x 的
   `history.json` / `library.json` / `settings.json` 直接可读是发布承诺
   （SPEC §7）。
5. **CI**：含代码改动的推送必须以 `gh run list` 绿灯收尾（run
   42706655830 / 42712702494 两层红灯的教训：本地全绿 ≠ CI 绿，runner
   环境差异要修 workflow 而不是跳过用例；dlopen 只报第一个缺失依赖，
   依赖缺口看 pr.yaml ldd 审计步的全量清单）。
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
