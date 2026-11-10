# 工作报告 · 2026-11-10（首绿发布 R4）

| 项           | 值                                                                                       |
| ------------ | ----------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-10（写作时 08:56 CST）                                                            |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                          |
| 版本         | git `2c6bf06`（HEAD，R4: remaining debts；origin/main 停在 `bd36f70`，R4 后两个提交待推送）；发布 tag `v2.0.0-alpha` → `bd36f70` |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_FIRST_GREEN_RELEASE.md`](../releases/RELEASE_2026-11-10_FIRST_GREEN_RELEASE.md) |

## 1. 本轮范围

OVERNIGHT-LOOP §二轮次结构的 R4 轮（开工检查 → 缺口分析 → 施工 → 文档）。
开工检查实测：R3 三提交推送后 main CI 一次转绿（**首绿**，run 42718530280，
`332 tests passed, 1 skipped`，与 R3 预期签名一致）；同日 `v2.0.0-alpha` tag
发布演练第一跑（run 42720144705）红灯三个平台 job。施工按 R3 报告 §6 下一步
建议与演练红灯取项：

1. **发布管线红灯修复**（建议 1/2 的延续）：`b9b3d2c`——macOS 打包找
   `Kazumi.app`（pbxproj 品牌化残留）、Windows 装环境缺 `yq`、arm64 构建缺
   ALSA 头文件，一次修三处；`bd36f70`——Windows 编译炸出被剥离业务的死
   include（app_links）。第三次演练 run 42724607274 八 job 全绿，
   **v2.0.0-alpha GitHub Release 公开发布（9 资产）**。
2. **engine apply 半边测试**（积压 3 续 / R2-R3 对账残余）：`2598bc8`——
   1.x `test_mpv_engine.cpp` apply 半边 5 条 live 用例逐用例平移进
   `test/mpv_player_properties_test.dart`（CI 修全依赖后 runner 有真 libmpv，
   此前无法做）。
3. **剩余欠账**（R3 建议 3 的执行切片 + README）：`2c6bf06`——设置页音频类
   i18n 第二页迁移（`test/audio_settings_l10n_test.dart` 4 用例）+ 中英
   README 补「发布产物」章节。
4. **文档收网**（本轮）：按 DOC-STANDARD 出发布说明 / 工作报告、HANDOVER
   刷新、路线图滞后数字与轮次表修正、CHANGELOG 补 R4 与发布条目、docs 索引
   登记。全部数字本轮实测，未跑或未能复现的如实标注。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 红灯 | CI 首绿未确认（R1–R3 遗留）：R3 修复推送前 runner 缺依赖连环红灯 | ✅ 已达成 | `gh run list`：run 42718530280 success（4m12s，2026-11-09T23:12:23Z = 07:12 CST）；job 129506221947 日志 `🎉 332 tests passed, 1 skipped.` + `No issues found! (ran in 19.7s)` + `✓ Built build/linux/x64/debug/bundle/emoplay`——与 R3 预期签名一字不差 |
| 红灯 | 发布演练第一跑三平台红灯：macOS `ditto: Cannot get the real path for source '.../EmoPlay.app'`（实际构建出 `Kazumi.app`）；Windows `yq not found`（flutter-action 的 version-file 解析）；arm64 `Could NOT find ALSA` | ✅ 已修（`b9b3d2c`，drill#2 验证三 job 转绿） | `gh run view 42720144705 --log-failed` 报错原文三段；`git show b9b3d2c`：pbxproj product 引用 / bundle id / TEST_HOST 改 EmoPlay、Windows job 钉 `flutter-version: '3.47.9'`（含注释）、arm64 action apt 补 `libasound2-dev` + `libayatana-appindicator3-dev` |
| 红灯 | 发布演练第二跑仅剩 Windows 编译：`main.cpp(4,10): error C1083: Cannot open include file: 'app_links/app_links_plugin_c_api.h'` | ✅ 已修（`bd36f70`，drill#3 验证全绿） | `gh run view 42722139024 --log-failed` 报错原文；`git show bd36f70`：删 include 与 `SendAppLink()`（app_links 已随 STRIP-LIST 剥离，pubspec/lock/generated_plugins.cmake 无此插件）；第二实例唤起保留，URL 转发记为待做 |
| 发布 | 真实发布流程未演练（R3 报告 §5 待办）：tag → release.yaml 全平台矩阵 → GitHub Release 产物链 | ✅ 已达成 | run 42724607274 success（15m15s，8 job 全绿含 GitHub Release 19s）；`gh api repos/emoeem/emoplay/releases`：v2.0.0-alpha，draft=false / prerelease=false / Latest，9 资产与字节数实测（amd64 deb 17,148,320 B … Windows zip 30,725,989 B）；tag 指向 `bd36f70`（`git rev-parse v2.0.0-alpha^{commit}`） |
| 缺口 | 1.x `test_mpv_engine.cpp` apply() 半边无自动化覆盖（R1 报告 §3.1 / R2-R3 报告 §5 挂账） | ✅ 已补（`2598bc8`） | `test/mpv_player_properties_test.dart` 新增 5 条 live 用例（applyPresetLandsOnLiveCore / propertyRoundTripDispatch / observedPropertySignalsAvailableAndUnavailable / unavailableIdleCoreReadsClearedValues / commandErrorSurfacesThroughLogStream），文件头注释带 1.x→2.0 逐用例对账表与不移植项理由；全量套件绿 |
| 缺口 | i18n 只有页签壳一页（积压 8 续） | ✅ 第二页已迁（`2c6bf06`） | `lib/pages/settings/audio_settings.dart` 全面取用 `AppLocalizations`；`test/audio_settings_l10n_test.dart` 4 用例（zh+en）锁 arb→gen→真实页面挂载链，含均衡器提示实时翻转与频段行滚动可见断言 |
| 缺口 | README 无发布产物说明（积压 9 部分） | ✅ 已补（`2c6bf06`） | 中英 README 各增「发布产物 / Release artifacts」节（平台×产物表、deb 直装建议、未签名提示）；`git show 2c6bf06 -- README.md` 实测 +51 行 |
| 记录澄清 | 首绿 run 标题为 `docs(round 3): 红灯清零`（纯文档提交名） | ⚠️ 第三次证实坑 2，无需修 | run 42718530280 由 R3 代码+文档混合 push 触发，标题只显示头提交 `c7acc9b`——归因链再添一例（HANDOVER 坑 2） |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 代码生成幂等 | `dart run build_runner build --delete-conflicting-outputs` | **wrote 0 outputs**，跑后 `git status --porcelain` 为空——生成物与提交一致 |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 3.0s)**——0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test`（全量） | **+341 ~1: All tests passed!**：33 文件（`ls test/*_test.dart \| wc -l`）/ 341 通过 + 1 平台条件跳过（`Skip: Windows-only probe (1.x QSKIP contract)`） |
| 用例增量对账 | 341 − 332 = 9 = 5（mpv live）+ 4（audio l10n）；33 − 32 = 1 新文件 | 计数自洽 ✓（`grep` 两文件实测 8 与 4 条声明：mpv 3 条既有纯逻辑 + 5 新 live；audio 3 testWidgets + 1 test） |
| Linux 构建（debug） | `flutter build linux --debug` | **✓ Built build/linux/x64/debug/bundle/emoplay** |
| ldd 审计（CI 同款） | `ldd build/native_assets/linux/libmpv.so.2 \| grep 'not found' \| wc -l` | **0**——容器内依赖闭包完整（与 CI 三连绿互证） |
| CI（main） | `gh run list -R emoeem/emoplay --limit 12` | 近三跑全绿：42718530280（4m12s，**首绿**）/ 42722128694（3m49s）/ 42724596082（3m29s）；此前两层红灯 42706655830 / 42712702494 已由 R2/R3 修复 |
| CI（release 演练） | `gh run view 42720144705 / 42722139024 / 42724607274` | 42720144705 ✗（13m6s，macOS/Windows/arm64 三红灯）→ 42722139024 ✗（18m7s，仅 Windows）→ **42724607274 ✓（15m15s，8 job 全绿）** |
| GitHub Release | `gh api repos/emoeem/emoplay/releases --jq ...` | v2.0.0-alpha：published 2026-11-10T00:13:04Z（08:13 CST）、draft=false、**prerelease=false**、Latest 标记、9 资产（字节数逐个实测，见发布说明一-1）、写作时 0 下载 |
| 推送状态 | `git log origin/main..HEAD --oneline` | **2 个 R4 提交未推送**（`2598bc8` 08:23 / `2c6bf06` 08:49 CST）；origin/main = `bd36f70`；R4 前两个修复提交已随 tag 与 main 推送 |
| 树干净度 | `git status --porcelain` | **空** |

