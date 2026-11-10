# 更新说明 · 2026-11-10（卫生与交付形态 R6）

> Linux 交付形态补上第三种：免安装的 AppImage（linuxdeploy 打包，amd64 在
> 本容器冒烟实测，FUSE 不可用的环境里 `--appimage-extract-and-run` 也能跑）。
> 仓库同轮清掉一批「看不见但一直在」的债：web 模板残留、三条 `any` 依赖、
> 零引用的 `screen_brightness_ohos`，正对应全面审计的 P2 卫生清单。界面按
> Kazumi 对齐空态按钮 / 徽章 / 许可证链接三处样式层细节，新增 3 条守护测试
> 防回退。35 文件 345 用例全绿。

| 项         | 值                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 版本       | git `b0e1a06`（2026-11-11 02:16 CST，R6: polish + readme）。本轮三个提交（`988122f` 01:45 / `e1a2df0` 01:56 / `b0e1a06` 02:16）落在 11-11 凌晨窗口，文档沿用 2026-11-10 夜间窗口命名（同 R1-R5 口径） |
| 平台       | Linux 容器内实测 analyze / 全量测试 / AppImage 产物与 runtime（详见 §一）；arm64 AppImage 打包仅 CI 可验（x86_64 容器无法跑 aarch64 打包）；Windows / macOS / Android 待 CI 与实体机验证 |
| 自动化测试 | **35 文件 / 345 通过 + 1 平台条件跳过，全绿**（上轮 34 文件 / 342 通过 + 1 跳过；+1 文件 / +3 用例 = `test/kazumi_alignment_ui_test.dart`）                     |
| 静态检查   | flutter analyze 通过（**0 告警**，`No issues found! (ran in 5.3s)`，2026-11-11 02:21 CST 文档收网窗口复测）                                                      |
| CI         | 本窗口不可测：`gh run list -R emoeem/emoplay` EOF（api.github.com 不可达，02:21 CST 实测）；`d446bb8` / `8ed84c4` / `1dc5d14` / `988122f` / `e1a2df0` / `b0e1a06` 六个提交未推送（origin/main 停在 `63d9f59`）。推送后预期签名 **345 passed / 1 skipped** |

## 一、Linux 第三种交付：AppImage（`e1a2df0`）

结论：release.yaml 的 Linux amd64 / arm64 两个 job 各多一步打包，产物
`EmoPlay_linux_<tag>_<arch>.AppImage` 与 deb、tar.gz 并列上传 GitHub
Release。打包器是 linuxdeploy（构建时自动下载，缓存在 `build/`，不进仓库）。

- 新脚本 `.github/scripts/package-appimage.sh`（121 行，本提交新增）：
  - AppDir 组装保留 Flutter bundle 原布局（`usr/bin/emoplay` + `lib/`，
    二进制 `$ORIGIN/lib` RPATH 不变），custom AppRun 再补一层
    `LD_LIBRARY_PATH` 导出（脚本头注释自述 belt and braces，同时是脚本的
    对外契约）；
  - FUSE-less 检测：无 `fusermount3` 或 `/dev/fuse` 时全程
    `--appimage-extract-and-run` + `APPIMAGE_EXTRACT_AND_RUN=1`，容器内
    既可打包也可运行；
  - linuxdeploy 只做 desktop/icon 校验与 packing，desktop 与 icon 用既有
    `assets/linux/com.emoplay.EmoPlay.desktop`、
    `assets/icon/emoplay_icon.png`；产物从 linuxdeploy 的
    `com.emoplay.EmoPlay.AppImage` 规范化为 `EmoPlay_linux_<tag>_<arch>`，
    与 tar.gz / deb 命名同轨。
- release.yaml（+16 行）：amd64 与 arm64 两个 "Package Linux AppImage" 步，
  upload-artifact 与 Release assets 两个 path 清单补 `*.AppImage`；
  `.gitignore` 补 `*.AppImage`（+1）。
