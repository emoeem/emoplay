# EmoPlay 过夜自动循环手册

| 项     | 值                                                                        |
| ------ | ------------------------------------------------------------------------- |
| 状态   | 生效中（2026-11-10 夜间窗口，至用户当地 ~09:00）                          |
| 日期   | 2026-11-10                                                                |
| 工作流 | `dwfrun-c1ac058d-a75f-4f2e-97b1-d7d2d0bdacb6`，脚本 `.zcode/workflow-drafts/EmoPlay-2.0-全量迁移.dwf.ts` |
| 相关   | [DOC-STANDARD.md](DOC-STANDARD.md)、[SPEC.md](SPEC.md)、[PORT-MAP.md](PORT-MAP.md) |

## 一、目标与停止条件

把 token 额度用到窗口结束为止：迁移主流程（M0–M8）结束后，持续执行
「缺口分析 → 施工 → 文档 → 推送 GitHub → CI 检测」的轮次循环，每轮结束必须推送备份。

**停止条件（任一满足即停）：**
1. 用户喊停。
2. 配额耗尽：run 变 `stopped`（provider，usage cap）——**不要手动 resume**；若额度会重置，
   ZCode 在重置后自动续跑；若不会重置，保持停止并保留现场（所有工作已 checkpoint + 推送）。
3. 到达窗口结束时间且当前轮收尾已完成（推送成功）。

## 二、轮次结构（每轮）

1. **开工检查**：`gh run list -R emoeem/emoplay --limit 5` 看上一轮 CI 结论；红灯的 job 列入本轮 issues。
2. **缺口分析**：派一个 agent 读 `SPEC.md`/`PORT-MAP.md`/仓库现状/上一轮 findings，
   输出按优先级排序的 issues（每条：title / why / approach / gate 命令 / 预估规模）。
3. **施工**：把 issues 写成工作流阶段。每阶段模式与主流程一致：
   专属 agent（PERSONA 复用）→ 施工 → `world.run` 门禁（build_runner/analyze/test/build，按需）→
   `checkpoint("R<N>: <主题>")`。阶段数量按 issues 定，1–4 个为宜。
4. **收尾**：调 `roundWrapup(roundNo, theme)`（工作流脚本内已定义）——文档员按 DOC-STANDARD
   出 `releases/RELEASE_*` 与 `reports/WORK_REPORT_*`、更新 `HANDOVER.md` 与 `docs/README.md` 索引 →
   docs checkpoint → `git push origin main` → 触发 CI。
5. **续轮**：以新的尾洞结束本轮填充，`roundNo = roundNo + 1`，洞口提示里带上本轮结果与未消化 issues。

## 三、操作机制

- 主工作流是**生长式**的：系统通知（洞口等待/完成/受阻）会自动唤醒主会话；每小时一次的
  cron 自检是兜底。
- 继续一轮的标准动作：**FillWorkflowHole**（`path` = 填充文件，body 只写语句，可读洞口前
  所有绑定：`ms`/`verified`/`findingsSoFar`/`roundWrapup`/`roundNo` 等）。
- 需要修改**既有阶段**时用 **AmendWorkflow**（`path` = 脚本文件）；**永远不要用 CreateWorkflow
  开新 run**——那会弹用户确认窗口，用户在睡觉。
- 文档标准在 `docs/DOC-STANDARD.md`；两份硬性模板（更新记录/工作报告）在标准第七节。

## 四、起始积压清单（缺口分析单薄时按此优先级取）

1. **CI 收敛**：push/PR 触发的 workflow 只保留 linux `analyze + test + build`；
   windows/macos/android 全平台矩阵移入仅 tag 触发的 release workflow（私有仓库省 Actions minutes）。
2. **flutter analyze 告警清零**（M1–M7 累积的 info/warning 逐类清理）。
3. **测试对账**：按 `PORT-MAP.md` §4 把 C++ 用例表与 Dart 测试逐一对账，补漏。
4. **`HANDOVER.md` + `UPGRADE_ROADMAP_2026-11-10.md`** 建立（ROADMAP 按 DOC-STANDARD 4.4，
   含 M0–M8 的 ☐/✅+提交哈希回填）。
5. **打包**：linux deb（参照 Kazumi CI 的 deb 产物链）或 AppImage。
6. **健壮性**：损坏媒体文件 / 无 ffmpeg 降级 / 空库 / 超长路径 / 拒绝权限目录的测试。
7. **性能**：大库扫描 isolate 分片与取消延迟、缩略图并发上限、首帧时间。
8. **i18n**：en arb 骨架（SPEC §1）。
9. **README** 双语终稿 + 截图（容器 GUI 不可达则标注"待人工"，不编图）。

## 五、红线（每轮开工前默念）

- 宿主机零污染不变；`/home/emo/code/mpv-emo` 只读不变；GPL-3.0 与 NOTICE 不变。
- 文档提交与代码提交分开（`docs:` 前缀），文档只动 markdown 与 CHANGELOG.md。
- 每轮收尾必须推送 GitHub——这是备份承诺，哪怕只改文档也要推。
- 收尾要轻（一轮收尾的 token 开销远小于施工），token 大头永远花在施工与测试上。
- 所有数字实测；拿不到就写"未测"；坏消息写进"已知取舍/未做项"。
