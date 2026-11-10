# 工作报告 · 2026-11-10（卫生与交付形态 R6）

| 项           | 值                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------ |
| 报告日期     | 2026-11-11（写作时 02:32 CST；窗口为 2026-11-10 夜间，文件名沿用窗口日期，同 R1-R5 口径） |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                            |
| 版本         | git `b0e1a06`（HEAD）；origin/main 停在 `63d9f59`，`d446bb8` 起六个提交未推送              |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_HYGIENE_DELIVERY.md`](../releases/RELEASE_2026-11-10_HYGIENE_DELIVERY.md) |

## 1. 本轮范围

OVERNIGHT-LOOP §二轮次结构的 R6 轮文档收网（第 6 轮，主题「卫生与交付形态」）。
本轮为文档轮，不开工代码；施工面是 R6 施工轮的三个提交：

1. `988122f` 仓库卫生与依赖收敛：web/ 模板残留、any×3、
   `screen_brightness_ohos`、两条死排除（对应审计 P2 卫生批次）。
2. `e1a2df0` AppImage 打包：`.github/scripts/package-appimage.sh`（121 行）
   + release.yaml（+16）+ `.gitignore`（+1）。
3. `b0e1a06` Kazumi 样式层对齐（许可证 tile / 空态按钮 / 插件页徽章）+
   守护测试 `test/kazumi_alignment_ui_test.dart`（171 行 / 3 用例）+
   README 对账（37/13），并随提交自更新了 HANDOVER 与 CHANGELOG。

文档收网（本轮）：本报告 + 发布说明 + HANDOVER 增量更新（适用版本、待推送
清单、第一步清单指向）+ docs/README.md 索引登记 + CHANGELOG 结构修复与
R6 小节补全。CHANGELOG 结构问题的来龙去脉：`b0e1a06` 编辑 CHANGELOG 时把
新小节插在 R5 的 `### Fixed` 之前、并顶替掉了 R5 的
`## [Unreleased] - 2026-11-10（面板观感轮）` 节头，导致 R5 的
Fixed/Added/Changed/验证 四个小节被卷进 R6 头下（R5 的「34 文件 342 用例」
验证数字随之过时地挂在 R6 头下）；本轮恢复「一轮一节」结构，并在 R6 小节
补上本轮实测的 Removed 小节与验证块。路线图 §四的勾选态（AppImage 等）
不在本轮范围，按 HANDOVER 既有口径以下次收网为准。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 工程 | 审计 P2：web/ 模板目录被跟踪 + `analysis_options.yaml` 死排除 | ✅ 已清（`988122f`） | `ls web/` = No such file or directory；`analysis_options.yaml` exclude 实读无 `web/**`、无 `lib/bbcode/generated/**`；`git show --numstat 988122f` |
| 工程 | 审计 P2：pubspec 三处 `any` 约束 | ✅ 已收敛（`988122f`） | `git show 988122f -- pubspec.yaml`：synchronized `^3.6.1+1` / material_color_utilities `^0.13.0` / path `^1.9.1` |
| 工程 | 审计 P2：`screen_brightness_ohos` 零引用 | ✅ 已移除（`988122f`）；同项后半 connectivity_plus 评估未决 | grep pubspec 实测无 ohos；`pubspec.yaml:18` connectivity_plus 仍在，`lib/services/network/metered_network_service.dart:3` 在用 |
| 交付 | AppImage 未做（审计「持续真未消化」清单 + 路线图 §4.2-108） | ✅ 本地落地（`e1a2df0`）；arm64 打包与 Release 资产待 CI | 脚本 121 行 + release.yaml +16 + `.gitignore:62`；产物 35,584,504 B / `file` static-pie / `--appimage-help` exit 0（本轮实测） |
| 观感 | 空态按钮 / 插件页徽章 / 许可证 tile 与 Kazumi 不一致（旧徽章深棕两主题不可读） | ✅ 已对齐（`b0e1a06`） | `about_page.dart:42`、`home_page.dart:251`、`player_page.dart:396-414`、`library_page.dart:394-411`、`plugins_page.dart:457`；`test/kazumi_alignment_ui_test.dart` 3 用例全绿 |
| 文档 | README 与实际漂移（AppImage 行 / libasound2-dev / 更新检查 / 截图占位） | ✅ 已对账（`b0e1a06`） | `git show --numstat b0e1a06`：README.md 37 插入 / 13 删除 |
| 文档 | CHANGELOG 一轮一节结构被 R6 提交打破（R5 小节卷进 R6 头，342 数字过时） | ✅ 本轮修复 | CHANGELOG.md 头部现为 R6（含 Removed / 验证）与 面板观感轮 两节，`### Fixed`（快捷键/浮层/楷体）回到面板观感轮名下 |
| 文档 | `test/kazumi_alignment_ui_test.dart:16-20` 头注释称插件页徽章容器对「由 CI 的 hardcoded-color grep 静态把关」，实测 CI 无此步骤 | ⚠️ 挂账（文档轮不改代码） | `grep -n "Color(" .github/workflows/*.yaml` 零命中（仅 pr.yaml:105 的 ldd 'not found' grep）；两个 workflow 全文无 hardcoded 步骤 |
| 阻塞 | 上轮推送后的 CI 结论仍无法核实 | ⚠️ 本窗口不可测 | `gh run list -R emoeem/emoplay --limit 3` = `failed to get runs: ... EOF`（02:21 CST，api.github.com 不可达）；不引用旧 run 冒充本轮结论 |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`；时间锚点：
`gh run list` EOF 与 `date` 实测 02:21 CST，报告收笔 02:32 CST）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 5.3s)**：0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test`（全量） | **00:20 +345 ~1: All tests passed!**：35 文件（`ls test/*_test.dart \| wc -l` = 35；`find test -name '*_test.dart' \| wc -l` = 35，无嵌套目录，两口径一致）/ 345 通过 + 1 平台条件跳过（skip 维持 R4 口径：Windows-only probe） |
| 用例增量对账 | 345 − 342 = 3；35 − 34 = 1 | 自洽 ✓：+1 文件 / +3 用例 = `kazumi_alignment_ui_test.dart`（3 个 `testWidgets`，`grep -c` 实测 3） |
| AppImage 产物 | `ls -la` / `file` / `--appimage-help` / `git check-ignore -v` | 35,584,504 B；ELF 64-bit LSB pie executable, static-pie linked；runtime help 应答 exit 0；命中 `.gitignore:62 *.AppImage` |
| 卫生复核 | `ls web/`；`grep -n "connectivity_plus\|screen_brightness" pubspec.yaml` | web/ 不存在；ohos 消失，connectivity_plus `^6.0.5`（:18）与 android/ios/platform_interface（:44-46）仍在 |
| 代码生成 | **未跑**（文档轮；`git show --numstat` 三个提交核对：无 `.g.dart` 改动，无需生成步骤） | 记「未跑」，不冒充已测 |
| Linux debug 构建 | **未跑**（R5 实测通过仍为底数；R6 无原生构建面改动） | 记「未跑」，不冒充已测 |
| CI（main） | `gh run list -R emoeem/emoplay --limit 3` | `failed to get runs: Get "https://api.github.com/...": EOF`（02:21 CST）：**本窗口不可测** |
| 推送状态 | `git log origin/main..HEAD --oneline` | **6 个提交未推送**（`d446bb8` / `8ed84c4` / `1dc5d14` / `988122f` / `e1a2df0` / `b0e1a06`）；origin/main = `63d9f59`（branch -vv "ahead 6"） |
| 树干净度 | `git status --porcelain`（文档写作前） | **空** |

