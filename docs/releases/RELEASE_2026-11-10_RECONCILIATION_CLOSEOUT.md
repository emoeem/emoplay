# 更新说明 · 2026-11-10（对账收网 R1）

> 迁移主流程 M1–M8 完成后的第一轮对账收网：设置中心的「更新检查」从占位开关变成
> 真正能用的功能（只提示、不下载、失败静默，与 1.x 行为一致）；修掉了 CI 从未
> 跑过一次的触发分支笔误（`master` → `main`）；按 PORT-MAP §4 把 C++ 用例表与
> Dart 测试逐一对账，补齐 3 个画质控制器测试面。全仓 28 个测试文件 313 条用例
> 通过（另有 1 条 Windows 专属探测按 QSKIP 契约在非 Windows 平台跳过），
> `flutter analyze` 0 告警，Linux debug 构建通过。

| 项         | 值                                                                    |
| ---------- | --------------------------------------------------------------------- |
| 版本       | git `a7488d9`（05:45 CST，R1: test parity）                            |
| 平台       | Linux（容器内实测：analyze / test / debug build）；Windows/macOS/Android 待 CI 与实体机验证 |
| 自动化测试 | **28 文件 / 313 用例通过 + 1 平台条件跳过，全绿**（上轮 M8 未留下用例数实测记录，测试文件数 26 → 28，+2） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 2.2s)`）    |
| CI         | **零 run**（`gh run list --json` 返回 `[]`）——根因见下文二-1；修复提交 `916c2d6` 尚未推送，首跑待推送后确认 |

## 一、面向用户的变化

### 1.1 更新检查真正上线（M7 留下的占位开关补全）

设置中心「更新检查」页（`lib/pages/settings/update_settings.dart`）此前只有
一个持久化开关和一条"M8 再接入"的注释；本轮把 1.x 的
`src/update/UpdateChecker.cpp` 完整平移为 `lib/services/update_checker.dart`
（335 行，纯函数 `tagToVersion` / `compareVersions` / `isNewer` 逐行直译，
考证注释随行平移），并接上两处装配：

- **启动检查**：`lib/main.dart` 在启动 3 秒后、且「自动检查更新」开关为开
  （默认开）时，向 GitHub Releases API（`repos/emoeem/emoplay/releases/latest`）
  发**至多一次** GET——1.x 的 `src/main.cpp:315-321` 语义，刻意延迟以不与启动争资源。
- **结果只报告，永不下载安装**：确认有新版本时，设置页内出现发布页入口
  （1.x `qml/UpdateBadge.qml` 的角色），打开页面是用户主动动作（url_launcher）。
- **失败完全静默**：离线 / HTTP 错误 / JSON 损坏 / 字段缺失 / 超时，一律只触发
  checkFinished 回调——断网启动的观感与"已是最新"完全一致，这是 1.x 的明确契约。

与 1.x 的唯一差异是端点：1.x 查询 `emoeem/mpv-emo`，2.0 按身份（SPEC §1）改查
`emoeem/emoplay`，版本语法、比较规则、静默失败、在途去重全部不变
（见 `lib/services/update_checker.dart:17-19` 的端点注记）。

## 二、修复与根因

### 2.1 CI 从未运行过：触发分支写的是 `master`，仓库分支是 `main`

现象：仓库自 M1 起推送过多次，`gh run list` 却始终为空（本轮实测仍为 `[]`）。
根因：`.github/workflows/pr.yaml` 的 `on.push.branches` 写的是 `master`，而仓库
主分支从建仓起就叫 `main`——M1–M8 的每次推送都被 GitHub 静默跳过，没有任何
失败记录可查。修复：`916c2d6`（R1: ci trigger main，1 行改动）。推送策略不变：
push/PR 仅单 job Linux analyze+test+build（paths-ignore 忽略 `**.md`，纯文档
推送不触发），全平台打包矩阵仅 `v*` tag 触发。

### 2.2 画质 / 插值控制器忽略"外部写入者"：MobX 镜像与 1.x Q_PROPERTY 语义不一致

写 `quality_engine_test.dart` 的对账用例时发现：1.x 的
`InterpolationController.cpp L34/L42` 与 `QualityController.cpp L199-208` 每次
apply 都经 Q_PROPERTY getter **实时重读**持久化设置；Dart 侧的 MobX 镜像字段
却只在 setter 里更新——如果 settings.json 在控制器之外被改写（比如换文件间隔
用户改了设置、或外部写入者损坏了预设 id），下一次 apply 不会生效。修复
（`a7488d9`）：`lib/quality/interpolation_controller.dart:172` 与
`lib/quality/quality_controller.dart:375` 在每次 apply 入口用 `runInAction`
从设置重同步镜像。正常面板流程里 setter 先持久化再 apply，所以这是一次无害的
no-op；异常路径（损坏的 settings.json）则因未知预设 id 的既有防御保持"什么都不开"。

## 三、已知取舍

- **CI 首跑结果未知**：修复已提交但 R1 的三个提交（`916c2d6`/`d1866dd`/`a7488d9`）
  在本说明写就时尚未推送；`ubuntu-latest` 上首次真实运行可能暴露容器内不存在的
  依赖问题（GTK/命名包版本等），首绿待推送后确认。
- **1 条用例平台条件跳过**：`test/mpv_profile_scanner_test.dart:217`
  `locateOnWindowsUsesAppData` 仅在 Windows 上执行（1.x QSKIP 契约的对应物），
  Linux 上显示为 skipped（本轮 `~1`）。
- **上轮用例数无实测记录可比**：M1–M8 各阶段未按规范留下测试数记录，本轮发布
  说明只能给出文件数对比（26 → 28），用例级增量（R1 新增 update_checker 381 行、
  quality_engine 294 行等）见工作报告。
- **Windows/macOS/Android 产物仍未实体机验证**，Android APK 仍未签名，iOS 仍在
  发布矩阵外——与 2.0.0-alpha 既有已知限制一致，本轮未变化。
