# HANDOVER · EmoPlay 2.0 交接现状

| 项     | 值                                                                          |
| ------ | --------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-10 对账收网 R1 之后）                                        |
| 日期   | 2026-11-10（最后实质性更新）                                                 |
| 适用版本 | git `a7488d9`                                                             |
| 相关   | [SPEC.md](SPEC.md)、[OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md)、[docs/README.md](README.md) |

## 现状一句话

M1–M8 迁移主流程与 R1 对账收网全部完成：Kazumi 骨架上重建的 Flutter/mpv 本地
播放器达到功能对等（播放 / 本地媒体 / 媒体库 / 历史 / mpv 兼容导入 / 画质引擎 /
插件 / 11 类设置 / 更新检查），28 个测试文件 313 用例全绿、analyze 0 告警、
Linux debug 构建通过，版本仍是未发布的 2.0.0-alpha，CI 因触发分支笔误刚修复
尚未首跑。

## 最近实质性变更（R1，2026-11-10 凌晨）

- `916c2d6` 修 CI 触发分支 `master`→`main`（此前 CI 一次都没跑过，见
  [发布说明二-1](releases/RELEASE_2026-11-10_RECONCILIATION_CLOSEOUT.md)）。
- `d1866dd` 补平移 1.x 更新检查（`lib/services/update_checker.dart`，只报告不
  下载、失败静默）+ PORT-MAP MediaBrowser 行对账为 N/A。
- `a7488d9` 测试对账：画质三控制器测试面合入 `quality_engine_test.dart`，顺带修
  掉 MobX 镜像不随设置重读的语义偏差（`interpolation_controller.dart:172`、
  `quality_controller.dart:375`）。

## 最容易踩的坑

1. **构建前必须 `source /opt/emoplay-env.sh`**——否则 PATH 里可能没有 Flutter 或
   用错 SDK；`PUB_CACHE=/opt/pub-cache` 也是它设的。宿主机零污染、
   `/home/emo/code/mpv-emo` 只读是硬红线（SPEC §3）。
2. **纯 markdown 推送不触发 CI**（pr.yaml `paths-ignore: '**.md'`）——文档轮次
   `gh run list` 看不到新 run 是正常的，不是坏了；红灯要找带代码的推送。
3. **平移铁律**：1.x 源文件注释里嵌着 mpv v0.37 源码级考证，必须连注释一起搬；
   `history.json`/`library.json`/`settings.json` 字段名一个都不能改（PORT-MAP 头部）。
4. **产品决策兜底顺序**：规格未覆盖取最接近 Kazumi 现状；与 SPEC §4 不变量冲突时
   不变量赢（SPEC §10）。
5. **文档提交与代码提交分开**：`docs:` 前缀，文档只动 markdown 与 CHANGELOG.md
   （DOC-STANDARD 提交前检查清单最后一条）。

## 接手第一步清单

1. `source /opt/emoplay-env.sh && cd /home/emo/code/emoplay && flutter analyze && flutter test`
   ——预期 0 告警 + 313 通过 / 1 skipped，达不到先查环境再查代码。
2. `git fetch origin && git log origin/main..HEAD --oneline` 与
   `gh run list -R emoeem/emoplay --limit 5` ——确认 R1 提交是否已推送、CI 首绿
   是否达成；红灯优先处理。
3. 通读 [SPEC.md](SPEC.md) §4 不变量与 [PORT-MAP.md](PORT-MAP.md) 头部铁律。
4. 待办从 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四积压清单取（打包 → 健壮性 →
   性能 → i18n），以及工作报告 §6 的优先级建议。
5. 改完代码跑 SPEC §9 gate（build_runner → analyze → test → build linux）。

## 路线图

路线图的权威来源是 [UPGRADE_ROADMAP_2026-11-10.md](UPGRADE_ROADMAP_2026-11-10.md)
（R2 轮建立，M0–M8 ✅+提交哈希、R1/R2 收尾轮次、未做项 ☐、验收标准与贯穿约定）；
逐里程碑的内容细节另见 [CHANGELOG.md](../CHANGELOG.md) 的 2.0.0-alpha 小节，
轮次结构与积压清单见 [OVERNIGHT-LOOP.md](OVERNIGHT-LOOP.md) §四。
