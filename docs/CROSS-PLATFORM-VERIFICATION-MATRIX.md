# EmoPlay 3.0 跨平台验证矩阵（Linux / Windows / macOS / Android 实测清单）

| 项       | 值 |
| -------- | --- |
| 状态     | 生效中（验证未开始执行；每行完成回填 ✅+日期+证据链接） |
| 日期     | 2026-11-11（建立） |
| 适用版本 | git `bdad604`（2.0.0-alpha+2000000） |
| 相关     | [EMOPLAY-3.0-ROADMAP.md](EMOPLAY-3.0-ROADMAP.md)（M7-T4/M8 各任务引用本矩阵）、[FORK-GOVERNANCE.md](FORK-GOVERNANCE.md)（矩阵内 libmpv 行为异常时按其 §四回溯）、[SPEC.md](SPEC.md) §9（冒烟口径）、[guides/BUILD_GUIDE.md](guides/BUILD_GUIDE.md)（产物获取） |

## 一、结论先行

本矩阵把 2.0 期「发布产物实体机验证」「GUI 手感人工验收」两张欠账（UPGRADE_ROADMAP_2026-11-10 §4.1、AUDIT_FULL §一末行）落成**逐行可执行的清单**：每行给出测试步骤、预期、所需环境、负责人。约定：

- **负责人 = AI agent**：容器/CI 内可自主执行（构建、门禁、日志取证、无头冒烟）。
- **负责人 = 需用户**：需要实体硬件、显示器/音频输出、GPU 驱动控制面板、应用商店/证书的操作。AI agent 只准备步骤与取证脚本，不执行。
- **取证**：每行完成后在「证据」处留命令输出摘要或截图路径；截图统一存 `docs/` 外的本地目录（不进 git，DOC-STANDARD §六隐私条款）；日志页导出（路线图 M7-T1 交付后）优先用应用内导出。
- **顺序**：Linux 行先走（容器可自测的最多），Windows/macOS/Android 由 CI 产物 + 需用户实机接力。**任何一行红灯 → 先查 [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md) §四回归清单，再怀疑应用代码**。

当前已验底数（本文建立时实测，勿重复跑）：CI main 门禁绿（analyze 0 告警 / 37 文件 355+1 全绿，2026-11-11 实测 `flutter analyze`、`flutter test`）；真 libmpv 音频探针已出声（`test/audio_probe_test.dart`，pinned ao=pulse，输出 `AO: [pulse] 44100Hz stereo 2ch float`）；ldd 审计 0 缺失（R4/R5 实测口径）；deb/AppImage 打包产物本机可跑（R3/R6 实测）。**以下矩阵全部行均为未执行状态**。

## 二、Linux（NVIDIA / Wayland / 硬解 / HDR / Shader）

发布产物：deb（amd64/arm64）、tar.gz、AppImage（amd64 本机实测过，arm64 仅 CI 可验，R6）。

