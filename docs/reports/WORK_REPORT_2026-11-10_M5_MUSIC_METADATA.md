# 工作报告 · 2026-11-10（M5 音乐与在线元数据兜底 R11）

| 项           | 值                                                                              |
| ------------ | ------------------------------------------------------------------------------- |
| 报告日期     | 2026-11-12（文档收网窗口，07:00-07:05 CST 实测门禁）                             |
| 项目         | EmoPlay 2.0（mpv-emo 1.x 的 Flutter 重写）                                       |
| 版本         | git `eb3b2bf`（R11 施工尾提交，2026-11-12 06:55 CST）                            |
| 对应更新记录 | [`RELEASE_2026-11-10_M5_MUSIC_METADATA.md`](../releases/RELEASE_2026-11-10_M5_MUSIC_METADATA.md) |

## 1. 本轮范围

第 11 轮施工收网。施工面是 [EMOPLAY-3.0-ROADMAP.md](../EMOPLAY-3.0-ROADMAP.md)
§五 M5 音乐三任务（循环/队列、replaygain/gapless、歌词与迷你条）+ §六改向
注记排期的 M4-T7 在线元数据兜底框架（2026-11-12 用户决策：由「明确不做」
改向纳入，第 11 轮）。四个施工提交 + 本轮文档收网（发布说明、轮级工作
报告、HANDOVER 刷新、docs/README.md 索引登记、CHANGELOG R11 节、路线图
勾选回填随文档提交入库）。

- `2115183` R11: playlist mode + music queue（M5-T1）：9 文件 +871/-4
- `ec456b3` R11: replaygain + gapless（M5-T2）：14 文件 +807/-22
- `a539866` R11: lyrics upgrade + music mini bar（M5-T3）：8 文件 +706/-66
- `eb3b2bf` R11: online metadata fallback framework（M4-T7）：17 文件 +2076/-31
  （自带 CHANGELOG R11 施工件 D 小节与路线图 M4-T7 行）

## 2. 交付结论

| 级别 | 问题 | 状态 | 关键证据 |
| --- | --- | --- | --- |
| 施工 | M5-T1 循环/队列：`PlaylistMode.none` 硬编码提升三态 + 队列面板 | 完成 | `2115183`；`test/music_queue_test.dart` 7 用例（验收线 ≥5）；三动线（设置下拉 `lib/pages/settings/player_settings.dart:346` / 面板菜单 / music 形态队列面板 `player_item_panel.dart:677`） |
| 施工 | M5-T2 replaygain + gapless | 完成 | `ec456b3`；`mpv_player_properties_test.dart` +2（`replaygainMappingAndPresetPlacement` 纯逻辑 + `replaygainThreeStatesAndGaplessApplyToLiveCore` 真 libmpv）；设置往返 `test/audio_properties_settings_test.dart` 2 用例 |
| 施工 | M5-T3 歌词升级 + 常驻迷你条 | 完成 | `a539866`；`music_lyrics_page_test.dart` +3、`music_mini_bar_test.dart` 2 用例（验收线 ≥3 / ≥2）；`lrc_parser_test.dart` 零触碰（`git diff b87e1c8..HEAD --name-only -- test/` 11 文件清单核实不含） |
| 施工 | M4-T7 在线元数据兜底框架 | 框架完成；真实联网数据流待用户 TMDB key 人工验收（pending） | `eb3b2bf`；`online_meta_service_test.dart` 10 + `tmdb_provider_test.dart` 10 + `library_online_ui_test.dart` 1；施工轮可达性实测：api.themoviedb.org curl 0.83s / Dart HttpClient 1.04s，无效 key 恰返 HTTP 401 |
| 文档 | 路线图勾选回填 | 完成（工作树，随本轮文档提交入库） | `git diff docs/EMOPLAY-3.0-ROADMAP.md`：M4-T7 行补哈希 `eb3b2bf`、M5-T1/T2/T3 ☐→✅+哈希，与四提交逐一相符 |
| 文档 | R11 文档收网五件 | 完成 | release + 本报告 + HANDOVER 刷新 + docs/README.md 索引 + CHANGELOG R11 节（一轮一节，替换施工件 D 单件小节） |

## 3. 工程状态（实测）

门禁全部在 2026-11-12 文档窗口由本文档轮重跑（命令先 `source /opt/emoplay-env.sh`）：

