# 工作报告 · 2026-11-10（红灯清零 R3）

| 项           | 值                                                                                      |
| ------------ | --------------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-10（写作时 07:07 CST）                                                          |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写，仓库 `emoeem/emoplay`）                        |
| 版本         | git `c943414`（HEAD，R3: remaining debts；origin/main 停在 `4d3eae5`，R3 三个提交待推送） |
| 对应更新记录 | [`releases/RELEASE_2026-11-10_RED_LIGHT_ZEROING.md`](../releases/RELEASE_2026-11-10_RED_LIGHT_ZEROING.md) |

## 1. 本轮范围

OVERNIGHT-LOOP §二轮次结构的 R3 轮（开工检查 → 缺口分析 → 施工 → 文档）。
开工检查实测 R2 推送产出的 CI 第二跑（run 42712702494）仍为红灯，施工按
R2 报告 §6 下一步建议与 OVERNIGHT-LOOP §四积压取项：

1. **CI 红灯第二层定位与修复**（建议 1 续）：`7debc83`——runner 缺
   `libpulse.so.0`（dlopen 只报第一层的洋葱结构），readelf 实测直系
   NEEDED 全集后一次装全 14 个新包，pr.yaml 步序改为 构建 → ldd 审计 →
   测试（release.yaml 同步装包）。
2. **deb 打包依赖审计**（建议 2 / 积压 5）：`7052260`——deb `Depends`
   2 项 → 17 项，apt 递归闭包覆盖审计，容器内实测打包产物。
3. **剩余欠账**（积压 7 / 8 的可测切片）：`c943414`——页签壳 i18n 第一页
   迁移（`menu.dart` + `menu_l10n_test.dart` 3 用例）+ 媒体库响应性守卫
   （`performance_guards_test.dart` 3 用例）。
4. **文档收网**（本轮）：按 DOC-STANDARD 出发布说明 / 工作报告、更新
   HANDOVER 与路线图滞后数字、CHANGELOG 补 R3 条目、docs 索引登记。
   全部数字本轮实测，未跑或未能复现的如实标注。

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 红灯 | CI 第二跑 failure：runner 缺 `libpulse.so.0`，`equalizer_test.dart` 两条真开 libmpv 的用例挂掉（`##[error]324 tests passed, 2 failed, 1 skipped.`） | ✅ 已修（`7debc83`，待推送验证首绿） | `gh run view 42712702494 -R emoeem/emoplay --log-failed`：报错原文 `Failed to load dynamic library '.../libmpv.so.2': ... libpulse.so.0: cannot open shared object file`；`git show 7debc83`：pr.yaml 补装 14 包 + 步序改 构建→ldd 审计→测试，release.yaml 同步装包 |
| 缺口 | deb `Depends` 仅 tray 2 项，GTK 靠 tray 侧链隐式捎带，最小系统装完可能起不来 | ✅ 已修（`7052260`） | `dpkg-deb -f <deb> Depends` 实测 **17 项**；审计复测：bundle 闭包 125 唯一解析路径（外部 113）由 **104 个 dpkg 包**提供，17 包的 `apt-cache depends --recurse --important` 闭包 **251 包，comm -23 差集为空** |
| 缺口 | i18n 只有骨架，零页面接入（积压 8 续） | ✅ 第一页已迁（`c943414`） | `lib/pages/menu/menu.dart` 新增 `menuTabLabels()`（NavigationBar/NavigationRail 共用单一来源）+ `doubleBackToExit` toast 取用；`test/menu_l10n_test.dart` 3 用例锁 arb→gen→取用链（zh+en） |
| 缺口 | 媒体库响应性（取消延迟 / 进度节流 / 缩略图串行）无自动化守卫（积压 7 可测切片） | ✅ 已补（`c943414`） | `test/performance_guards_test.dart`（239 行）3 用例在全量套件内绿：cancel 延迟实测断言 <5s 且部分结果保留、进度按节流步触发、flock 实证至多一个 ffmpeg 子进程 |
| 记录澄清 | 打包脚本注释「115-library ldd closure」数字口径 | ⚠️ 本轮未能复现，已标注 | 同一 bundle 四种口径实测：全闭包 250 / 仅 lib/ 234 / 主二进制 166 / 直系并集 64（最接近的外部解析路径口径 113）——核心覆盖声明独立复现成立，115 本身按规范标「未复现，待施工方确认口径」 |