### 3.1 发布演练归因链（三次跑的因果，避免误读 run 列表）

1. drill#1（42720144705，tag 指向 R3 文档提交 `c7acc9b`）：Linux amd64 与
   Android 在第一跑就绿——说明矩阵主体可用，红灯是平台特异问题。
2. drill#2（42722139024，tag 重指 `b9b3d2c`）：三红灯全消，唯一新红灯是
   Windows 编译层——Linux 下永远编不到的 runner 死代码，被首次真实编译暴露。
3. drill#3（42724607274，tag 重指 `bd36f70`）：全绿并发布。两次迭代各修
   一层，与 R2/R3 的「依赖洋葱」同类：**发布矩阵的红灯也只能在真实演练里
   逐层暴露**——这正是 R3 报告坚持「矩阵是最后一环、必须演练」的验证。
4. run 标题继续误导：三次 release run 的标题分别是文档提交名与修复提交名，
   tag 移动后标题跟随新头提交——按 ref 列（`v2.0.0-alpha`）判演练，别按标题。

## 4. 确认无问题的部分

- **数据兼容契约**：`test/data_compat_spec7_test.dart` 在 341 全绿内——
  1.x 三份 JSON 直接可读的发布承诺继续被锁定，且发布产物内含同版本测试。
- **R4 对既有测试零改动**：`git diff bd36f70..2c6bf06 --stat -- test/` =
  2 文件（一新增一扩充）；`2598bc8` 的 4 行删除经 `git show ... | grep '^-[^-]'`
  核对**全部是文件头旧注释**（「apply 半边不在本文件测」的过时声明被对账
  表替代），既有 3 条纯逻辑用例未动。
