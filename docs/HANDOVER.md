# HANDOVER · EmoPlay 2.0 交接现状

| 项     | 值                                                                          |
| ------ | --------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-10 红灯清零 R3 之后）                                        |
| 日期   | 2026-11-10（最后实质性更新）                                                 |
| 适用版本 | git `c943414`                                                             |
| 相关   | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[docs/README.md](README.md) |

## 现状一句话

M1–M8 迁移主流程与 R1 对账 / R2 转绿 / R3 红灯清零三轮收尾全部完成：
Kazumi 骨架上重建的 Flutter/mpv 本地播放器功能对等（播放 / 本地媒体 / 媒体库 /
历史 / mpv 兼容导入 / 画质引擎 / 插件 / 11 类设置 / 更新检查），32 个测试文件
332 用例全绿、analyze 0 告警、debug / release 构建与 deb 打包（17 项 Depends
经 apt 递归闭包审计）实测通过，页签壳已接入 i18n；CI 两层红灯（VA/VDPAU →
libpulse）都已定位并修复（`3379d7a` / `7debc83`，后者含一次性列全缺失的
ldd 审计步），R3 三个提交待推送，**首绿仍未确认**——版本仍是未发布的
2.0.0-alpha。

## 最近实质性变更（R3，2026-11-10 早晨）

- `7debc83` CI 红灯第二层修复：R2 补的 VA/VDPAU 只是第一层（dlopen 每次只
  报第一个缺失依赖），第二层是 `libpulse.so.0`；readelf 实测捆绑
  `libmpv.so.2` 直系 NEEDED 后一次装全 14 个新包，pr.yaml 步序改为
  构建 → **ldd 审计（`grep 'not found' && exit 1`）** → 测试——以后依赖
  缺口一次列全，不再逐轮烧 CI 分钟数（release.yaml 同步装包）。
- `7052260` deb 打包依赖审计：`Depends` 2 项 → 17 项（GTK 显式钉入，不再
  靠 tray 侧链捎带），闭包覆盖经 `apt-cache depends --recurse` 审计
  （104 提供包 ⊂ 251 闭包，差集空）；容器内实测打包 deb + tarball 通过。
- `c943414` 剩余欠账：页签壳 i18n 第一页迁移（`menuTabLabels()` 双壳同源
  + 退出 toast）+ 媒体库响应性守卫 3 用例（取消延迟 / 进度节流 / 缩略图
  串行，`test/performance_guards_test.dart`）。
- 本轮文档：R3 发布说明 / 工作报告、HANDOVER 刷新、路线图数字修正
  （见[工作报告](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)）。

## 最容易踩的坑

1. **构建前必须 `source /opt/emoplay-env.sh`**——否则 PATH 里可能没有 Flutter 或
   用错 SDK；`PUB_CACHE=/opt/pub-cache` 也是它设的。宿主机零污染、
   `/home/emo/code/mpv-emo` 只读是硬红线（SPEC §3）。
2. **CI 信号要按归因链读**（[R2 报告 §3.1](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)、
   [R3 报告 §3.1](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)）：
   纯 markdown 推送不触发 CI（pr.yaml `paths-ignore: '**.md'`），但**代码与
   文档混在同一次 push 时会触发，且 run 标题只显示头提交**（R2/R3 两轮连续
   证实）——看到 `docs(...)` 标题的红灯别误判触发者。另：**本地全绿 ≠ CI 绿**
   ——runner 环境差异修 workflow，绝不跳过用例；且 **dlopen 每次只报第一个
   缺失依赖**（VA/VDPAU 修完挂 libpulse 就是这么来的），所以 pr.yaml 把
   `ldd libmpv.so.2 | grep 'not found'` 审计步放在测试之前——依赖缺口看
   审计步的全量清单，不要按测试报错逐层补。真开 libmpv 的测试依赖装步在
   `flutter test` 之前。
3. **平移铁律**：1.x 源文件注释里嵌着 mpv v0.37 源码级考证，必须连注释一起搬；
   `history.json`/`library.json`/`settings.json` 字段名一个都不能改（PORT-MAP 头部）。
4. **产品决策兜底顺序**：规格未覆盖取最接近 Kazumi 现状；与 SPEC §4 不变量冲突时
   不变量赢（SPEC §10）。
5. **文档提交与代码提交分开**：`docs:` 前缀，文档只动 markdown 与 CHANGELOG.md
   （DOC-STANDARD 提交前检查清单最后一条）。
6. **打包产物别留在仓库根**：`package-linux.sh` 把 deb/tar.gz/打包目录写在
   当前目录且不在 `.gitignore` 里——容器内验证后删掉再提交，CI 里靠
   release.yaml 的 upload-artifact 路径收集。

## 接手第一步清单

1. `source /opt/emoplay-env.sh && cd /home/emo/code/emoplay && flutter analyze && flutter test`
   ——预期 0 告警 + 332 通过 / 1 skipped，达不到先查环境再查代码。
2. `git fetch origin && git log origin/main..HEAD --oneline` 与
   `gh run list -R emoeem/emoplay --limit 5` ——确认 R3 三个提交是否已推送、
   **CI 首绿是否达成**（预期签名 332 passed / 1 skipped）；红灯按坑 2 的
   归因链处理（ldd 审计步会给全量缺失清单），仍红灯优先修。
3. 通读 [SPEC.md](SPEC.md) §4 不变量与 [PORT-MAP.md](PORT-MAP.md) 头部铁律。
4. 待办从 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) §四
   未做项清单取（推送确认 → tag 演练发布 → i18n 迁移 → 性能实测），以及
   [工作报告 §6](reports/WORK_REPORT_2026-11-10_RED_LIGHT_ZEROING.md)
   的优先级建议。
5. 改完代码跑 SPEC §9 gate（build_runner → analyze → test → build linux）。

## 路线图

路线图的权威来源是 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)
（M0–M8 ✅+提交哈希、R1/R2/R3 收尾轮次、未做项 ☐、验收标准与贯穿约定）；
逐里程碑的内容细节另见 [CHANGELOG.md](../CHANGELOG.md) 的 2.0.0-alpha 小节，
轮次结构与积压清单见 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四。