- **系统库不内嵌是明说的选择**：GTK3、ALSA/pulse、VA-API/VDPAU 仍取自
  发行版，与 deb `Depends` 同款策略（脚本头注释明文）。理由：AppImage 的
  目标是免 root 免安装，不是零依赖；发行版本来就有 GTK/mpv 运行栈，内嵌
  只增体积不增可用性。这与 R3 的 deb 依赖审计（17 项 `Depends`）是同一个
  决策在两种交付形态上的落法。
- **实测**（文档收网窗口，2026-11-11 02:21 CST）：
  - 仓库根 `EmoPlay_linux_v2.0.0-alpha_amd64.AppImage` 存在，35,584,504
    字节（`ls -la`）；`file` 判 ELF 64-bit LSB pie executable,
    static-pie linked（即 AppImage 自带 runtime）；
  - `./EmoPlay_linux_v2.0.0-alpha_amd64.AppImage --appimage-help` 应答正常
    （exit 0）：runtime 在本容器可用；
  - `git check-ignore -v` 命中 `.gitignore:62 *.AppImage`：产物不入侵
    仓库（审计坑 6 关闭态的延伸）；
  - extract-and-run 完整冒烟由施工轮完成（脚本头注释与 CHANGELOG 记录）；
    本文档轮只做产物与 runtime 级复核，未再启动 GUI。

## 二、仓库卫生与依赖收敛（`988122f`）：审计 P2 卫生批次清账

结论：全面审计（[AUDIT_FULL_2026-11-10.md](../audits/AUDIT_FULL_2026-11-10.md)）
§九第 3 条点名的「P2 卫生（小改可批量）」三项在本提交一次清完。这类债不炸
构建、不炸测试，所以容易被一直往后排：`any` 约束让 lockfile 失守，死排除
与模板残留则让「仓库里到底有什么」变模糊。

| 审计项 | 处置 | 证据 |
| --- | --- | --- |
| P2「pubspec 三处 `any` 约束」 | 钉版本：synchronized `^3.6.1+1`、material_color_utilities `^0.13.0`、path `^1.9.1` | `git show 988122f -- pubspec.yaml`（3 插入 / 4 删除） |
| P2「web/ 模板目录被跟踪 + bbcode 死排除」 | 整体删 `web/`（index.html 59 行 + manifest.json 35 行 + favicon 与 4 张 icon）；`.metadata` 去 web 平台登记（-3 行）；`analysis_options.yaml` 删 `lib/bbcode/generated/**` 与 `web/**` 两条指向已不存在路径的死排除（-2 行） | `git show --numstat 988122f`；本轮 `ls web/` 实测 No such file or directory |
| P2「`screen_brightness_ohos` 依赖必要性存疑」 | 移除依赖声明与 lockfile 条目（pubspec.yaml 1 行、lock 8 行） | `git show 988122f -- pubspec.yaml pubspec.lock`；本轮 grep pubspec 实测只剩 android / ios / platform_interface 三件 |

两点说明：

- `connectivity_plus` 是同一审计项的后半句（「评估本地播放器是否需要计费
  网络检测」），本轮**未动**：lib/ 仍有真实使用
  （`lib/services/network/metered_network_service.dart:3`），去留是产品
  决策而非卫生问题，继续挂账。
- 为什么把 `any` 收成 `^` 而不是只留 lockfile：lockfile 只复现「当前」的
  解析结果，`any` 会让任何一次 `pub upgrade`（或新环境缓存失效后的重解析）
  悄悄换版本；`^` 把漂移面收进同主版本，lockfile 依旧负责精确钉死。

## 三、界面对齐 Kazumi（仅样式层）与守护测试（`b0e1a06`）

结论：三处样式层细节回归 Kazumi idiom，行为与回调一律不动；配 3 条
headless 挂真实页面的守护测试（`test/kazumi_alignment_ui_test.dart`，
171 行），防止后续施工把对齐磨掉。

- **关于页「GPL-3.0 许可证」tile 改指本项目 LICENSE**
  （`lib/pages/about/about_page.dart:42`，4 插入 / 1 删除）：导入时的 URL
  误指向 Kazumi 仓库 LICENSE；Kazumi 同槽位本就链自家仓库，Kazumi 的许可
  归属另由「上游声明（NOTICE）」槽位承担（about_page.dart 同页注释）。
  守护用例 `aboutLicenseTileOpensEmoPlayLicense` 用记录型
  `UrlLauncherPlatform` 假体捕获真实启动 URL 做断言（测试文件
  `:59`-`:79`）。
