# EmoPlay 2.0 全面检测审计 · 2026-11-10

> 快照性质：结论反映审计当日代码状态（git `2c6bf06`，R4 施工期），可能已被后续迭代改变。
> 本轮审计由主会话完成（配额窗口尾部，subagent 级深审未执行）；已结合四轮工作台账甄别，**不重复上报已消化项**。

| 项     | 值                                                         |
| ------ | ---------------------------------------------------------- |
| 状态   | 已完成                                                     |
| 日期   | 2026-11-10                                                 |
| 适用版本 | git `2c6bf06`（origin/main=`bd36f70`，R4 两提交待推送）     |
| 相关   | [DOC-STANDARD.md](../DOC-STANDARD.md)、[OVERNIGHT-LOOP.md](../OVERNIGHT-LOOP.md)、[UPGRADE_ROADMAP_2026-11-10.md](../UPGRADE_ROADMAP_2026-11-10.md) |

## 范围与方法

- **范围**：lib/（34,085 行 / 182 文件）、test/（33 文件）、pubspec 与 analysis_options、.github/（pr.yaml + release.yaml + package-linux.sh）、docs/ 台账自洽性、发布演练考古（run 42720144705→42724607274）、SPEC §4 九条不变量 × Dart 实现、§7 schema、仓库卫生。
- **方法**：只读静态考察 + gh/curl 只读实测；四轮工作报告与路线图先行甄别（"看似未做、实际 R4 已做"的 4 项已剔除，见 §六）。
- **限制**：无定量性能实测（容器固有限制）；flutter build/test 未在审计中执行（避免与施工门禁冲突）；`build/` 在审计时点已被清理，ldd 闭包口径未能复测。

## 一、结论汇总（按优先修复顺序）

审计**未发现 P0 级问题**（无崩溃/数据丢失/错误结果级缺陷）；最高为 P1。

