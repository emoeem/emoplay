# 更新说明 · 2026-11-10（红灯清零 R3）

> CI 第二次红灯的根因被剥到了头：R2 补的 VA/VDPAU 只是依赖洋葱的第一层，
> run 42712702494 又挂在 `libpulse.so.0`——本轮把 media_kit 捆绑 `libmpv.so.2`
> 的直系依赖用 `readelf -d` 实测清点后一次装全，并在 CI 里加了一道
> `ldd` 审计步，从此缺依赖一次列全、不再逐轮烧 CI 分钟数。同轮把 Linux deb
> 的 `Depends` 从 2 项补到 17 项并经 apt 递归闭包审计验证（装完即能起，
> 不靠 tray 包的侧链捎带 GTK）；页签壳成为第一个接入 i18n 的页面；媒体库
> 三条响应性行为（取消延迟 / 进度节流 / 缩略图串行）被 3 条新用例锁定。
> 全仓 32 个测试文件 332 条用例通过（另有 1 条 Windows 专属探测按 QSKIP
> 契约跳过），`flutter analyze` 0 告警，debug / release 构建与 deb 打包
> 实测通过。**CI 首绿仍未确认**——修复提交待推送，推送后按验收标准 5 确认。

| 项         | 值                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------- |
| 版本       | git `c943414`（07:00 CST，R3: remaining debts；2.0.0-alpha+2000000，未发布）              |
| 平台       | Linux（容器内实测：analyze / test / debug+release build / deb 打包）；Windows/macOS/Android 待 CI 与实体机验证 |
| 自动化测试 | **32 文件 / 332 通过 + 1 平台条件跳过，全绿**（上轮 30 文件 / 326 通过 + 1 跳过，+2 文件 / +6 用例） |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 2.3s)`）                      |
| CI         | **run 42712702494 failure**（2m53s：analyze ✓，test 324 通过 / 2 失败 / 1 跳过）——根因与修复见二-1；修复提交 `7debc83` 待推送，首绿待推送后确认 |

## 一、面向用户的变化

### 1.1 Linux deb 安装包首次具备独立安装能力（Depends 2 项 → 17 项）

此前 deb 的 `Depends` 只有 tray 相关两个包（`libayatana-appindicator3-1` +
`gir1.2-ayatanaappindicator3-0.1`），GTK 运行库是靠 tray 包自己的依赖链**顺带**
装上的——用户在最小化系统上装完 deb 可能直接起不来。本轮（`7052260`）把
`libgtk-3-0t64` 与音频输出、硬解、GL 视频输出所需的 14 个运行库全部显式钉进
`Depends`（逐包依据见 `.github/scripts/package-linux.sh` 头部注释），并用两道审计背书：

- **覆盖审计**：release bundle 的 ldd 闭包解析出 125 个唯一库路径（除捆绑
  自带 12 个外为 113 个外部库），由 104 个 dpkg 包提供；`apt-cache depends
  --recurse --important` 实测这 17 个包的递归闭包为 251 个包，**104 ⊂ 251，
  差集为空**（本轮在 Ubuntu 26.04 容器内复测通过）。
- **捆绑即自带**：`libmpv.so.2` / `libmedia_kit_event_loop.so` /
  `libflutter_linux_gtk.so` 及插件 .so 全部打进包内，不设依赖。

本轮实测：`dpkg-deb --build` 产出 deb 17,045,202 字节（Installed-Size
50820 KB）+ tarball 20,743,844 字节；打包脚本已由 release.yaml 在 `v*` tag
时对 amd64/arm64 自动调用。用户感知：**装完就能放视频，硬解（VA-API/VDPAU）
与音频输出（PulseAudio/ALSA）的运行库不再缺位**。

### 1.2 页签壳接入 i18n（第一个迁移页面，zh 显示零变化）

`menu.dart`（页签壳）成为第一个从 arb 取字符串的页面（`c943414`）：五个页签
标签经新的 `menuTabLabels(AppLocalizations)` 单一来源分发——竖屏
NavigationBar 与横屏 NavigationRail 共用同一列表，两套壳的文案从此不可能
各改各的（1.x 在 qml/Main.qml 里也是同一 tab 模型）；「再按一次退出应用」
toast 同步换成 `l10n.doubleBackToExit`。默认语言仍是 zh-Hans-CN，**中文用户
看到的界面一个字都没变**；en arb 补齐同键（结构不再是空壳）。迁移链
（arb 键 → gen-l10n 生成类 → 页面取用，zh+en 两语言）由
`test/menu_l10n_test.dart` 3 条用例端到端锁定。

### 1.3 媒体库响应性行为被测试锁定（3 用例，对齐 1.x 形状）

`test/performance_guards_test.dart`（239 行）锁定三条用户可感知的响应性
不变量，全部对着真实文件系统跑：

- **取消扫描立即生效**：扫描进行中点取消，部分结果保留、毫秒级停下
  （实测断言 <5 秒上限，实际约几十毫秒），且取消后库照常可用；
- **大库进度不刷屏**：进度回调按节流步长（约每 32 个文件一次）触发，
  绝不逐文件轰炸 UI——大库扫描时界面不会因为进度事件而卡顿；
- **缩略图串行生成**：任意时刻至多一个 ffmpeg 子进程在跑（flock 标记
  实证），与 1.x「一次一条进程链」的形状一致——后台缩略图不会吃满机器。

不采 isolate 分片多开扫描：1.x 用单 worker 线程，协作式逐文件让出已把取消
延迟压到毫秒级，第二个 isolate 会破坏进度顺序而没有实测收益——测试文件头
注释记录了这个决策依据。

## 二、修复与根因

### 2.1 CI 第二次红灯：runner 缺 libpulse，dlopen 洋葱只报第一层

现象：run 42712702494（2m53s，由 R2 push 触发，标题仍是文档提交
`4d3eae5`——老坑，别按 run 标题判触发者）在 Run tests 步报
`324 tests passed, 2 failed, 1 skipped`，失败用例仍是那两条真开 libmpv
的均衡器用例（`equalizer_test.dart`），报错变为
`libpulse.so.0: cannot open shared object file`。

根因：**dlopen 每次只报第一个缺失依赖**。R2 `3379d7a` 补的 VA/VDPAU 只是
media_kit 捆绑 `libmpv.so.2` 直系依赖里的第一层；装上后 dlopen 往下走一层，
撞到第二层的 libpulse。逐个补齐要多烧好几轮 CI。修复（`7debc83`）分两步：

1. **一次装全**：`readelf -d` 实测捆绑 `libmpv.so.2` 的全部直系 NEEDED
   （本轮容器内复测：34 个 soname，含 libva*/libvdpau/libpulse/libxv/
   libegl/libgbm/libdrm/libunwind/liblcms2/libarchive/libasound/libXv/
   libXss 等），映射到 14 个新 apt 包一次装进 pr.yaml 与 release.yaml
   （`libpulse0 libxv1 libegl1 libgbm1 libdrm2 libunwind8 liblcms2-2
   libarchive13t64 libasound2t64 libdbus-1-3 libsndfile1 libmpg123-0t64
   libopus0 libogg0`）；第二层编解码库（libFLAC/libvorbis/libmp3lame 等）
   不按 soname 钉死——它们由 libpulse0/libsndfile1 的发行版依赖图带进来，
   且 `libflac12t64` 这类名字随发行版变，钉了反而脆。
2. **审计防线**：pr.yaml 步序改为 装依赖 → **构建** → **`ldd
   build/native_assets/linux/libmpv.so.2 | grep 'not found' && exit 1`**
   → 测试。审计步在测试之前一次性列出全部缺失（任一 not found 即红灯并
   给全清单），这是最后一轮补丁——以后依赖缺口在构建后立刻暴露全貌，
   不会再出现「每次红灯剥一层洋葱」。

顺带排掉一个命名陷阱：`ubuntu-latest` 是 noble（24.04），`libarchive13` /
`libasound2` / `libmpg123-0` 这三个名字**不存在**，必须用 t64 后缀名
（workflow 注释已记录）。本地容器同款 `ldd` 审计本轮实测通过（0 个
not found）。

### 2.2 deb Depends 的系统性缺口（同根因，另一处表现）

与 2.1 同源：`.github/scripts/package-linux.sh` 自 M8（`6247f2e`）建立时
只钉了 tray 两个包，假设「GTK 会被 tray 带上」。这条侧链恰好存在，所以
此前没炸，但它是隐式契约——tray 包一旦换掉，应用就起不来。`7052260`
按 1.1 的审计方法把直系依赖显式化；审计依据写在脚本注释里（control 二进制
字段不认 `#` 注释行，理由只能住在脚本里）。

