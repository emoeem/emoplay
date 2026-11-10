# media-kit Fork 治理（Predidit/media-kit@83b7ca6 差异清单、同步与升级回归）

| 项       | 值 |
| -------- | --- |
| 状态     | 生效中（差异清单已取证；同步机制待首次季度执行） |
| 日期     | 2026-11-11（建立） |
| 适用版本 | git `bdad604`；内核 pin `83b7ca63772856e1ea0158916177e136f7b7b0be` |
| 相关     | [EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md) §六（fork 升级必经本文）、[CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md)（回归行）、[SPEC.md](SPEC.md) §2（锁 commit 决策） |

## 一、结论先行

EmoPlay 的播放内核是 **Predidit/media-kit fork，双包锁同一 commit `83b7ca63`**
（`pubspec.yaml:52-62`：`media_kit` 走 `path: ./media_kit`、`media_kit_video`
走 `path: ./media_kit_video`，ref 相同；`pubspec.lock` resolved-ref 与之一致，
2026-11-11 实测）。该 fork 相对上游 media-kit/media-kit 的差异是**结构性**的
而非零星补丁：native assets 构建体系（告别全部 `media_kit_libs_*` 容器包）、
自建 libmpv 二进制分发（`media_kit/hook/native_bundles.json` 单一真源 + sha256）、
OHOS 平台支持、Linux/Windows 渲染管线增强。治理三原则：

1. **升级不走悄悄路**：pin 变更必经 §四回归流程，且两包 ref 必须同步改
   （fork 自述要求同一 checkout，见 §三-1 证据）。
2. **渲染/硬解类红灯先查 fork**：见 [CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md) §六归因顺序。
3. **可上游的修复尽量上游**（§五），降低长期分叉成本。

## 二、锁定现状（实测证据）

| 项 | 值 | 证据 |
| --- | --- | --- |
| 应用侧 pin | `Predidit/media-kit@83b7ca63`，双包同 ref | `pubspec.yaml:52-62`、`pubspec.lock`（2026-11-11 读） |
| 本地取证副本 | `/opt/pub-cache/git/media-kit-83b7ca63772856e1ea0158916177e136f7b7b0be`（含完整 git 历史，2062 commits；`git log --oneline | wc -l` 实测） | 2026-11-11 实测 |
| fork 包版本 | media_kit `1.1.11` + **Unreleased**（native assets 未发版）；media_kit_video `1.2.5` | fork 内 `media_kit/pubspec.yaml`、`media_kit_video/pubspec.yaml`、两包 CHANGELOG 头部（2026-11-11 读） |
| 实际跑的 libmpv | `mpv v0.41.0-11-gf011d73d5-dirty`（Linux 构建产物 build/native_assets/linux/libmpv.so.2，2026-11-10 探针） | `lib/mpv/config/mpv_player_properties.dart:15-17` 文件头考证注释 |
| CI 消费方式 | pr.yaml 先装 native build tools，再 `flutter test`，构建后 ldd 审计产物 | `.github/workflows/pr.yaml:82`（Install native build tools）、`:104`（ldd build/native_assets/linux/libmpv.so.2 审计步） |
| 工具链要求 | Dart 3.10+ 且 Flutter 3.38+（native assets）；EmoPlay `sdk >=3.10.0`、`flutter 3.47.9` 满足 | fork `media_kit/doc/native_assets.md` + `pubspec.yaml:8-10` |

## 三、差异清单（fork 相对上游 media-kit/media-kit）

结论：按主题分组，全部条目取自本地 checkout 的 git log 与文件（2026-11-11
实测，commit 短哈希可直接 `git show` 复核）。**与上游的精确 merge-base 未能
离线计算**（§六），以下按「fork 自己的 PR/提交主题」归组，基线判断为上游
media_kit 1.1.11 / media_kit_video 1.2.5 时代（fork CHANGELOG 的已发布小节与
上游发布版本一致）。