- **tag ↔ 产物对应关系**：`git rev-parse v2.0.0-alpha^{commit}` = `bd36f70`；
  drill#2 的 checkout 日志显示 tag 移动轨迹（`b9b3d2c` → `bd36f70`），
  发布说明一-2 已写明产物不含 R4 未推送提交。
- **workflow 权限与结构未变**：`b9b3d2c` 只动 arm64 action 的 apt 清单、
  Windows 的版本钉法与 macOS 工程文件；`bd36f70` 只动 runner main.cpp；
  `git show` 全文核对无 secrets / 无 dart-define / 无新第三方 action。
- **音频页语义未漂移**：`2c6bf06` 对 `audio_settings.dart` 的改动被同提交
  的 4 条 l10n 用例 + 套件内均衡器用例（`equalizer_test.dart`）双重覆盖，
  全量套件绿。
- **i18n 生成链与提交物一致**：`2c6bf06` 改动 arb 后同步提交 3 个生成文件，
  `build_runner` 与 `flutter test` / `flutter build` 跑完树仍净（wrote 0
  outputs + porcelain 空）——CI 无需额外生成步骤（R3 结论的再验证）。
- **打包脚本参数化未受影响**：drill#3 的 arm64/amd64 job 同脚本产出 deb +
  tar.gz 并上传成功，R3 的「脚本参数化正确」结论在全平台维度成立。