## 4. 确认无问题的部分

- **门禁数字独立复测吻合**：35 文件 / 345 通过 + 1 skipped 与施工轮
  HANDOVER 的声明一致；施工轮（01:4x 窗口）与本轮（02:2x）两次
  独立实测同数，skip 用例同一条（Windows-only probe），无新增 skip。
- **web/ 删除无残留引用**：删除后 analyze 0 告警 + 全量测试绿；
  `analysis_options.yaml` 现有 exclude 列表实读核对，无指向已删路径的条目。
- **AppImage 三处口径一致**：脚本输出的命名（`EmoPlay_linux_<tag>_<arch>`）
  = release.yaml upload path（`EmoPlay_linux_*_*.AppImage`）=
  `.gitignore` 规则（`*.AppImage`），三处逐字核对一致。
- **守护测试是网络无关测试**：`UrlLauncherPlatform` 记录型假体 +
  临时目录 path_provider 假体 + Hive 引导在 temp root（测试文件
  `:140`-`:171`），不触网、不碰用户数据；全量套件照常绿。
- **R6 提交改动面可控**：`git show --numstat` 三提交全量核对，无
  `.g.dart`、无原生平台目录（android/ios/linux/macos/windows）改动、无
  secrets / dart-define；workflow 改动仅 AppImage 相关三处（脚本新增、
  打包步、path 清单）。