## 三、已知取舍

- **CI 首绿仍未确认**：R3 三个提交（`7debc83` / `7052260` / `c943414`）
  与本轮文档在本说明写就时尚未推送；推送后预期 CI 签名为
  **332 passed / 0 failed / 1 skipped**（本地 332+1 与 CI 历史口径
  自洽：R2 本地 326 = CI 324 通过 + 2 失败）。若仍红灯，ldd 审计步会
  一次性给出完整缺失清单。
- **打包注释里的「115-library ldd closure」口径未复现**：本轮对同一
  bundle 用四种口径实测（全闭包 250 / 仅 lib/ 234 / 主二进制 166 /
  直系并集 64 唯一 soname），无一等于 115，最接近的外部解析路径口径为
  113。核心声明（闭包 ⊂ Depends 递归闭包，差集空）已独立复现成立，
  但 115 这个数字本身按规范标注为**未复现，待施工方确认口径**。
- **打包验证仅 amd64**：arm64 deb 由 CI 矩阵按同脚本产出（脚本参数化
  arch），本轮容器内未实测 arm64；AppImage 与签名仍未做。
- **i18n 只有页签壳一页**：其余页面字符串迁移仍在路线图 ☐（R3 只证明
  生成链在真实页面可用）。
- **性能轮只交了测试可锁的部分**：吞吐墙钟数字与首帧时间需实机
  （SPEC §9 GUI 验收轮），不在自动化守卫范围。
- **Windows / macOS / Android 产物仍未实体机验证**，Android APK 仍未签名，
  iOS 仍在发布矩阵外——与既有已知限制一致，本轮未变化。