| ID | 验证项 | 测试步骤 | 预期 | 所需环境 | 负责人 |
| --- | --- | --- | --- | --- | --- |
| LX-1 | 纯净系统「装完即起」 | 最小化 Debian/Ubuntu 容器/虚机直装 `*.deb` → 命令行启动 → 观察 stderr 20s | 进程存活、无 error 级输出、窗口出现（SPEC §9 冒烟口径） | 最小化 Debian/Ubuntu（无预装媒体库） | AI agent（容器可跑；图形输出按 SPEC §9 以进程+日志判定，标注「显示待人工验收」） |
| LX-2 | ldd 闭包复测 | `flutter build linux --release` 后 `ldd build/native_assets/linux/libmpv.so.2 | grep -c 'not found'`，并跑 pr.yaml 同款审计步全量清单 | `0`；deb Depends 与闭包一致 | 容器 + source /opt/emoplay-env.sh | AI agent |
| LX-3 | Wayland 原生渲染 | Wayland 会话（niri/GNOME-Wayland）启动，播本地 mp4，`grim` 截图 | 画面正确、无 X11 回退警告、窗口标题 EmoPlay | Wayland 桌面 | 需用户（桌面空闲窗口；工具链先例 audit §八：grim + wlrctl） |
| LX-4 | NVIDIA 专有驱动硬解 | 设置→视频与画质选 hwdec（nvdec/vaapi 对应驱动），播放 H.264/HEVC 10bit 各一，读 mpv 日志 `hwdec-current` | `hwdec-current=nvdec`（或 vaapi）；GPU 占用上升、CPU 占用显著低于软解 | NVIDIA GPU 实机 + 专有驱动 | 需用户 |
| LX-5 | AMD/Intel VAAPI 硬解 | 同 LX-4，hwdec=vaapi，播放 4K HEVC | `hwdec-current=vaapi`；无零拷贝崩溃（fork a9467290 修过 vaapi zero copy，回归点） | AMD/Intel GPU 实机 | 需用户 |
| LX-6 | HDR tone-mapping | 播放 HDR10 片源，toneMappingMode 逐档切换（auto/clip/mobius/bt.2390 等，SPEC §7 枚举） | 画面无洗白/色带爆炸；libplacebo 日志出现 tone-mapping 行 | HDR 显示器 + 支持 HDR 的 GPU | 需用户 |
| LX-7 | Anime4K 着色器链 | 设置→着色器管理，选 high 档（CNN VL 序列，`assets/shaders/` 9 个 GLSL 在包内），播放 1080p 动画 | 明显锐化；掉帧率 <2/s（超限自动降档，不变量 8）；无 GLSL 编译报错 | 容器无 GPU 可验证「加载与降档逻辑」，画质需实机 | AI agent（逻辑）+ 需用户（画质） |
| LX-8 | ICC 色彩管理 | 系统装 ICC profile → 设置启用 ICC → 播放 SDR 片 | 无崩溃；profile 不可读时自动持久化 off + 恢复启动快照（不变量 8） | 带 ICC profile 的桌面 | 需用户 |
| LX-9 | 音频输出 | 播放 5.1 声道片源，pulse/pipewire 下切换 ao | 声道正确；`audio_probe_test.dart` 先例口径（pinned ao=pulse 可达宿主 pipewire-pulse） | 音频输出设备 | AI agent（探针测试）+ 需用户（5.1 实听） |
| LX-10 | 分数缩放/多屏 | 125%/150% 缩放 + 双屏不同 DPI 拖窗 | UI 不糊、控制条不错位 | 多屏环境 | 需用户 |
| LX-11 | AppImage 启动 | `./EmoPlay_linux_v3.0.0_amd64.AppImage --appimage-help` exit 0 后运行 | 进程存活、功能同 deb（R6 已验 amd64 链路，3.0 产物复核一遍） | 任意 Linux | AI agent |
| LX-12 | 拖拽打开 | 从文件管理器拖 mp4 进窗口（desktop_drop） | 进播放且入库 | 桌面 | 需用户（E2E 指针注入受限，audit §八） |

## 三、Windows（D3D11 / 硬解 / HDR / 显卡切换）

发布产物：Windows zip（CI `release.yaml` "Release for Windows" job，.github/workflows/release.yaml:115）；msix 配置在 `pubspec.yaml:98-102`（`sign_msix: false`，签名是 M8-T3 决策项）。

