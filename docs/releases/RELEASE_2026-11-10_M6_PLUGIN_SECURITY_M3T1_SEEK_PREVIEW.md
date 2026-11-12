# 更新说明 · 2026-11-10（M6 插件安全 + M3-T1 帧预览 R12）

> 第 12 轮施工：插件安全四任务一次做完，即清单资产完整性（size+sha256
> 缺一拒装 + 装前内容校验）、操作审计落盘（append-only JSONL，拒绝也
> 留痕）、destination 防穿越 fuzz + 操作白名单、插件页 catalog 重组；
> 顺带清偿 M3-T1 进度条帧预览（第二解码实例，hover/拖动出帧图）。修掉
> 的隐患：用户带注释的 mpv.conf 在 2.0 兼容层把注释文本当成了值，
> audio-device 变成 `auto # 此项用于…`，设备找不到，每次开文件都以
> 「Could not open/initialize audio device -> no sound」收场（用户报告，
> v2.2.0-alpha / v2.3.0-alpha 均可复现）。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `3514db3`（2026-11-13 00:30 CST，R12: seek preview controller (M3-T1)）。本轮五提交（`757d130` 11-12 08:10 / `0919ccc` 11-12 08:23 / `07427f8` 11-12 08:54 / `7b89bb0` 11-12 23:40 / `3514db3` 11-13 00:30，均 CST）落在 11-12 至 11-13 窗口，文档沿用 2026-11-10 计划窗口命名（同 R1-R11 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试（CI 本窗口不可测，详见[工作报告 §3](../reports/WORK_REPORT_2026-11-10_M6_PLUGIN_SECURITY_M3T1_SEEK_PREVIEW.md)）；Windows / macOS / Android / arm64 待 CI 与实体机验证 |
| 自动化测试 | **63 文件 / 585 通过 + 1 平台条件跳过，全绿**（上轮 60 文件 / 539 通过 + 1 跳过；+3 文件 / +46 用例。46 的构成逐文件实测点数：plugin_manager +10、seek_preview_controller 10（新）、plugin_catalog 9（新）、plugin_manifest +5、plugin_audit 5（新）、mpv_config_parser +4、performance_guards +2、mpv_import_rules +1，合计与全量差值 585-539 一致，见工作报告 §3） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 7.6s)`，2026-11-13 本文档窗口实测）                                                               |
| CI         | 本窗口不可测：`gh run list` EOF（api.github.com 不可达，2026-11-13）。`757d130` / `0919ccc` / `07427f8` 已推送（origin/main = `07427f8`），`7b89bb0` / `3514db3` 未推送（ahead 2）；推送后预期签名 **585 passed / 1 skipped**（未测：远端尚未载入 R12 全部提交） |

## 一、插件清单资产完整性：size+sha256 缺一拒装（`757d130`，M6-T1）

结论：插件清单（manager.json / 在线源条目）新增可选的资产完整性对
`sizeBytes` + `sha256`（`lib/plugins/plugin_manifest.dart`）。两个字段是
**全有全无**的一对：只声明其一的清单拒绝安装（`integrityGateError()`，
拒绝理由随返回值给出）；两个都不声明的清单保持 1.x 行为逐位不变。

- **校验点在整条安装链的最前面**：install 与 replace 型 update 都在
  **任何 git 命令（包括 ls-remote）跑之前**先过完整性门
  （`lib/plugins/plugin_manager.dart` install/update 入口）；check 型
  update 不动文件，不需要 pin。
- **克隆内容先验后记**：clone 完成后、写入 state.json（install）或备份/
  换装（replace update）之前，用 manifest 钉住的 size+hash 校验刚克隆的
  内容树（`PluginContentIntegrity.verify`，`lib/plugins/plugin_git_runner.dart`）。
  不匹配即删除刚克隆的树，**未经校验的安装永远不会变得可见**。
- **摘要定义确定性、可重放**：只算内容树的普通文件（`.git` 目录剪枝、
  符号链接整个跳过），按相对 POSIX 路径排序，逐文件一行
  `<文件 sha256>  <相对路径>\n` 再对整份清单取 sha256；字节数独立于摘要
  单独核对，且先比大小再比摘要，每次失败都能说清到底哪一项偏离。
- **默认不加字段 = 行为零变化**：1.x 的 manager.json 没有这两个字段，
  `toMap()` 只在声明了字段时才输出它们（字段往返用例
  `integrityFieldsRoundtrip` 锁定），旧清单 / 旧在线源不受影响。

## 二、插件操作审计：plugin_audit.jsonl 落盘（`757d130`，M6-T2）

结论：`PluginManager` 的每次判定都留痕。新 AppData 文件
`<appDataDir>/plugin_audit.jsonl`（`plugins/` 目录的兄弟文件，绝不写
用户主目录或当前目录），append-only：每次写入都是打开-追加，从不重写、
轮转或截断，崩溃也不丢历史。

- **两类事件**：`plan` 是 `planOperation()`（永不直接执行的判定链）的
  每次调用结果，接受带变更清单、拒绝带拒绝理由；`operation` 是每次
  终态操作结果，**被拒绝的也记**（busy / 已安装 / porcelain 本地改动
  防线 / 内容完整性拒绝都流经同一出口）。三段式契约本身不变：
  plan → UI 确认 → 执行，审计只观察、不阻断。
- **观察性优先**：写失败记日志并吞掉，审计永远不能弄坏一次插件操作；
  读取时跳过解不出 JSON 对象的行，半截写入或手改降级为少几条记录，
  从不报错（`PluginAuditLog`，`lib/plugins/plugin_manager.dart` 尾部）。

## 三、插件暴力面收缩：防穿越 fuzz + 操作白名单（`0919ccc`，M6-T3）

结论：两层收紧，都是「默认拒绝」。

- **destination 防穿越**：清单的 destination/source 只能经
  `PluginManifest.parseList` 摄入，其 `isSafeRelativePath` 闸门拒绝绝对
  路径、`..` 段与反斜杠（闸门 M1 起就在，本轮把它钉死在端到端
  fuzz 段）。fuzz 语料实测 12 条敌意 destination（`..` 穿越 / 绝对路径 /
  Windows 盘符 / 反斜杠混合 / 空段 `..` 混合等，
  `test/plugin_manager_test.dart` `kHostileDestinations`）+ 4 条
  「形似而非穿越」对照（`..%2f`、`foo..`、空白词干、unicode 词干，必须
  放行且派生出的 entry 路径逐段证明不逃出内容根）+ 两类符号链接用例：
  安装目标本身是指向 plugins 根之外的符号链接时拒绝且原样未动；克隆
  内容内的符号链接永不进摘要。
- **操作白名单常量化**：`planOperation` 收的字符串动作收敛为显式常量
  `allowedOperations = [install, uninstall, update, check]`
  （`lib/plugins/plugin_manager.dart`），未知动作在任何变更清单字符串被
  拼出来之前就拒绝；install/uninstall/update/checkForUpdate 四个执行器
  都是不吃字符串动作的类型化包装，这张表因此是整个模块唯一的字符串
  操作入口。

## 四、插件页 catalog 重组（`7b89bb0`，M6-T4）

结论：插件页按 Kazumi plugin_editor 范式重组：目录视图（搜索框 +
全部/已安装/可更新三个过滤 chip，作用于三段各自的行）+ 每插件详情页
+ 更新动作独立成件。**三段式 UI 语义不变**（不变量 6：本地安装 / 仓库
/ 目录三段不合并不裁剪，过滤只是变换视图）。

- 单文件 `plugins_page.dart` 577 → 485 行，拆出四件（全部 < 600 行）：
  `plugin_catalog_dispatch.dart`（137 行：目录⇄详情视图切换、详情路由
  只为能在已同步目录行里解析出的名字打开、行消失自动回退目录视图）、
  `plugin_catalog_row.dart`（228 行）、`plugin_detail_page.dart`
  （244 行）、`plugin_update_actions.dart`（138 行）。
- 三段式语义由 `filterAndSearchShapeTheDirectoryWithoutMergingSections`
  用例锁定；「经确认的操作是通向 manager 的唯一漏斗」由
  `executeConfirmedOperationIsTheOnlyFunnelToTheManager` 锁定。

## 五、进度条帧预览（`3514db3`，M3-T1）

结论：进度条 hover / 拖动出帧图，第二 media_kit 解码实例
（Haruna `MpvPreview` 语义移植），开关**默认关**，关闭时零第二实例
开销。新设置项两枚：`seekPreview`（默认 false）与 `seekPreviewWidth`
（默认 200，滑杆 120-400 逻辑像素，`lib/pages/settings/player_settings.dart`
与 `lib/services/storage/settings_keys.dart:268,275`）。

- **默认关的理由**：Haruna `generalsettings.kcfg` 同名项
  `ShowPreviewThumbnail` 即 default=false，且关闭时第二解码实例根本不
  建（实例数守卫用例锁定），最接近 Kazumi/1.x 现状（SPEC §10 兜底）；
  宽度默认 200 同 Haruna `PreviewThumbnailWidth`。
- **预览实例的属性集与 Haruna 逐项等价**：`seekPreviewMpvProperties`
  常量表（`lib/pages/player/controller/seek_preview_controller.dart:62`）
  是生产创建与测试断言共用的单一代码通道：mute/pause 关声画输出、
  aid/audio-file-auto/sid/sub-auto/audio-display 全关（预览只要帧）、
  osd-level=0、audio-pitch-correction=no（mpvpreview.cpp:21-38 原文）。
  差异均有考证随行（文件头）：`vo=libmpv` 不手写（fork attach 时自己
  写，且 fork 预置 vid=no，所以预览必须 attach VideoController 才有
  画面，Video widget 直接吃纹理）；`really-quiet` 转译为日志级别 error；
  hr-seek 跟随主通道（bundled libmpv 空闲核回读 hr-seek=yes，绝对
  seek 已精确，2026-11-13 probe 实测）。
- **行为语义**：激活门禁 = 开 && 文件非空 && isLocalFile && isVideo &&
  非停止（与 Haruna HProgressBar.qml 同条件）；hover 懒建实例 + 100ms
  消抖 seek（只认最后一次位置）；**隐藏即取消挂起 seek 并 pause 实例**
  （不拆除，Haruna Loader active 语义，下次 hover 零重建开销）；换文件
  重置重建；dispose 链幂等。拖动中（鼠标拖）主实例与预览实例双 seek。
  气泡除帧图外带章节标题（复用 M3-T2 的 `chapterIndexAt` 上界二分）。
- **生效性实测边界**：属性集在 bundled libmpv 空闲核上全部被接受且回读
  逐项一致（2026-11-13 临时 probe，跑毕即删，记录在控制器文件头）；
  但帧图纹理依赖 VideoOutputManager 平台通道，flutter_test 无原生端，
  **画面效果待 linux 构建的 GUI 人工验收（SPEC §9）**。

## 六、修复：带注释的 mpv.conf 导致无声（`07427f8`）

结论：1.x 里 mpv 自己读 mpv.conf，空白符前导的 `#` 是行尾注释；2.0
兼容层把每行解析成运行时属性下发给 mpv，而运行时属性语境里 `#` 不是
注释。数字型选项应用直接失败（osd-\*、sub-\*、colors、audio-channels、
audio-format 等），字符串型更隐蔽：**静默把注释文本当值收下**，
`audio-device` 变成 `auto # 此项用于指定启动时的音频输出设备`，开文件
时设备找不到，每个会话以「Could not open/initialize audio device ->
no sound」告终（用户报告 2026-11-12，v2.2.0-alpha / v2.3.0-alpha 可复现）。

