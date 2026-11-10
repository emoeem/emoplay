# EmoPlay 2.0 迁移路线图（M0–M8 现状快照与后续待办的权威清单）

| 项       | 值                                                                                     |
| -------- | -------------------------------------------------------------------------------------- |
| 状态     | 生效中（2026-11-10 R2 轮建立；R2/R3/R4 文档轮先后修正滞后数字与轮次表）                     |
| 日期     | 2026-11-10（最后实质性更新）                                                             |
| 适用版本 | git `2c6bf06`（2.0.0-alpha+2000000，`pubspec.yaml:4`）；tag `v2.0.0-alpha` 已公开发布，产物对应 `bd36f70`                            |
| 相关     | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[HANDOVER.md](HANDOVER.md)、[R1 工作报告](reports/WORK_REPORT_2026-11-10_RECONCILIATION_CLOSEOUT.md)、[R2 工作报告](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)、[R3 工作报告](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)、[R4 工作报告](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md)、[CI run 42718530280（首绿）](https://github.com/emoeem/emoplay/actions/runs/42718530280) |

## 一、当前基线（实测）

结论：迁移主流程 M0–M8 与 R1–R4 四轮收尾全部完成；**CI 首绿已达成**（run
42718530280，签名与 R3 预期一字不差），**v2.0.0-alpha 已公开发布**（发布
演练三次跑打穿，GitHub Release 9 资产）；本地门禁全绿且 build_runner 幂等、
ldd 审计 0 缺失；唯一悬空项是 R4 后两个提交待推送（推送后预期 CI 签名
341 passed / 1 skipped）。

| 门禁       | 结果                                                              | 来源                                                                 |
| ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- |
| 版本       | 2.0.0-alpha+2000000，git HEAD `2c6bf06`（领先 origin/main 2 提交）；tag `v2.0.0-alpha` → `bd36f70` 已发布 | `git log -1`、`git log origin/main..HEAD`、`git rev-parse v2.0.0-alpha^{commit}`（2026-11-10 R4 文档轮实测） |
| 静态检查   | **0 告警**（`No issues found! (ran in 3.0s)`）                    | `flutter analyze`（2026-11-10 R4 文档轮实测）                        |
| 自动化测试 | **33 文件 / 341 通过 + 1 平台条件跳过，全绿**（`+341 ~1: All tests passed!`） | `flutter test`（2026-11-10 R4 文档轮实测；R1 28/313+1 → R2 30/326+1 → R3 32/332+1 → R4 +1 文件 / +9 用例） |
| Linux 构建 | debug 构建通过；ldd 审计 0 缺失；发布产物由 CI 矩阵产出（amd64 deb 17,148,320 字节等 9 资产） | `flutter build linux --debug` / `ldd build/native_assets/linux/libmpv.so.2 \| grep -c 'not found'`（R4 文档轮实测）；`gh api .../releases`（R4 实测） |
| CI         | main 三连绿：**42718530280 首绿**（4m12s，`🎉 332 tests passed, 1 skipped.`）→ 42722128694 → 42724596082；release 演练 42720144705 ✗ → 42722139024 ✗ → **42724607274 ✓（GitHub Release 已发布）** | `gh run list` / `gh run view`（R4 本轮实测）                         |

CI 红灯历史（归因链全文见
[R3 工作报告 §3.1](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md) 与
[R4 工作报告 §3.1](reports/WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE.md)）：
main 侧两层依赖洋葱（`libva-drm.so.2` → `libpulse.so.0`，`3379d7a` /
`7debc83` 修复）已由首绿 run 42718530280 收口；发布矩阵侧四盏红灯
（macOS `Kazumi.app` 残留 / Windows 缺 `yq` / arm64 缺 ALSA / Windows 死
include app_links）已由 `b9b3d2c` / `bd36f70` 修复并被 drill#3 全绿验证。
混合 push 触发、run 标题只显示头提交的坑在 R2/R3/R4 三轮连续出现
（HANDOVER 坑 2）。

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

## 三、收尾轮次（R1-R4）

结论：R1-R4 全部提交均为 `git log --oneline` 实测；R1 的缺口分析结论
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
| R3 文档 | `c7acc9b` | R3 发布说明 / 工作报告 / HANDOVER 刷新 / 本文件滞后数字修正 / CHANGELOG R3 条目 / docs 索引登记 | 收尾流程（OVERNIGHT-LOOP §二-4） |
| R4 | `b9b3d2c` | 发布演练第一跑三红灯修复：macOS pbxproj 的 Kazumi.app 残留改 EmoPlay（product 引用/bundle id/TEST_HOST）、Windows 装环境钉 `flutter-version: '3.47.9'`（runner 缺 yq，flutter-version-file 不可用）、arm64 action apt 补 `libasound2-dev` + `libayatana-appindicator3-dev`（源码构建缺 ALSA 头） | 发布演练 42720144705 三红灯 |
| R4 | `bd36f70` | Windows runner main.cpp 删除已剥离业务 app_links 的死 include（`error C1083`，STRIP-LIST.md:37）；`emoplay://` 第二实例唤起保留，URL 转发记为待做 | 发布演练 42722139024 Windows 编译红灯 |
| R4 | `2598bc8` | 1.x `test_mpv_engine.cpp` apply 半边 5 条 live 用例逐用例平移进 `test/mpv_player_properties_test.dart`（CI 有真 libmpv 后可做；不移植项与理由在文件头注释） | R3 报告 §5 测试对账残余 |
| R4 | `2c6bf06` | 设置页音频类 i18n 第二页（`audioEqualizerPresetLabels` 单一来源，`test/audio_settings_l10n_test.dart` 4 用例 zh+en）+ 中英 README「发布产物」节 | R3 下一步建议 3 / 积压 8、9 部分 |
| R4 发布 | tag `v2.0.0-alpha` 三次演练 | 42720144705 ✗（三红灯）→ 42722139024 ✗（仅 Windows）→ **42724607274 ✓**：GitHub Release 公开（9 资产，prerelease=false 占 Latest，语义待决策） | R3 下一步建议 2 |
| R4 文档 | `9f51c2f` | R4 发布说明 / 工作报告 / HANDOVER 刷新 / CHANGELOG R4 与发布条目 / docs 索引登记（本文件 §三-§五 修正残片随收尾提交，哈希待回填） | 收尾流程（OVERNIGHT-LOOP §二-4） |

## 四、未做项（☐）

结论：按下述优先级推进；R1 报告「下一步建议」5 条全部消化或转实机（建议
1 首绿达成 run 42718530280、建议 2 已消化 R3 `7052260`、建议 3 已迁两页
R3 `c943414` + R4 `2c6bf06`、建议 4 已消化 R2 `b61dff2`、建议 5 转性能
实测项）；R3 报告 §6 建议 1（推送盯首绿）与建议 2（tag 演练）已由 R4
消化，其余在列。

### 4.1 需要人工/实机的

- ☐ **发布产物实体机验证**：9 资产（Linux amd64/arm64 deb 与 tar.gz、
  3 APK、Windows/macOS zip）均未逐平台安装/解压验证；优先在最小化
  Debian/Ubuntu 环境直装 amd64 deb 验证「装完即起」（R4 报告 §6 建议 2）。
  Android 签名密钥接入（R1 报告 §5；CHANGELOG「已知限制」：APK 发布为
  未签名产物）。
- ☐ **GUI 手感人工验收**：容器内仅验证了进程与构建产物（SPEC §9 冒烟约定：
  显示不可达时以进程存活 + 日志判定，并在报告中标注「显示待人工验收」）。
- ☐ **iOS 构建进发布矩阵**：workflow 留注释，待签名方案（CHANGELOG「已知限制」）。
- ☐ **推送 R4 提交（`2598bc8` / `2c6bf06`）与本轮文档并确认 CI 签名
  341 passed / 1 skipped**（R4 报告「需要人工操作的」；本地 33 文件 341+1
  实测口径）。
- ☐ **性能实测**：大库扫描吞吐墙钟数字与首帧时间需实机（SPEC §9），
  自动化侧能锁的响应性守卫已由 R3 `c943414` 交付。

### 4.2 代码侧待办（按优先级）

- ☐ **release.yaml 的 prerelease 语义**：`softprops/action-gh-release` 步
  未设 `prerelease` 参数，v2.0.0-alpha 以正式版语义占据 Latest（当前对
  UpdateChecker 行为正确，语义待固化）；打 beta/rc 前决策按 tag 后缀
  （-alpha/-beta/-rc）自动判定（R4 报告 §5 / §6 建议 3）。
- ☐ **AppImage**：deb 之外的第二种 Linux 交付（OVERNIGHT-LOOP §四-5 后半）。
- ☐ **i18n 其余页面**：页签壳（R3 `c943414`）与音频设置（R4 `2c6bf06`）
  已迁，其余页面字符串逐页替换为 `AppLocalizations` 取用
  （R3 下一步建议 4 续）。
- ☐ **Windows `emoplay://` URL 内容转发**：第二实例唤起已工作（`bd36f70`
  保留 `ActivateExistingWindow()`），链接内容转发到已运行实例待做。
- ☐ **测试对账残余**：仅剩 `test_settings_service.cpp` 的
  `restoreDefaultsKeepsMediaAndHistory` 槽位无对应（2.0 无恢复默认 UI，
  测试侧明确不伪造）；`test_mpv_engine.cpp` 的 apply() 半边已由 R4
  `2598bc8` 消账。

已消化待办（留痕，勿重复施工）：**健壮性轮**（损坏媒体 / 空库 / 拒绝权限
目录 11 用例 + settings 语义 2 用例，R2 `b61dff2`）；**CI 依赖两层洋葱**
（VA/VDPAU `3379d7a` → libpulse 全闭包 + ldd 审计步 `7debc83`）；**deb
依赖审计**（Depends 17 项 + apt 递归闭包覆盖验证，R3 `7052260`）；**媒体
库响应性守卫**（取消延迟 / 进度节流 / 缩略图串行 3 用例；isolate 分片多开
经评估不采，理由在测试文件头注释，R3 `c943414`）；**CI 首绿**（run
42718530280，签名 332 passed / 1 skipped 与预期一致，R4 推送后达成）；
**tag 发布演练**（`v2.0.0-alpha` 三次跑打穿，GitHub Release 9 资产公开，
R4）；**发布矩阵四红灯**（macOS Kazumi.app 残留 / Windows 缺 yq / arm64
缺 ALSA，`b9b3d2c`；Windows 死 include app_links，`bd36f70`）；**engine
apply 半边**（5 条 live 用例逐用例平移，`2598bc8`）；**无 ffmpeg 降级 /
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
3. **自动化测试**：`flutter test` 全绿，当前底数 33 文件 / 341 通过 + 1
   条件跳过（R4 文档轮实测），只增不减；Windows-only 用例按 QSKIP 契约
   在非 Windows 平台 skipped 不计失败。
4. **数据兼容**：`test/data_compat_spec7_test.dart` 必须保持绿——1.x 的
   `history.json` / `library.json` / `settings.json` 直接可读是发布承诺
   （SPEC §7）。
5. **CI**：含代码改动的推送必须以 `gh run list` 绿灯收尾（run
   42706655830 / 42712702494 两层红灯的教训：本地全绿 ≠ CI 绿，runner
   环境差异要修 workflow 而不是跳过用例；dlopen 只报第一个缺失依赖，
   依赖缺口看 pr.yaml ldd 审计步的全量清单）。
6. **发布验收**：`v*` tag 触发 release.yaml 全平台矩阵产物可用（已达成：
   run 42724607274 全绿，v2.0.0-alpha GitHub Release 公开 9 资产；实体机
   验收与 AppImage 见 §4.1/§4.2）。
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
