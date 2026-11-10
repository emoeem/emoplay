# 构建与发布手册 · EmoPlay 2.0

| 项       | 值                                                              |
| -------- | --------------------------------------------------------------- |
| 状态     | 生效中                                                          |
| 日期     | 2026-11-11（最后实质性更新）                                     |
| 相关     | [HANDOVER.md](../HANDOVER.md)（坑列表）、[../README.md](../../README.md)（依赖清单）、[../../.github/workflows/release.yaml](../../.github/workflows/release.yaml) |

## 一、适用场景

本地构建（开发自验、打包冒烟）与正式发布（tag 触发 CI 矩阵 → 人工核对 →
publish）。发布演练的完整归因链见 HANDOVER 坑 8。

## 二、前置条件

1. **构建前必须 `source /opt/emoplay-env.sh`**（HANDOVER 坑 1）：PATH 里的
   Flutter、`PUB_CACHE=/opt/pub-cache` 都由它设置；全部构建只在容器内做，
   宿主机零污染。
2. 本机 Linux 构建依赖已随容器就绪；CI 的依赖装步以
   `.github/workflows/pr.yaml` 与 `release.yaml` 的
   `Install native build tools` 步为准。
3. `gh` CLI 可用且有 `emoeem/emoplay` 的 release 写权限（发布步需要；
   api.github.com 在收网窗口内可能不可达，见 HANDOVER）。

## 三、本地构建与打包（可直接复制的命令）

```bash
source /opt/emoplay-env.sh && cd /home/emo/code/emoplay
flutter analyze && flutter test          # SPEC §9 门禁前两步
flutter build linux --release            # 或 --debug
# Linux 打包（tar.gz + deb；AppImage 另有 package-appimage.sh）：
./.github/scripts/package-linux.sh amd64 x64 v2.0.0-alpha
```

打包产物落在仓库根（`.gitignore` 已覆盖，验证完建议清掉，HANDOVER 坑 6）。

## 四、正式发布流程（draft 制）

1. 推送 `v*` tag 触发 `release.yaml`：test → analyze → 五平台构建矩阵 →
   **Create release 步带 `draft: true`**（release.yaml `Create release` 步）。
2. 产物齐后 release 是 **draft**：不公开、不占 Latest 位、只有维护者可见。
   到 GitHub Releases 页或 `gh release view <tag> -R emoeem/emoplay` 核对
   资产清单（按 release.yaml 的 `files:` 列表：Android APK、Windows
   zip+msix、macOS zip、Linux amd64/arm64 各 tar.gz+deb+AppImage；R4 实测
   9 资产为 AppImage 落地前底数，R6 起 AppImage 计入）。
3. 人工确认产物齐且可用后 publish：

   ```bash
   gh release edit <tag> --draft=false        # 例：gh release edit v2.0.0-alpha --draft=false
   ```

4. **不 publish 就没有发布**：draft release 不会出现在 Releases 公开页，
   忘记 publish 是新流程的主要失效模式（见 §六已知限制）。

## 五、常见故障与排查顺序

1. tag 触发的 run 红灯：按 HANDOVER 坑 2 的归因链读 CI 信号（本地全绿 ≠
   CI 绿；dlopen 只报第一个缺失依赖，看 ldd 审计步全量清单）。
2. Windows job 找不到 yq：已由 R5 修复（`choco install yq` 前置）；若复发
   检查 flutter-action 的 `flutter-version-file` 是否被改回无 yq 的路径。
3. arm64 job 排队不动：runner 由 `vars.LINUX_ARM64_RUNNER` 控制（默认
   `ubuntu-24.04-arm`），仓库 Variables 未配置时核对默认 label。
4. 发布语义（再演练要先删已有 release 与 tag、产物对应 tag 指向的提交）：
   HANDOVER 坑 8。

## 六、已知限制

- **publish 是人工步**：draft 制换来的安全（alpha/误 tag 不会自动占 Latest，
  draft 也不能被设为 Latest），代价是必须有人执行 §四-3 的命令。
- APK / MSIX / AppImage / macOS zip 均未签名；macOS 未公证；iOS 在矩阵外
  （release.yaml 注释块）。签名接入点见 release.yaml 内注释。
- **prerelease / Latest 语义未决**：`v2.0.0-alpha` 现占公开 Latest 位
  （HANDOVER 坑 8(a)），publish 时是否补 `--latest=false` /
  prerelease 标注待路线图决策。
- 本手册不含 Android/iOS 本地构建排查；Android 构建镜像问题见
  HANDOVER「R5 移动端修复」小节。