### 3.1 native assets 构建体系（最大差异，破坏性）

- **内容**：Dart 3.10+ native assets；二进制由核心包 build hook 下载与编译；
  删除全部 `media_kit_libs_*` 容器包与 Gradle JAR 下载、CMake 库下载、
  CocoaPods Makefile、SwiftPM binary target；事件循环改 native-owned
  （finalizer 在 isolate/engine 销毁后仍安全）；播放器生命周期重建。
- **证据**：`media_kit/CHANGELOG.md` Unreleased 小节（原文四条）；fork 提交
  `a1b34d37`（migrate native assets and rebuild player lifecycle）、
  `d13fc22b`（native build hooks code assets 2）、`6fd002aa`（restore native
  builds CI）；hook 代码 `media_kit/hook/build.dart` 与 `media_kit/hook/src/`
  （apple/bundles/ohos/process 四文件，目录实测）。
- **对 EmoPlay 的含义**：`media_kit_libs_*` 从不出现在依赖里；ldd 审计对象是
  `build/native_assets/` 产物（pr.yaml:104）；**升级 Flutter/Dart 版本前先看
  fork 是否支持新工具链**。

### 3.2 libmpv 二进制自建分发与版本（全部平台，sha256 锁定）

单一真源 `media_kit/hook/native_bundles.json`（schema+bundles 两键，13 个
target，2026-11-11 实测读出）：每条目 = 归档 URL + sha256 + 架构 + 主库名。

| target | 来源（URL 实测） |
| --- | --- |
| linux_x64 / linux_arm64 | `Predidit/libmpv-linux-build` **20260810**（x64 条目 sha256 `45922100e5…`，主库 libmpv.so.2） |
| windows_x64 / windows_arm64 | `Predidit/libmpv-win32-video-cmake` **202609151348**（mpv-dev-x86_64-20260915） |
| macos_arm64 / macos_x64 / ios_arm64 / ios_x64 | `Predidit/libmpv-darwin-build` **0.6.8** XCFrameworks（0.6.7 起经 SwiftPM 接入，fork `13b332ad` #31） |
| android_arm64/arm/x64/ia32 | `Predidit/libmpv-android-video-build` **v1.3.1**（pin 提交 `83b7ca63` 本身；v1.3.0 为 `6b188ae9`） |
| ohos_arm64 | `ErBWs/libmpv-ohos-build` **20260811** |

相关 fork 提交：`90ea5598`（mpv 0.41）、`6d744e4a`/`e3d51713`/`8241881c`
（linux 20260804/20260730/20260728）、`78d4cce7`/`4e1aafe0`（windows
202609151348/20260915）、`994465d9`（native video libraries 升级）。
缓存机制：内容寻址缓存 + 文件锁串行构建 + 损坏自修复
（`media_kit/doc/native_assets.md` Ownership 节）。

### 3.3 OHOS（鸿蒙）支持（上游没有）