| ID | 验证项 | 测试步骤 | 预期 | 所需环境 | 负责人 |
| --- | --- | --- | --- | --- | --- |
| WIN-1 | CI 产物可解压可启动 | 下载 zip → 解压 → 运行 EmoPlay.exe → 20s 观察日志 | 进程存活、窗口出现、无缺 DLL 弹窗 | Windows 10/11 x64 | 需用户（CI runner 只能构建不能跑 GUI） |
| WIN-2 | D3D11 渲染路径 | 播放 H.264/HEVC/VP9/AV1 各一；`vo=gpu` 下查 mpv 日志渲染上下文 | 无黑屏/花屏；日志出现 d3d11 上下文；窗口缩放无残影 | Windows 实机 | 需用户 |
| WIN-3 | 硬解 d3d11va | hwdec=auto 播 4K HEVC 10bit | `hwdec-current=d3d11va`；帧率满 | 带 GPU 的 Windows 实机 | 需用户 |
| WIN-4 | HDR 直通/tone-mapping | Windows HDR 开启 → 播 HDR10 片源 | 画面正确（直通或 tone-map 一致）；关闭 HDR 后 SDR 正常 | HDR 显示器 + Windows HDR | 需用户 |
| WIN-5 | 双显卡切换（混合本） | 集显/独显分别设为首选 → 播放 → 任务管理器查 GPU | 两模式都能渲染；切换后首播无崩溃 | 双 GPU 笔记本 | 需用户 |
| WIN-6 | 窗口控制/标题栏 | 最大化/贴边/多虚拟桌面切换 | 原生标题栏行为正常（`embedded_native_control_area.dart` 路径） | Windows 实机 | 需用户 |
| WIN-7 | `emoplay://` 唤起与转发 | 已运行实例 → 双击注册协议的 `emoplay://` 链接 | 第二实例唤起已有（R4 `bd36f70`）；**URL 内容转发是 M8-T3 待做项，做完前预期 = 只唤起不转发** | Windows 实机 | 需用户（M8-T3 完成后重跑本行） |
| WIN-8 | msix 签名决策落地 | 按 M8-T3 决策（签或不签）验证安装路径 | 与决策一致；不签则记录 msix 不发布 | Windows + 证书（若签） | 需用户 |
| WIN-9 | Windows ARM64 | arm64 zip 在 Snapdragon 设备解压运行 | libmpv 有 win-arm64 包（fork `11d02cb8`），应用可启动；播放失败则记「arm64 实验态」 | ARM64 Windows 设备 | 需用户 |

## 四、macOS（VideoToolbox / Metal / 色彩管理）

发布产物：macOS zip（release.yaml "Release for macOS" job，.github/workflows/release.yaml:160）；libmpv 来自 Predidit/libmpv-darwin-build 0.6.8 XCFrameworks（fork `media_kit/hook/native_bundles.json` macos_arm64 条目实测）。签名/公证未配置（M8-T5 决策项）。

| ID | 验证项 | 测试步骤 | 预期 | 所需环境 | 负责人 |
| --- | --- | --- | --- | --- | --- |
| MAC-1 | 未签名产物可启动 | 下载 zip → 解压 → 右键打开绕 Gatekeeper → 20s 观察 | App 启动、窗口出现；确认弹窗次数记录 | macOS 实机（Apple Silicon 优先） | 需用户 |
| MAC-2 | VideoToolbox 硬解 | hwdec=videotoolbox 播 4K HEVC | `hwdec-current=videotoolbox`；无花屏 | macOS 实机 | 需用户 |
| MAC-3 | Metal 渲染 | 播放并截图对比；切全屏/空格预览 | 无黑屏；Retina 下不糊（backing scale 正确） | macOS 实机 | 需用户 |
| MAC-4 | 色彩管理（Display P3） | 系统色彩描述文件生效下播广色域片源 | 颜色无过饱和漂移；ICC 关闭时一致 | macOS + P3 显示器 | 需用户 |
| MAC-5 | 通用二进制 | `lipo -info` 检查产物含 arm64+x86_64；Intel 机器跑 zip | 双架构齐；Intel 可启动 | 两类实机或 CI 产物检查 + Intel 机 | AI agent（lipo）+ 需用户（Intel 机） |
| MAC-6 | 公证决策落地 | 按 M8-T5 决策：公证后下载打开无 Gatekeeper 拦截，或不公证并记录用户步骤 | 与决策一致 | Apple 开发者账号（若公证） | 需用户 |

## 五、Android（MediaCodec / 横竖屏 / PiP / 后台音频）