- **树干净**：文档写作前 `git status --porcelain` 为空，本轮全部新增/
  修改均为 markdown + CHANGELOG.md。

## 5. 已知限制与未做项

**需要人工操作的**
- 推送六个施工提交 + 本轮文档提交（推送由收尾流程执行）；推送后核对
  CI 签名 **345 passed / 1 skipped**（本窗口 api.github.com 不可达，
  无法自查）。
- AppImage arm64 打包只能在 CI 首次真跑（本机 x86_64 无法验 aarch64），
  推送后看 flutter-build-linux-arm64 job；GitHub Release 资产列表里
  AppImage 是否如预期挂上，同样等下次 tag 演练。
- GUI 截图补拍填 README 占位（桌面空闲窗口；审计 §八工具链备注：
  指针类 E2E 必须空闲桌面执行）。
- AppImage 在真实桌面环境的安装表现（desktop/icon 集成、菜单项）人工
  点验。

**代码侧待办**
- `test/kazumi_alignment_ui_test.dart:16-20` 注释与 CI 现实二选一收口：
  给 pr.yaml 补 hardcoded-color grep 步骤（推荐，顺带守「无裸 Color()」）
  或把注释改成如实描述；别让注释描述不存在的把关。
- 路线图 §四勾选态收网：AppImage（§4.2-108 → ✅ `e1a2df0`）等；审计
  §九-1 的 CI timeout / Windows 双源两项已由 R5 `8ed84c4` 消账，但路线图
  正文仍未列（路线图轮次表只写到 R2）。
- `connectivity_plus` 必要性评估（审计 P2 后半，未决）。
- ldd「115-library closure」口径复测（审计 P2；需重建 `build/` 后以
  `readelf -d | NEEDED` 为准并回写 `package-linux.sh:58` 注释）。
- PORT-MAP §5 目标目录树对账（审计 P2）。
- 既有账目不变：release.yaml prerelease 语义、i18n 第三页起、Windows
  `emoplay://` URL 内容转发、1.x 对账最后一条
  （`restoreDefaultsKeepsMediaAndHistory`）。

**固有限制**
- 纯 markdown 推送不触发 CI（pr.yaml `paths-ignore: '**.md'`）；混合
  push 触发时 run 标题只显示头提交（R2/R3/R4 连续证实）。
- api.github.com 本窗口不可达：凡 CI 结论一律标「不可测」，不拿旧 run
  冒充本轮。
- x86_64 构建容器无法验证 aarch64 打包路径（本机只能验 amd64）。
- 无显示器构建环境：GUI 观感与截图依赖桌面空闲窗口（README 占位说明
  即为此而设，不产占位假图）。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送并盯 CI 签名**：`git push origin main` 后
   `gh run list -R emoeem/emoplay`，预期 **345 passed / 1 skipped**；红灯
   按 pr.yaml ldd 审计步的全量清单处理，不按测试报错逐层补。
2. **AppImage arm64 收尾**：看推送后 run 的 flutter-build-linux-arm64
   job（aarch64 linuxdeploy 打包首跑）；下次 tag 演练时核对 Release
   资产新增 `*.AppImage` 两枚。
3. **hardcoded-color grep 决策**：补 pr.yaml 步骤或修测试注释（§5 第一条
   待办，10 分钟级）。
4. **路线图收网**：§四勾选态同步（AppImage ✅ `e1a2df0`；CI timeout /
   双源 ✅ `8ed84c4`）+ 轮次表补 R3-R6。
5. **观感与截图**：桌面空闲窗口补拍五页签 + 播放面板截图填 README 占位，
   顺带做 AppImage 的 desktop 集成点验；i18n 第三页与 connectivity_plus
   评估按既有优先级排后。