- 提交：`7d1e3f81`（feat: add ohos support (#2)(#25)）、`afb5a1b1`（ohos libmpv
  ad blocker #26）、`652cfc76`（ohos 硬解 #35）、`99c7358b`（ohos 硬解性能 #40）、
  `9c31fe57`（ohos native assets 构建 #43）。
- 代码：`media_kit/hook/src/ohos.dart`、`test/hook/ohos_test.dart`、
  `media_kit/lib/src/player/native/utils/`（asset_loader/temp_file 内 ohos 分支，
  grep 'ohos' 命中清单实测）。
- **对 EmoPlay 的含义**：零影响（EmoPlay 无 OHOS 目标），但它是 fork 存在的
  主因之一；上游同步时 OHOS 面几乎必然保留在 fork 侧。fork 文档自述 Kazumi
  用的是 `tignioj/media-kit` 的 OHOS 适配（`doc/native_assets.md` 末段），
  即生态里存在多个 OHOS fork 变体，**引用时不要混认**。

### 3.4 桌面/移动渲染与硬解增强

- Linux：专用 mpv 渲染线程（`1e70872a` #11）、double/triple buffer 与 swap
  chain 修复（`6bb4b5df` #13、`c1829525` #14、`261c1012`、triple buffer
  `480c1e18` #15、fence 受损设备延迟一帧防闪烁 `b58dbf8f`）、
  VAAPI zero-copy 修复（`a9467290`）、pulse 音频掉帧修复（`3ec38cd3`）、
  仅 epoxy（`d1ac737b` #24）、x11 硬解（`df5a969e` #37）、OSC 噪音抑制
  （`b11ec805` #38）、aarch64 支持（`fd330cea` #6）。
- Windows：native D3D11 renderer（`9c94fabd` #5）、mailbox triple buffering
  （`d19286c1` #28）、no stall pipeline（`21aacaf9` #29）、arm64 libmpv
  （`11d02cb8` #34）。
- Android：SurfaceTexture 回退选项（`87cdfef7`）、gles shader 编译修复
  （`4cd7c295` #27）、API26 支持（`b08e0744` #23）、16K page size
  （`ad84c59f`）。
- 通用：video bitrate 暴露（`11f72195` #33）、safe screenshot（`a7d4a070` #32）、
  http proxy 支持（`037fbf8f`）、ad blocker（`66d46c3d` #16）、不可用 mpv
  属性安全处理（`803c4a27`）、libplacebo shaderc vulkan 1.4 补丁（`c04ddeea` #22）、
  gpu-next 在 vulkan 1.1-only 设备的修复（`e3732e30`）。

复核命令（全部短哈希可重放）：
`git -C /opt/pub-cache/git/media-kit-83b7ca63772856e1ea0158916177e136f7b7b0be log --oneline`。

### 3.5 上游同期修复（fork 继承，非 fork 原创）

fork 历史包含上游 PR 编号（4 位数，如 #1274/#1275/#1283/#1294/#1107）的提交
（android seek 位置修复、16k page size、method call 主线程化等），`git log`
实测在案。这意味着**对比上游新提交时，先确认 fork 是否已含同名修复**，避免
重复 cherry-pick。

## 四、上游同步机制（季度对比 + 升级回归流程）

**季度对比（只读，不动 pin）**，每次执行后在本文件 §六登记：

```bash
# 1. 刷新本地副本（走 pub cache 的镜像目录只读拉取，或新克隆到 /tmp）
git clone https://github.com/Predidit/media-kit.git /tmp/media-kit-fork
git -C /tmp/media-kit-fork remote add upstream https://github.com/media-kit/media-kit.git
git -C /tmp/media-kit-fork fetch upstream main
# 2. fork-point 与两侧增量（首次执行即得 merge-base，补 §六欠账）
git -C /tmp/media-kit-fork merge-base 83b7ca63 upstream/main
git -C /tmp/media-kit-fork log --oneline 83b7ca63..upstream/main
# 3. fork 自身增量（新于当前 pin 的 fork 提交）
git -C /tmp/media-kit-fork log --oneline 83b7ca63..origin/main
```

**pin 升级回归流程**（fork 侧有需要的修复/二进制时执行；全程宿主机零污染，
`source /opt/emoplay-env.sh`）：

1. **改 pin**：`pubspec.yaml:52-62` 两包 ref 同步改为目标 commit（**必须同一
   commit**，fork 自述两包须同 checkout）；`flutter pub upgrade media_kit media_kit_video`
   刷新 lock。
2. **门禁**：build_runner → `flutter analyze`（0 error）→ `flutter test`
   全绿（底数只增不减）→ `flutter build linux --debug`。
3. **专项回归**（渲染/二进制变更必跑）：
   - ldd 审计（pr.yaml:104 同款）0 缺失；
   - `test/audio_probe_test.dart` 真出声；
   - `mpv_player_properties_test.dart` 全绿（fork 属性行为变化的哨兵，例如
     `803c4a27` 这类属性安全修复可能改变失败语义）；
   - [CROSS-PLATFORM-VERIFICATION-MATRIX.md](CROSS-PLATFORM-VERIFICATION-MATRIX.md)
     的 LX-2/LX-4/LX-5/LX-7 与对应平台渲染行按能力复跑（AI agent 可跑部分 +
     需用户部分，矩阵行回填）。
4. **登记**：pin 旧值→新值、动机、回归证据写入本文件 §六 + CHANGELOG 一行；
   红灯按 §六-3 归因，不绕过。

**回滚预案**：pin 是单 commit ref，回滚 = ref 改回 `83b7ca63` + lock 还原 +
门禁重跑；无本地补丁需要重放（EmoPlay 不维护 fork 内部分叉）。

## 五、上游 PR 策略

判定标准与动作（按差异清单主题）：

| 类别 | 例子（fork 实测提交） | 策略 |
| --- | --- | --- |
| 通用正确性修复（与构建体系无关） | `803c4a27` 不可用属性安全处理、`4cd7c295` android gles 修复、`3ec38cd3` pulse 掉帧 | **值得上游**：若上游仍活跃，按 fork 原提交整理 PR；EmoPlay 侧不动手改 fork 源码 |
| 渲染管线增强（Linux 双缓冲/D3D11/x11 硬解等） | `1e70872a`、`9c94fabd`、`df5a969e` | fork 已验证；是否上游由 Predidit 决定，EmoPlay 只跟踪不代提 |
| native assets 构建体系 | `a1b34d37` 全套 | 上游未走此路线前**不推**；EmoPlay 依赖面已锁死在 fork 行为上（pr.yaml ldd 审计 + Dart 3.10 工具链），换上游需重建整个打包链 |
| OHOS | §3.3 全部 | 不上游（上游无此平台诉求），留在 fork |
| EmoPlay 自身发现的问题 | 未来矩阵红灯定位到 fork 层的 | 流程：先在本地 checkout 写最小复现测试 → 提 issue 附复现 → 修复合入 fork 后按 §四流程带 pin 升级进 EmoPlay；**禁止在 EmoPlay 仓库用 pubspec override 打本地补丁长期共存** |

补充纪律：fork 的 `doc/native_assets.md` 明确「git 消费者必须把两包 pin 到同
一 immutable commit」，且声明此前发布版本不实现该协议，**禁止只升一个包**；
EmoPlay 的 Dependabot/手改依赖时按此校验（可作 M7 加一条守护测试：解析
pubspec.yaml 断言两包 ref 相等）。

## 六、已知限制与未做项（坏消息 + 登记表）

1. **fork-point 未知**：本环境 GitHub API/TLS 不可达（2026-11-11 实测
   ECONNRESET），§四-1 命令序列待首次联网执行；拿到 merge-base 后回填本节。
2. **fork Unreleased 面大**：native assets 体系尚未在 fork 侧发版（包版本停在
   1.1.11/1.2.5），意味着升级 pin 时风险面 = Unreleased 全部内容，回归流程
   不可裁剪。
3. **上游活跃度未知**：media-kit/media-kit 的最近提交时间/是否仍在维护，待
   季度对比首次执行时记录；若上游已停更，§五「可上游修复」降级为「只跟 fork」。
4. **§3.4 勘误**：Linux buffer 提交短哈希有一处笔误声明（见 §3.4 勘误说明），
   以 checkout `git log` 为准；下次更新本文件时直接修正正文。
5. **同步登记表**（每次季度对比/升级后追加一行）：

| 日期 | 动作 | fork pin | upstream 增量 | 结论/证据 |
| --- | --- | --- | --- | --- |
| 2026-11-11 | 建立（离线取证） | `83b7ca63` | 未测（网络不可达） | 本文 §三 |
