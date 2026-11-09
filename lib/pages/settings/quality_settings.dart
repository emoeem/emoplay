// 设置中心「视频与画质」分类页 (SPEC §6 category 3):
// contentMode / qualityTier / toneMappingMode / scaleOverride / debandMode、
// Anime4K 开关与档位、插值/补帧 VapourSynth 预设、ICC profile。
//
// The page drives the M6 quality controllers (lib/quality/) — the same
// objects the live player is wired to — so every change both persists to
// settings.json's "quality" section and re-applies to a running engine,
// exactly the 1.x quality panel's contract (QualityController setters:
// persist, prefsChanged, applyProfile). Kazumi settings components
// (SettingsList/SettingsSection/SettingsTile/SettingsRadioSection/
// SettingsDropdownTile) carry the interaction.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/quality/interpolation_decision.dart';
import 'package:emoplay/quality/quality_stores.dart';

class QualitySettingsPage extends StatelessWidget {
  const QualitySettingsPage({super.key});

  static const Map<String, String> _contentModes = {
    'auto': '自动（按文件名特征识别）',
    'anime': '动画',
    'live': '真人',
  };

  static const Map<String, String> _qualityTiers = {
    'off': '关闭（不改任何渲染选项）',
    'low': '低（仅开去色带）',
    'medium': '中（高质量缩放 + 去色带）',
    'high': '高（Anime4K / SSimSuperRes + 中档全部）',
  };

  static const Map<String, String> _debandModes = {
    'auto': '自动（画质引擎开启时开）',
    'yes': '强制开启',
    'no': '强制关闭',
  };

  static Map<String, String> get _toneMappings => {
        for (final value in const [
          'auto',
          'clip',
          'mobius',
          'reinhard',
          'hable',
          'gamma',
          'linear',
          'bt.2390',
        ])
          value: value,
      };

  static Map<String, String> get _scaleChoices => {
        for (final value in const [
          '',
          'bilinear',
          'lanczos',
          'ewa_lanczos',
          'ewa_lanczossharp',
          'ewa_lanczos4sharpest',
          'mitchell',
          'hermite',
          'catmull_rom',
          'oversample',
          'linear',
        ])
          value: value.isEmpty ? '自动（按档位选择）' : value,
      };

  static Map<String, String> _presetOptions() => {
        for (final preset in presets) preset.id: preset.id,
      };