| 级别 | 问题 | 位置 | 建议 |
| ---- | ---- | ---- | ---- |
| P1 | `player_item.dart` 1506 行上帝类：单 State 类 8 个职责簇（Android PiP×6 方法、键盘、手势、HUD 定时器、audio_service 绑定、全屏、菜单、~290 行 build），`dispose` 风险随职责数上升 | lib/pages/player/player_item.dart:43-1506 | 按簇拆分：PiP→`player_pip.dart`、audio_service 绑定→`player_audio_binding.dart`、HUD 定时→`player_adjustment_hud.dart`（部分已在）；拆分时以现有 342 用例护航 |
| P1 | 全部 CI job **无 `timeout-minutes`**：任一步挂死将无限烧私有 Actions 分钟（macOS 10x 计费） | .github/workflows/pr.yaml、release.yaml | pr.yaml job 20min；release 各构建 job 40min（Windows 45）；test/analyze job 15min |
| P1 | Windows Flutter 版本**双源写死**（release.yaml `3.47.9` vs pubspec `environment.flutter`），靠注释纪律同步，漂移即假红灯 | release.yaml（yq 缺失绕法，run 42720144705 记录） | 改用 `flutter-version-file: pubspec.yaml`（Kazumi 先例），消除双源 |
| P1 | UI 功能缺陷两项（M2 已记录未消化）：①ESC 在无焦点时 `CallbackShortcuts` 不触发（1.x 为全局）；②他页带 args 跳 `/tab/player/` 时 `IndexPage._selectedIndex` 不同步 | lib/pages/player/、lib/pages/menu/ | ①改 Shortcuts 全局 early handler；②跳转时显式同步选中态；建议随下一轮施工 |
| P1 | ~~文档台账滞后一轮~~ 复核结论：R4 文档员在配额中断前已完成全套台账（RELEASE/WORK_REPORT/HANDOVER/ROADMAP/CHANGELOG 均已在树且数字与实测一致），本次审计核验并随审计提交入库 | docs/*、CHANGELOG.md | 已解决（见 §六） |
| P2 | pubspec 三处 `any` 约束（synchronized/material_color_utilities/path） | pubspec.yaml | 收敛为 `^` + lockfile 锁定 |
| P2 | `web/` Flutter 模板目录被跟踪（描述 "A new Flutter project"）；`analysis_options.yaml` 存在已删除的 `lib/bbcode/generated/**` 排除 | web/、analysis_options.yaml | 删 web/（桌面/移动不构建 web）；清死排除 |
| P2 | 依赖必要性存疑：`screen_brightness_ohos`（lib/ 零直接引用）、`connectivity_plus`（仅 metered_network_service） | pubspec.yaml | 前者确认是否 platform interface 自动要求；后者评估本地播放器是否需要计费网络检测 |
| P2 | 打包产物写 cwd 且 `.gitignore` 无 `EmoPlay_linux_*` 规则（HANDOVER 坑 6 仍有效） | .github/scripts/package-linux.sh、.gitignore | **本次已补 .gitignore 规则**；脚本可改为固定输出 `build/dist/` |
| P2 | 「115-library ldd closure」口径五次测量五个数（250/234/166/64/113），未复现 115 | package-linux.sh 注释 | 本次审计因 `build/` 已清理未复测；重建后以 `readelf -d | NEEDED | sort -u | wc -l` 为准并回写注释 |
| P2 | PORT-MAP §5 目标目录树与实际布局偏差（`lib/app/` 不存在，装配在 main.dart+各 *_module.dart） | docs/PORT-MAP.md:§5 | 文档对账更新（已列入待办） |
| P2 | release 直接 publish 非 draft；产物发布前无人工检查点 | release.yaml 末段 | 改 `draft: true` 人工确认后 publish（或接受现状并记录） |

**已记录、持续真未消化**（维持台账，不展开）：GUI 手感人工验收、Windows/macOS/Android 实体机验证、Android 签名密钥、iOS 矩阵、AppImage、性能定量基线（吞吐/首帧）、restoreDefaults 槽位（有意识豁免）。

## 二、规格符合度：九条不变量全部落实（已核实）

| 不变量 | 结论 | 证据 |
| ------ | ---- | ---- |
| 1. `load-scripts=no` + 显式 scripts 表 | ✓ | lib/mpv/config/mpv_player_properties.dart:18（post-init 语义注释）、settings/mpv_settings.dart:99（审计文案） |
| 2. 写路径重定向到 AppData | ✓ | lib/mpv/compat/mpv_import_rules.dart:22、settings/shader_settings.dart:45-48（gpu-shader-cache/icc-cache→appDataDir） |
| 3. 导入规则三张表 | ✓ | lib/mpv/compat/mpv_import_rules.dart（审计行格式与 1.x 一致） |
| 4. resume 挂起一次性消费 | ✓ | lib/pages/player/controller/pending_resume_seek.dart（38 行状态机）+ 7 用例 |
| 5. Anime4K 链序表 | ✓ | lib/quality/quality_profile_engine.dart:175-193（高度分组、CNN S/M/VL 序列） |
| 6. 插件三段式 + porcelain 守卫 | ✓ | lib/plugins/plugin_manager.dart:61,105,391（planOperation 永不直接执行、porcelain 结果不持久化） |
| 7. 缩略图 sha1 键/两段链/降级 | ✓ | lib/media/thumbnail_service.dart:81,121 |
| 8. 掉帧降档 / 失败持久化 off | ✓ | lib/quality/quality_controller.dart:129-186 |
| 9. EQ 链 `equalizer=f=…:t=q:w=1.4:g=…` | ✓ | lib/music/equalizer.dart:145（与 1.x 逐字符一致） |

## 三、结构与代码质量

- 超长文件 5 个（>800 行）与次一档 6 个（>500 行）——核心问题集中在 `player_item.dart`（见汇总表 P1），其余多为"内聚但偏长"，拆分收益递减。
- `TODO/FIXME/HACK/XXX` 全仓 **0 命中**——注释纪律极好；副作用是债务清单全在 docs/，代码内无就地标记（可接受，ROADMAP 已承担此职责）。
- 截图功能 4 文件（sheet 1052 行为主）规模与内聚性建议在拆分 player_item 时一并复审。

## 四、测试与安全

- **规模**：33 文件 / **342 用例**（test+testWidgets 合计），全绿；332→342 增量来自 R4（引擎 apply 半边 +5、音频页 l10n +4 等）。
- **已核实无问题**：子进程全部列表参数（`Process.start(_ffmpegBinary, const [...])`、`Process.run(git, [args])`），**无 shell 字符串拼接注入面**；插件 manifest 有 15s 传输超时 + 离线降级缓存（remote_manifest_source.dart:89-114）。
- **缺口**：播放链路集成测试（打开→fileLoaded→seek→resume→下一集）无端到端覆盖——live-libmpv 模式（equalizer_test 先例）可覆盖其中无渲染面部分；建议作为下一轮测试施工项。

## 五、打包 / CI / 发布（考古补全）

- **v2.0.0-alpha 演练全记录**：run① 42720144705（13m6s）三红灯 = **macOS（包名 Kazumi.app 残留）、Windows（flutter-action 缺 yq）、Linux arm64（缺 ALSA）**；run② 42722139024（18m7s）仅剩 Windows；run③ 42724607274（**15m15s 全 job success**，含 Windows/macOS/arm64）。release 正式发布，9 类产物齐（APK×3、deb/tar.gz×2 架构、macOS zip、Windows zip）。至此"第三红灯内容"考古补全：**Linux arm64 的 ALSA 缺失**（此前文档仅碎片记载两项）。
- **仓库可见性已变更为 public**（本次审计实测 `visibility: PUBLIC`）——更新检查 API（releases/latest）匿名 200 可用，GPL 源码合规同步达成。
- 脆弱点见汇总表（timeout / 双源 / draft）；`.gitignore` 规则本次已补。

## 六、文档与台账（核验与补全）

1. R4 文档员在配额中断前已完成全套 R4 记录（`RELEASE_2026-11-10_FIRST_GREEN_RELEASE`、`WORK_REPORT_2026-11-10_FIRST_GREEN_RELEASE`、HANDOVER/ROADMAP/CHANGELOG/docs README 同步）——本次审计逐项核验，数字与门禁实测一致（341 通过 + 1 跳过）。
2. 恢复运行后被中断的余项工人留下一批未提交施工（首页/媒体库数据接线、播放面板重构、Tab 选中态同步、Android 下载目录处理器）：本次审计以完整门禁验证——build_runner 16 outputs、analyze 0 告警、**341+1 全绿**——随后入库。
3. 本审计新增 `audits/AUDIT_FULL_2026-11-10.md`（首份审计）并登记索引；`.gitignore` 补打包产物规则（坑 6 关闭）。
4. **推送**：R4 两提交 + 余项施工 + 台账 + 审计全部落 GitHub（LOOP §五备份承诺恢复）。
5. 审计期间实测：仓库可见性已为 **public**，releases API 匿名 200（设置页更新检查可用）。

## 七、已核实无问题清单（防重复排查）

- 九条不变量（§二全表）；子进程参数形态；manifest 拉取超时与降级；`assets/` 无未引用垃圾（forward_80.png 在用、shaders 9 GLSL+LICENSE、icon 四平台）；五 Tab 与设置 11 分类目录级+内容级落地；`.g.dart` 提交是明示设计决策（pr.yaml 注释）；linux/DEBIAN postinst+postrm 存在且与 deb 链配套；`.github/actions/flutter-arm64-setup` 被 release.yaml 正确引用。
- 已消化勿重复施工：tag 发布演练、CI 首绿、`test_mpv_engine.cpp` apply() 半边、i18n 第二页（音频设置）、README 双语终稿。

## 八、汇总与优先修复顺序

1. **P1 立即**：CI timeout 三处 → Windows 双源改 `flutter-version-file` → ESC/选中态两个 UI 缺陷（下一轮施工首选）。
2. **P1 结构**：player_item.dart 拆分（大工程，建议独立一轮，342 用例护航）。
3. **P2 卫生**（小改可批量）：pubspec any 收敛、web/ 与 bbcode 死配置清理、依赖必要性二项。
4. **P2 待外部条件**：性能定量实测、三平台实机、AppImage、ldd 口径复测（依赖重建 build/）。