发布产物：3 个 APK（arm64/armeabi/x86_64，release.yaml "Release for Android" job，:77；当前**未签名**，M8-T2 接密钥）；libmpv 来自 libmpv-android-video-build v1.3.1（fork `83b7ca63`）。代码落点：横竖屏全屏 `lib/services/platform/display_mode_service.dart` + `player_item.dart` `_syncOrientationFullscreen`（R5 已实现）；PiP `lib/services/player/pip_utils.dart`；后台音频 audio_service 绑定（player_item audio cluster；manifest 有 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`，android/app/src/main/AndroidManifest.xml:74）；手机自动扫描 `lib/services/platform/mobile_media_scanner.dart` + `DownloadDirectoryHandler.kt`。

| ID | 验证项 | 测试步骤 | 预期 | 所需环境 | 负责人 |
| --- | --- | --- | --- | --- | --- |
| AN-1 | APK 安装启动 | 安装 APK（先 adb 装，后用户侧装）→ 启动 → 空态出现 | 可安装（未签名 APK 需允许未知来源）；无即时崩溃 | Android 8+ 实机/模拟器 | AI agent（模拟器可装）+ 需用户（真机） |
| AN-2 | MediaCodec 硬解 | 播 4K HEVC/H.264，`hwdec-current` 读数 | `mediacodec`（auto 档）；低端机 SurfaceTexture 回退路径可用（fork `87cdfef7` 选项） | Android 实机 | 需用户 |
| AN-3 | 横竖屏自动全屏 | 竖屏播视频 → 旋转横屏 | 自动进全屏、返回竖屏退出全屏、锁定按钮跳过旋转（R5 语义） | Android 实机（有重力感应） | 需用户 |
| AN-4 | PiP | 播放中按 Home 触发 PiP（`pip_utils.dart`） | 小窗继续播、退 PiP 恢复；锁定态不进 PiP | Android 8+ 实机 | 需用户 |
| AN-5 | 后台音频 | 音乐形态 → Home 键 → 通知栏控制 | 后台继续播、通知栏播放/下一首可用（audio_service + MEDIA_BUTTON，AndroidManifest.xml:64,74） | Android 实机 | 需用户 |
| AN-6 | 存储访问与自动扫描 | 授予存储权限 → 媒体库自动扫描 | Download 目录内容入库；拒绝权限时空态 CTA 引导（`hasStorageAccess` 路径） | Android 实机 | 需用户 |
| AN-7 | 签名产物 | M8-T2 后 `apksigner verify` + 安装升级覆盖装 | 验证通过；可覆盖升级不丢数据 | 密钥（用户提供）+ 实机 | AI agent（apksigner）+ 需用户（覆盖装） |
| AN-8 | 免 Google 服务环境 | 无 GMS 设备（如国产 ROM）全功能走查 | 更新检查/播放/扫描均可用（更新检查走 GitHub API，需网络） | 无 GMS 实机 | 需用户 |

## 六、执行与回填约定

1. **每行一个证据单元**：命令 + 关键输出（或截图路径）；回填格式 `✅ YYYY-MM-DD 证据`；红灯记 `❌` + 归因链接（报告或 issue）。回填直接改本文表格，收网时 DOC-STANDARD 全套台账照出。
2. **AI agent 可执行的行**（LX-1/LX-2/LX-7 逻辑面/LX-9 探针/LX-11/AN-1 模拟器部分/AN-7 apksigner）由路线图 M7-T4/M8 对应任务在桌面空闲窗口执行；**需用户行**在每阶段收尾报告「需要人工操作的」小节集中列出（DOC-STANDARD §4.2-6）。
3. **红灯归因顺序**：先核对 [FORK-GOVERNANCE.md](FORK-GOVERNANCE.md) 差异清单与回归流程（libmpv 二进制/渲染相关），再查应用层；fork 侧问题按其 §四记录，不在应用仓库绕过。
4. 与 2.0 遗留的关系：本矩阵覆盖并细化 UPGRADE_ROADMAP_2026-11-10 §4.1 的「发布产物实体机验证」「GUI 手感人工验收」；2.0 侧口径（SPEC §9 冒烟）不变，行结果直接回填到旧路线图对应 ☐ 项。