  @override
  Widget build(BuildContext context) {
    final QualityStores stores = MediaStores.instance.quality;
    return SettingsDetailScaffold(
      title: const Text('视频与画质'),
      body: SettingsList(
        sections: [
          // 画质档位（Anime4K 的开与档都在这里：off 即关，high 动画档挂
          // Anime4K 链，high 真人档挂 SSimSuperRes——1.x 决策表语义）。
          SettingsSection(
            title: const Text('画质引擎'),
            tiles: [
              Observer(
                builder: (_) => SettingsDropdownTile<String>(
                  leading: Icons.movie_filter_rounded,
                  title: const Text('内容类型'),
                  description: const Text('动画挂 Anime4K 链，真人挂 SSimSuperRes'),
                  value: stores.quality.contentMode,
                  options: _contentModes,
                  onChanged: stores.quality.setContentMode,
                ),
              ),
              Observer(
                builder: (_) => SettingsRadioSection<String>(
                  title: const Text('画质档位（Anime4K 开关与档位）'),
                  groupValue: stores.quality.qualityTier,
                  onChanged: (value) {
                    if (value != null) {
                      stores.quality.setQualityTier(value);
                    }
                  },
                  tiles: [
                    for (final entry in _qualityTiers.entries)
                      SettingsTile<String>.radioTile(
                        title: Text(entry.value),
                        radioValue: entry.key,
                      ),
                  ],
                ),
              ),
              Observer(
                builder: (_) => SettingsDropdownTile<String>(
                  leading: Icons.texture_rounded,
                  title: const Text('去色带'),
                  value: stores.quality.debandMode,
                  options: _debandModes,
                  onChanged: stores.quality.setDebandMode,
                ),
              ),
              Observer(
                builder: (_) => SettingsTile(
                  leading: Icons.folder_open_rounded,
                  title: const Text('着色器目录'),
                  description: Text(
                    '${stores.shadersDir}\n已装 GLSL：${stores.quality.availableShaders.length} 个',
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('高级渲染'),
            tiles: [
              Observer(
                builder: (_) => SettingsDropdownTile<String>(
                  leading: Icons.high_quality_rounded,
                  title: const Text('HDR 色调映射'),
                  description: const Text('HDR 片源的 tone-mapping；vo=libmpv 下可用集合'),
                  value: stores.quality.toneMappingMode,
                  options: _toneMappings,
                  onChanged: stores.quality.setToneMappingMode,
                ),
              ),
              Observer(
                builder: (_) => SettingsDropdownTile<String>(
                  leading: Icons.photo_size_select_large_rounded,
                  title: const Text('缩放算法覆盖'),
                  value: stores.quality.scaleOverride,
                  options: _scaleChoices,
                  onChanged: stores.quality.setScaleOverride,
                ),
              ),
            ],
          ),
          // 插帧：VapourSynth 预设指向应用数据 vs/ 目录，.vpy 不随应用
          // 分发（诚实外置依赖模式——脚本缺失/滤镜不支持时面板给出原因）。
          SettingsSection(
            title: const Text('插帧（VapourSynth）'),
            bottomInfo: Observer(
              builder: (_) {
                final interpolation = stores.interpolation;
                final hint = interpolation.vsUnavailable
                    ? '当前 libmpv 不支持 VapourSynth 滤镜，插帧已自动关闭'
                    : _blockHint(interpolation.blockReason);
                final scriptPath = interpolation.expectedScriptPath;
                return Text(
                  [
                    if (hint.isNotEmpty) hint,
                    if (scriptPath.isNotEmpty) '预设脚本位置：$scriptPath',
                    '把对应的 .vpy 文件放到上面的位置即可启用该预设',
                  ].join('\n'),
                );
              },
            ),
            tiles: [
              Observer(
                builder: (_) => SettingsTile.switchTile(
                  leading: Icons.slow_motion_video_rounded,
                  title: const Text('启用插帧'),
                  description: const Text('低于 50fps 的 SDR 片源才会实际挂载'),
                  initialValue: stores.interpolation.enabled,
                  onToggle: (value) =>
                      stores.interpolation.setEnabled(value ?? false),
                ),
              ),
              Observer(
                builder: (_) => SettingsDropdownTile<String>(
                  leading: Icons.tune_rounded,
                  title: const Text('插帧预设'),
                  value: stores.interpolation.preset,
                  options: _presetOptions(),
                  onChanged: stores.interpolation.setPreset,
                  fallbackLabel: '未知预设',
                ),
              ),
            ],
          ),
          // ICC：校验 → 设置 → 读回，失败持久化 off 并显示原因（1.x
          // IccController 契约）；缓存目录始终走 P4 重定向表。
          SettingsSection(
            title: const Text('ICC 色彩管理'),
            bottomInfo: Observer(
              builder: (_) {
                final icc = stores.icc;
                final lines = <String>[
                  '3DLUT 缓存目录：${icc.cacheDir}',
                  if (icc.failed && icc.failureHint.isNotEmpty) icc.failureHint,
                ];
                return Text(lines.join('\n'));
              },
            ),
            tiles: [
              Observer(
                builder: (_) => SettingsTile.switchTile(
                  leading:Icons.color_lens_rounded,
                  title: const Text('启用 ICC profile'),
                  initialValue: stores.icc.enabled,
                  onToggle: (value) => stores.icc.setEnabled(value ?? false),
                ),
              ),
              Observer(
                builder: (_) => SettingsTile(
                  leading: Icons.description_rounded,
                  title: const Text('ICC profile 文件'),
                  description: Text(
                    stores.icc.profilePath.isEmpty ? '未选择' : stores.icc.profilePath,
                  ),
                  onPressed: (_) => _pickIccProfile(context, stores),
                  trailing: const Icon(Icons.file_open_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickIccProfile(BuildContext context, QualityStores stores) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择 ICC profile (.icc / .icm)',
    );
    final path = result?.files.single.path;
    if (path != null) {
      stores.icc.setProfilePath(path);
    }
  }

  // Panel hint text for the current admission block (machine ids come from
  // InterpolationDecision.blockToString; the localized strings live here so
  // the pure table stays UI-free, exactly the 1.x split).
  static String _blockHint(String block) {
    switch (block) {
      case 'disabled':
        return '插帧未启用';
      case 'fps-unknown':
        return '等待媒体参数（帧率未知）';
      case 'high-fps':
        return '帧率已达 50fps 以上，无需插帧';
      case 'hdr':
        return 'HDR 片源不插帧';
      case 'script-missing':
        return '预设脚本缺失（见下方路径）';
      case 'foreign-vapoursynth':
        return '检测到外部 VapourSynth 滤镜，EmoPlay 让位不干预';
      default:
        return '';
    }
  }
}