| 门禁 | 结果 |
| --- | --- |
| `flutter analyze` | **0 告警**（`No issues found! (ran in 5.3s)`） |
| `flutter test` | **60 文件 / 539 通过 + 1 平台条件跳过全绿**（reporter 尾行 `00:24 +539 ~1: All tests passed!`） |
| 测试文件计数 | `ls test/*_test.dart \| wc -l` = **60**（R10 为 54，+6：music_queue / audio_properties_settings / music_mini_bar / online_meta_service / tmdb_provider / library_online_ui） |
| 账目闭环 | `git diff b87e1c8..HEAD` 逐文件点数新增用例（`^\+\s*(test\|testWidgets)\(` 计数）：emoplay_settings 12、tmdb_provider 10、online_meta_service 10、music_queue 7、music_lyrics_page 3、music_mini_bar 2、mpv_player_properties 2、audio_properties_settings 2、library_online_ui 1、audio_settings_l10n 1、library_nfo_ui 0，**合计 50 = 539-489** ✓ |
| 1 skip 身份 | `test/mpv_profile_scanner_test.dart:217` Windows-only 探针（与 R9/R10 同一身份） |
| CI（gh 本窗口可达） | `gh run list -R emoeem/emoplay --limit 5` 实测：v2.2.0-alpha main run 43101040926 ✓（3m36s）、release run 43101070581 ✓（13m34s）；v2.1.0-alpha 两 run 此前已绿。R11 四提交未推送 |
| release 状态 | `gh release view v2.2.0-alpha --json isDraft,assets` = `{"assets":11,"draft":false}`（已公开） |
| 提交状态 | `git log origin/main..HEAD --oneline` = 4（`2115183` / `ec456b3` / `a539866` / `eb3b2bf`，ahead 4；origin/main 在 `b87e1c8` = v2.2.0-alpha 发版提交） |

## 4. 确认无问题的部分

- **§7 三份 schema 零触碰**：本轮三组新键（`behavior.playlistMode` /
  `audio.replaygain` / `online.enabled`+`online.apiKey`）全部是 settings.json
  追加键（`lib/settings/emoplay_settings.dart` 注释与 §四红线一致），
  `media_online.json` 是第 4 个独立新 AppData 文件；`data_compat_spec7_test.dart`
  在全量跑内通过（539 绿的一部分）。
- **验收下限全达标**：M5-T1 7≥5、M5-T2 2≥2（含设置往返）、M5-T3 3≥3 与
  2≥2；`lrc_parser_test.dart` 按验收要求不动。
- **未知/损坏取值回落契约**：`QueueLoopMode` 存储值与 `replaygainMpvValue`
  映射对未知值都落回默认（不循环 / 不启用），不臆测档位；两处均有专门断言。
- **media_online.json 沿用新文件先例**：原子写 + 损坏降级 + 负缓存语义
  （传输失败不缓存）各有专门用例；与 media_meta.json / media_nfo.json 的
  缓存失效键互不干扰（键 = 视频绝对路径）。
- **迷你条挂载路径与点 tab 同源**：shell 注入 `_selectDestination`
  （`menu.dart`），缺省回调走 `context.navigate('/tab/player/')`，测试与
  裸挂载不依赖 shell。
- **预置选项与导入 mpv.conf 的优先级**：replaygain / gapless-audio 放默认
  半区，compatOptions 最后 addAll 后写者胜（`mpv_player_properties_test.dart`
  的 compatWins 断言锁定）。

## 5. 已知限制与未做项

**需要人工操作的**

1. TMDB API key 填入 + 真实联网数据流人工验收（设置 → 在线元数据 → 媒体库
   挑无 NFO 条目走「联网补全」），七种结果逐一核对；框架轮边界，非缺陷。
2. replaygain（track/album 档 + 有标签音频）与 gapless（同参数连播）的
   **听感**验收，SPEC §9 挂账；属性层 live 用例只证明接受 + 回读一致。
3. R11 四施工提交 + 本轮文档提交的推送（ahead 4 + 文档），推送后核对 CI
   签名是否 **539 passed / 1 skipped**。

**代码侧待办**

4. 3.0 施工下一阶段 M6 插件安全（清单校验，路线图 §五 M6）；M3 残留
   T1 帧预览 / T2 刻度收口 / T3 面板择机清偿。
5. 版本 bump 与发版决策：R11 目前在 `[Unreleased]`，是否随 v3.0.0-alpha
   （或 2.3.0-alpha）收口待定；沿用 draft 制时忘 publish 是主要失效模式。

**固有限制**

6. 列表循环回卷依赖应用层管线（`PlayerProgressPipeline` + `resolveQueueNextIndex`），
   引擎侧 playlist 单 entry 语义不动（见发布说明 §一/§五-5）。
7. 迷你条只在 shell 层显示，播放页内部不显示；对视频条目同样生效（命名
   保留 music 前缀跟随路线图）。
8. 容器内无法验证 CI 矩阵的平台侧（Windows/macOS/Android/arm64 产物），
   归 release.yaml 与实体机（CROSS-PLATFORM-VERIFICATION-MATRIX.md）。

## 6. 下一步建议

1. **推送**：R11 四提交 + 文档提交一起推（代码与文档混推会触发 CI，run
   标题只显示头提交），核对签名 539/1；红灯按 HANDOVER 坑 2 归因链处理。
2. **TMDB key 验收**：填 key 后媒体库实测「联网补全」七种结果与
   `media_online.json` 正/负缓存行为；顺带确认掩码显示与「恢复默认设置」
   对 `online` 段的覆盖。
3. **听感验收**：replaygain 选 track/album 播放带标签音频对比响度；
   连播两张同参数编码专辑验证 gapless 无缝与进度条推进。
4. **M6 开工**：按路线图 §五 M6 插件安全起手（清单校验），M3 残留三项
   排在 M6 后或穿插；开工前过一遍 HANDOVER 最易踩的坑 12（真相源）。
5. **发版收口**：R11 验收完成后走版本 bump + CHANGELOG 折叠 + tag +
   draft publish 流程（BUILD_GUIDE §四）。