## 3. 工程状态（实测）

以下命令本轮在容器内实际执行（先 `source /opt/emoplay-env.sh`）：

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `flutter analyze` | **No issues found! (ran in 2.3s)**——0 error / 0 warning / 0 info |
| 自动化测试 | `flutter test`（全量） | **+332 ~1: All tests passed!**：32 文件（`ls test/*_test.dart \| wc -l`）/ 332 通过 + 1 平台条件跳过（Windows-only 探测） |
| 用例增量对账 | 332 − 326 = 6 = 3（menu_l10n：2 testWidgets + 1 test）+ 3（performance_guards） | 计数自洽 ✓（`grep -n "test(\|testWidgets(" 两文件实测 6 条声明） |
| Linux 构建（debug） | `flutter build linux --debug` | **✓ Built build/linux/x64/debug/bundle/emoplay** |
| Linux 构建（release） | `flutter build linux --release` | **✓ Built build/linux/x64/release/bundle/emoplay**（打包前置） |
| deb 打包 | `bash .github/scripts/package-linux.sh amd64 x64 v2.0.0-alpha` | **packaged**：deb 17,045,202 字节（Installed-Size 50820）+ tar.gz 20,743,844 字节；产物验证后已删除、树恢复干净（`/build/` 外产物不入库） |
| ldd 审计（CI 同款） | `ldd build/native_assets/linux/libmpv.so.2 \| grep 'not found'` | **0 个 not found**（grep 退出码 1）——容器内依赖闭包完整 |
| 直系依赖清点 | `readelf -d build/native_assets/linux/libmpv.so.2 \| grep NEEDED` | **34 个直系 NEEDED soname**，与 pr.yaml 注释的清单一致（libva*/libvdpau/libpulse/libxv/libegl/libgbm/libdrm/libunwind/liblcms2/libarchive/libasound/libXss 等全部在场） |
| Depends 覆盖审计 | `dpkg -S`（125 路径→104 包）+ `apt-cache depends --recurse --important`（17 包→251 包） | **comm -23 差集为空**——104 ⊂ 251，脚本注释的核心声明复现成立 |
| CI | `gh run list -R emoeem/emoplay --limit 10` | **2 条：42712702494 failure**（2m53s，2026-11-09T22:31:54Z UTC = 06:31 CST，头提交 `4d3eae5`）与 42706655830 failure（R2 已记录）；`gh run view 42712702494 --log-failed` 提取到 `324 tests passed, 2 failed, 1 skipped` 与 libpulse 报错 |
| 推送状态 | `git log origin/main..HEAD --oneline` / `git log HEAD..origin/main --oneline` | **3 个 R3 提交未推送**（`7debc83` 06:46 / `7052260` 06:52 / `c943414` 07:00 CST）；HEAD 无落后；R2 两个代码提交已在 origin |
| 树干净度 | 门禁与打包产物清理后 `git status --porcelain` | **空** |

### 3.1 CI 失败归因链（第二层洋葱，避免再误诊）

1. run 42712702494 头提交 `4d3eae5`（纯文档）——与 R2 同款：混合 push
   触发、标题只显示头提交（HANDOVER 坑 2 已记，本轮再证一次）。
2. 失败点仍是 `test/equalizer_test.dart` 两条真开 libmpv 的用例，报错从
   R2 的 `libva-drm.so.2` 变为 `libpulse.so.0`——**dlopen 每次只报第一个
   缺失依赖**，R2 修复只剥了第一层。
3. 本地 326 通过（R2 口径）= CI 324 通过 + 2 失败，用例数自洽；本地全绿
   ≠ CI 绿的根因始终是 runner 环境，不是用例本身。
4. 修复后预期 CI 签名：**332 passed / 0 failed / 1 skipped**（本地 332+1）。

## 4. 确认无问题的部分

- **数据兼容契约**：`test/data_compat_spec7_test.dart` 在 332 全绿内——
  1.x 三份 JSON 直接可读的发布承诺继续被锁定。
- **R3 对既有测试零改动**：`git show c943414 --stat` 中 test/ 仅为两个
  **新增**文件，全量套件绿即既有用例无回归；`git diff 4d3eae5..c943414
  --stat -- test/` = +322 行全在两新文件。
- **menuTabLabels 双壳同源**：竖屏 NavigationBar 与横屏 NavigationRail
  都从 `menuTabLabels(AppLocalizations.of(context))` 取标签
  （`menu.dart`），文案漂移在结构上不可能。
- **i18n 生成链与提交物一致**：`c943414` 改动 arb 后同步提交了 4 个生成
  文件（diff +15 行），`flutter test` / `flutter build` 内置 gen-l10n
  跑完树仍净——CI 无需额外生成步骤。
- **打包脚本参数化正确**：release.yaml 对 amd64/arm64 分别以
  `x64`/`arm64` 为 flutter-target-dir 调用同一脚本，产物通配上传
  （`release.yaml:201/:230`）。
- **依赖清单的分层纪律**：pr.yaml 只按 soname 钉直系 NEEDED（第一层），
  第二层编解码库交给发行版依赖图（注释明说 `libflac12t64` 这类名字随
  发行版变，钉死反而脆）——避免了「为全闭包钉 250 个包」的反模式。
- **工作流权限未变**：R3 两个 workflow 提交只动依赖安装步与步序，未引入
  secrets / dart-define（`git show 7debc83` 全文核对）。

## 5. 已知限制与未做项

**需要人工操作的**
- R3 三个提交（`7debc83` / `7052260` / `c943414`）与本轮文档的推送（本轮
  职责边界止于文档，推送由收尾流程执行）；推送后需人工确认 **CI 首绿**
  （预期签名 332/0/1）。
- GUI 实机验收与 Windows / macOS / Android 实体机验证；Android 签名密钥
  接入——均与 R1/R2 报告相同，本轮无变化。

**代码侧待办**
- **性能轮剩余**：扫描吞吐墙钟数字与首帧时间需实机（SPEC §9），isolate
  分片多开已评估不采（测试文件头注释记录理由）；缩略图并发上限的进一步
  调优无实测需求驱动。
- **i18n 其余页面**：页签壳之外逐页迁移（R3 只证明生成链在真实页面可用）。
- **测试对账残余**：`test_settings_service.cpp` 的
  `restoreDefaultsKeepsMediaAndHistory` 槽位与 `test_mpv_engine.cpp` 的
  `apply()` 半边仍无自动化覆盖（R2 报告 §5 原状，本轮未变）。
- **AppImage 与打包签名**未做；deb 已可产出但首次真实发布流程（tag →
  release.yaml 矩阵）仍未演练。
- 打包脚本注释「115」数字口径待施工方确认（见 §2 交付结论表末行）。

**固有限制**
- Windows 专属扫描探测在非 Windows 平台永远 skipped（QSKIP 契约对应物）。
- CI 对纯 markdown 推送不触发；混合 push 触发时 run 标题只显示头提交
  （R2/R3 两轮连续验证，归因链见 §3.1）。
- 私有仓库 Actions 分钟数有限，全平台矩阵只能随 tag 跑。
- ldd 闭包的「覆盖审计」结论以容器内（Ubuntu 26.04）包库为基准；其他
  发行版的包名映射（尤其 t64 前）不在脚本保证范围（注释已声明以
  ubuntu-latest 命名为准）。

## 6. 下一步建议

按优先级，每条可独立执行：

1. **推送并盯 CI 首绿**：`git push origin main` 后
   `gh run list -R emoeem/emoplay`。预期 332 passed / 1 skipped；若仍红灯，
   ldd 审计步会给出完整缺失清单——按清单补 pr.yaml 即可，不再逐层试。
2. **演练真实发布**：打 `v2.0.0-alpha` tag 触发 release.yaml 全平台矩阵，
   验收 deb/tar.gz/APK 产物链（打包脚本已实测，矩阵是最后一环）。
3. **i18n 第二页**：从设置页挑一类把字符串换成 `AppLocalizations` 取用
   （生成链已在页签壳验证可用）。
4. **性能实测轮**：实机跑大库扫描吞吐与首帧时间（SPEC §9），给
   `performance_guards_test.dart` 的定性守卫补定量基线。
5. **GUI 实机验收**：SPEC §9 冒烟约定中「显示待人工验收」部分。
