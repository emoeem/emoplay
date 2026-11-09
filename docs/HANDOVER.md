# HANDOVER · EmoPlay 2.0 交接现状

| 项     | 值                                                                          |
| ------ | --------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-10 转绿补账 R2 之后）                                        |
| 日期   | 2026-11-10（最后实质性更新）                                                 |
| 适用版本 | git `b61dff2`                                                             |
| 相关   | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[docs/README.md](README.md) |

## 现状一句话

M1–M8 迁移主流程、R1 对账收网与 R2 转绿补账全部完成：Kazumi 骨架上重建的
Flutter/mpv 本地播放器功能对等（播放 / 本地媒体 / 媒体库 / 历史 / mpv 兼容
导入 / 画质引擎 / 插件 / 11 类设置 / 更新检查），30 个测试文件 326 用例
全绿、analyze 0 告警、Linux debug 构建通过，i18n 骨架就位（页面字符串未
迁移）；CI 首跑红灯（runner 缺 VA/VDPAU 运行库）已定位修复（`3379d7a`），
修复与补账两个提交待推送，**首绿未确认**——版本仍是未发布的 2.0.0-alpha。

## 最近实质性变更（R2，2026-11-10 早晨）

- `3379d7a` CI 红灯修复：pr.yaml 依赖安装步挪到 `flutter test` 之前并补装
  `libva2 libva-drm2 libva-x11-2 libva-wayland2 libvdpau1`（release.yaml
  同步）——根因是 media_kit 捆绑 `libmpv.so.2` 链接 VA/VDPAU，runner 没装
  （见[发布说明二-1](releases/RELEASE_2026-11-10_TURN_GREEN_BACKFILL.md)）。
- `b61dff2` 补账三笔：`test/robustness_test.dart`（损坏媒体 / 空结果 /
  权限拒绝，11 用例）+ `test/settings_service_semantics_test.dart`
  （`test_settings_service.cpp` 两槽位语义）+ i18n 骨架（`l10n.yaml` +
  en/zh arb + 生成类 + `app_widget.dart` 装配）；顺带建立
  [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)。
- 本轮文档：R2 发布说明 / 工作报告、HANDOVER 刷新、路线图滞后数字修正
  （见[工作报告](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)）。

## 最容易踩的坑

1. **构建前必须 `source /opt/emoplay-env.sh`**——否则 PATH 里可能没有 Flutter 或
   用错 SDK；`PUB_CACHE=/opt/pub-cache` 也是它设的。宿主机零污染、
   `/home/emo/code/mpv-emo` 只读是硬红线（SPEC §3）。
2. **CI 信号要按归因链读**（[R2 报告 §3.1](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)）：
   纯 markdown 推送不触发 CI（pr.yaml `paths-ignore: '**.md'`），但**代码与
   文档混在同一次 push 时会触发，且 run 标题只显示头提交**——看到
   `docs(...)` 标题的红灯别误判触发者；反之文档轮次看不到新 run 也是正常的。
   另：**本地全绿 ≠ CI 绿**——runner 环境差异修 workflow（如本轮补 VA/VDPAU
   运行库），绝不跳过用例；真开 libmpv 的测试依赖 pr.yaml 的装步在
   `flutter test` 之前。
3. **平移铁律**：1.x 源文件注释里嵌着 mpv v0.37 源码级考证，必须连注释一起搬；
   `history.json`/`library.json`/`settings.json` 字段名一个都不能改（PORT-MAP 头部）。
4. **产品决策兜底顺序**：规格未覆盖取最接近 Kazumi 现状；与 SPEC §4 不变量冲突时
   不变量赢（SPEC §10）。
5. **文档提交与代码提交分开**：`docs:` 前缀，文档只动 markdown 与 CHANGELOG.md
   （DOC-STANDARD 提交前检查清单最后一条）。

## 接手第一步清单

1. `source /opt/emoplay-env.sh && cd /home/emo/code/emoplay && flutter analyze && flutter test`
   ——预期 0 告警 + 326 通过 / 1 skipped，达不到先查环境再查代码。
2. `git fetch origin && git log origin/main..HEAD --oneline` 与
   `gh run list -R emoeem/emoplay --limit 5` ——确认 R2 两个提交是否已推送、
   **CI 首绿是否达成**；红灯按坑 2 的归因链处理，仍红灯优先修。
3. 通读 [SPEC.md](SPEC.md) §4 不变量与 [PORT-MAP.md](PORT-MAP.md) 头部铁律。
4. 待办从 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md) §四
   未做项清单取（推送确认 → 打包 → i18n 迁移 → 性能），以及
   [工作报告 §6](reports/WORK_REPORT_2026-11-10_TURN_GREEN_BACKFILL.md)
   的优先级建议。
5. 改完代码跑 SPEC §9 gate（build_runner → analyze → test → build linux）。

## 路线图

路线图的权威来源是 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)
（M0–M8 ✅+提交哈希、R1/R2 收尾轮次、未做项 ☐、验收标准与贯穿约定）；
逐里程碑的内容细节另见 [CHANGELOG.md](../CHANGELOG.md) 的 2.0.0-alpha 小节，
轮次结构与积压清单见 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四。