- **空态按钮换 `StateActionButton(.tonal)`**（64×48 药丸，Kazumi 空态
  idiom）：首页「选择媒体文件」（`home_page.dart:251`）、播放页
  「打开文件/文件夹/URL/媒体库」（`player_page.dart:396`-`:414`）、媒体库
  三个空态动作（`library_page.dart:394`-`:411`）。裸 `FilledButton` 观感
  偏小；`StateActionButton` 是早前已平移件
  （`lib/bean/widget/state_presentation.dart:48`-`:57`），此前只在错误页
  使用。守护用例锁 style `minimumSize` = `Size(64, 48)` + padding
  （测试文件 `:116`-`:128`）。
- **插件页徽章与次要文案主题化**（41 插入 / 9 删除）：「已定制」徽章原是
  硬编码深棕底 `Color(0xFF5a3d1e)` + 继承前景，亮暗两主题下都读不清，改
  `errorContainer/onErrorContainer` 容器对（`plugins_page.dart:457`）；
  模式徽章补 `onSecondary/onTertiaryContainer` 前景；三处
  `TextStyle(fontSize: 12)` 裸样式改 `bodySmall + onSurfaceVariant`
  弱化（Kazumi 次要文案 idiom）。
- **新增 dev_dependency**：`url_launcher_platform_interface ^2.3.2`
  （`pubspec.yaml:69`）作启动捕获测试缝，仅测试用。

## 四、README 对账（`b0e1a06`）

结论：README 中英两份正文与实际对齐（37 插入 / 13 删除），对的是四件事：

1. **发布产物表补 AppImage 行**（中英），Linux 安装建议改「deb / AppImage
   / tar.gz 三种任选」，注明系统库策略与 FUSE-less 运行方式；
2. **构建依赖补 `libasound2-dev`**：R4 发布演练已实测「缺 ALSA 头时冷缓存
   源码构建失败」（run 42720144705），README 的 Linux 构建要求此前漏了这
   一条，现与 pr.yaml 的 "Install native build tools" 步一致；
3. **设置中心行补「关于（含应用内更新检查）」**：R1 上线的 UpdateChecker
   一直没反映进功能清单；
4. **新增「截图」占位说明（中英）**：明文写「本轮在无显示器的构建环境内
   收尾，不产占位假图」，五页签与播放面板实拍图待桌面空闲窗口补。

## 五、已知取舍

- **arm64 AppImage 仅 CI 可验**：linuxdeploy 官方 aarch64 AppImage 的 URL
  可达性已实测并记录在 release.yaml 注释（2026-11-11），但 x86_64 构建容器
  无法真跑 aarch64 打包；推送后以 CI 的 flutter-build-linux-arm64 job
  结论为准。
- **CI 本窗口不可测**：api.github.com 不可达（02:21 CST EOF 实测），六个
  提交未推送。「推送后预期 345 passed / 1 skipped」是推算值（本地全绿 +
  R3/R4 两轮「预期签名 = 实测签名」的先例），不是已实测结论。
- **AppImage 观感未做人手点验**：本文档轮只核产物与 runtime；启动观感与
  桌面环境里的 desktop/icon 集成表现未验，与既有「GUI 手感人工验收 ☐」
  合并挂账。
- **测试文件头注释与 CI 现状有一处不符**：`test/kazumi_alignment_ui_test.dart`
  头注释称插件页徽章的容器对「由 CI 的 hardcoded-color grep 静态把关」，
  本轮实测 `.github/` 两个 workflow 均无该 grep 步骤（详见对应工作报告
  §5）；本轮文档轮不改代码，挂账待下轮补 grep 步骤或修注释。
- 与既有已知限制一致、本轮无变化：产物未签名 / 实体机验证 ☐ / prerelease
  语义 ☐ / i18n 已迁页签壳与音频设置两页 / connectivity_plus 去留待评估。
