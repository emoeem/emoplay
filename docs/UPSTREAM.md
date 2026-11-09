# 上游与来源记录

## Kazumi（M1 骨架起点）

- 仓库快照：`/home/emo/code/_upstream/kazumi`（工作树导入，未 fork、未带上游 git 历史）
- 导入 HEAD：`7265274fac136a0cfe6ee32ea37f32f06ea57672`（2026-11-04，version 2.4.3，main）
- 导入方式：rsync 工作树，排除 `.git/`、`fastlane/`、`.gitmodules`（fastlane 两个子模块未随行）
- 剥离依据：`docs/STRIP-LIST.md`；改造依据：`docs/SPEC.md`
- 许可：Kazumi 代码版权（Predidit 及贡献者，GPL-3.0）保留，见 `NOTICE.md` 与各文件头

## 其他参考

- EmoPlay 1.x：`/home/emo/code/mpv-emo`（C++/Qt，只读参考；行为语义与 JSON schema 契约见 `docs/PORT-MAP.md`）
- PiliPlus：`/home/emo/code/_upstream/piliplus`（只读参考，播放器交互小件摘取在 S2）