## 5. 已知限制与未做项

**需要人工操作的**
- R4 两个提交（`2598bc8` / `2c6bf06`）与本轮文档的推送（本轮职责边界止于
  文档，推送由收尾流程执行）；推送后需确认 CI 签名 **341 passed / 1 skipped**。
- 9 个发布产物的实体机验证：Windows / macOS / Android 均未在实体机运行过；
  Linux deb 的最小系统直装亦未对发布产物本体复验（容器内验证的是同脚本
  产物，R3）。APK 签名密钥接入仍需仓库配置。
- GUI 实机验收（SPEC §9 冒烟中「显示待人工验收」部分）。

**代码侧待办**
- **release.yaml 的 prerelease 语义**：alpha 以 prerelease=false 占据 Latest；
  打 beta/rc 前应决策是否给 `softprops/action-gh-release` 步加 `prerelease`
  参数（发布说明 §四已记录影响面）。
- **AppImage**：deb 之外的第二种 Linux 交付仍未做（OVERNIGHT-LOOP §四-5）。
- **i18n 其余页面**：已迁页签壳 + 音频设置两处，其余逐页替换待续。
- **测试对账残余收窄为一条**：`test_settings_service.cpp` 的
  `restoreDefaultsKeepsMediaAndHistory` 槽位（2.0 无恢复默认 UI，测试侧
  明确不伪造）；apply() 半边已由本轮 `2598bc8` 消账。
- **Windows URL 转发**：`emoplay://` 第二实例唤起已工作，链接内容转发到
  已运行实例是待做功能（`bd36f70` 提交信息记录）。
- 打包脚本注释「115」数字口径待施工方确认（R3 遗留，本轮未跟进）。

**固有限制**
- Windows 专属扫描探测在非 Windows 平台永远 skipped（QSKIP 契约对应物）。
- CI 对纯 markdown 推送不触发；混合 push 触发时 run 标题只显示头提交
  （R2/R3/R4 三轮连续验证，本轮 §3.1 再添 release 侧一例）。
- 私有仓库 Actions 分钟数有限：本轮三次发布演练（13m6s + 18m7s + 15m15s）
  与三次 main CI 是演练的必要成本，收敛后应避免反复移动 tag。
- 发布产物的 arm64 Linux 构建依赖自建 action 的源码装 Flutter 路径，其
  缓存键（`flutter-arm64-3.47.9-Linux-`）首次为冷缓存——后续跑依赖缓存
  命中，但缓存逐出后仍会走完整源码构建（耗时波动属预期）。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送 R4 并盯 CI 签名**：`git push origin main` 后
   `gh run list -R emoeem/emoplay`，预期 **341 passed / 1 skipped**（本地
   实测口径）；红灯则按 pr.yaml ldd 审计步的全量清单处理。
2. **发布产物实体机冒烟**：优先 Linux——在最小化 Debian/Ubuntu 容器或实体机
   `sudo apt install ./EmoPlay_linux_*_amd64.deb` 验证「装完即起」；再各下载
   一次 Windows zip / macOS zip / APK 确认可解压可安装（签名缺失会有系统
   警告，属预期）。
3. **prerelease 语义决策**：给 release.yaml 的 gh-release 步加 `prerelease`
  参数方案（如按 tag 后缀 `-alpha/-beta/-rc` 自动判定），避免下一个预发布
  tag 再次占据 Latest。
4. **i18n 第三页**：从设置页再挑一类（视频与画质或常规）完成迁移并配
   l10n 链路用例（生成链已在两个页面验证可用）。
5. **AppImage 与 Android 签名**：AppImage 可参照 deb 的打包脚本模式新增
   产物类型；Android 签名待仓库密钥配置后接入 release.yaml。
6. **性能实测轮**：实机跑大库扫描吞吐与首帧时间（SPEC §9），给
   `performance_guards_test.dart` 的定性守卫补定量基线。