- **根因修复**：`MpvConfigParser.runtimeOptionValue`
  （`lib/mpv/config/mpv_config_parser.dart:137`）复刻 mpv 的文件语义：
  前导空白后的 `#` 起注释；紧贴值首的 `#`（`osd-color=#F8F8F2`）是
  颜色码，保留。`parseMpvConf` 仍保留原始行，设置编辑器的往返不受影响；
  审计表报告清洗后的值。
- 5 条回归测试直接取自报告人的真实 conf 行（`mpv_config_parser_test`
  +4、`mpv_import_rules_test` +1）。

## 七、已知取舍

1. **帧预览的画面效果未人工验收**：属性层 live 探针全过 + 10 个逻辑
   用例全绿，但纹理路径依赖平台通道，flutter_test 无法覆盖；帧图显示
   归 SPEC §9（同 replaygain 听感、TMDB 真实数据流的挂账先例）。
2. **hr-seek 跟随主通道，不设预览独立键**：Haruna 的
   `accuratePreviewThumbnail`（独立 hr-seek 开关，默认 false）未搬，
   EmoPlay 按 ask 只落「开关 + 预览宽度」两键；bundled libmpv 实测
   hr-seek=yes，绝对 seek 已精确，两侧零配置即一致。
3. **完整性校验是 opt-in**：不声明 size+hash 的清单保持 1.x 行为
   （在线源兼容性优先）；只有声明了的条目才受装前校验。1.x 内容不受
   影响是设计目标，不是遗漏。
4. **审计是观察性日志**：写失败吞掉、从不阻断操作；损坏行跳过降级为
   少几条记录。审计不是安全边界，三段式确认链才是。
5. **`test/plugin_audit_test.dart` 在 git 里是二进制**：损坏行夹具
   （`test/plugin_audit_test.dart:117`）有意内嵌字面 NUL 字节，git 据
   此把整个文件按二进制处理（`757d130 --stat` 显示 `Bin 0 -> 10024`），
   该文件的 diff 无法文本评审；评审请直接读文件。
6. **CI 签名 585 / 1 为预期值**：R12 后两提交未推送（ahead 2），远端
   尚未载入；推送后按 HANDOVER 坑 2 的归因链核对（run 标题只显示头
   提交）。
7. **路线图勾选回填在工作树**：M6-T1/T2/T3/T4 与 M3-T1 ☐→✅+哈希已
   回填（与五提交逐一相符），随本轮文档提交入库（同 R10/R11 惯例）。
