// 设置中心「音频」分类页 (SPEC §6 category 4)：EQ 开关、预设、10 段增益
// 滑块。驱动的是 M7 音乐层 MusicController（挂在当前播放器上的同一个实
// 例），每次改动既持久化 settings.json 的 music 段也实时重挂 mpv af 链
// （1.x MusicController 契约）。链式考证见 music/equalizer.dart 文件头。
//
// R4 i18n：第二个迁移到 AppLocalizations 的页面（R3 建议 3「从设置页挑
// 一类」的执行件；生成链已由 R3 c943414 在页签壳验证）。预设标签表收敛
// 为顶层 [audioEqualizerPresetLabels]（menuTabLabels 同款约定：下拉与
// l10n 链测试共用单一来源）；频点数值与 Hz/dB 是通用记号，不进 arb。
// [music] 注入参数只服务测试：生产路径保持 MediaStores 单例（测试直建
// store 的约定见 media_stores.dart 头注释）。
import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/music_controller.dart';

/// 10 个固定频点的短标签（31.25 Hz .. 16 kHz）。
const List<String> _bandLabels = <String>[
  '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k', //
];

/// 预设下拉的标签表：键 = settings.json `music.equalizerPreset` 的持久化
/// 值（对齐 music/equalizer.dart 的 kPresetNames），值 = 当前语言显示名。
Map<String, String> audioEqualizerPresetLabels(AppLocalizations l10n) =>
    <String, String>{
      'flat': l10n.presetFlat,
      'bass': l10n.presetBass,
      'vocal': l10n.presetVocal,
      'live': l10n.presetLive,
    };

class AudioSettingsPage extends StatelessWidget {
  const AudioSettingsPage({super.key, this.music});

  /// 生产路径取 MediaStores 单例；测试注入裸 MusicController()（无
  /// settings、无 player：均衡器改动只留内存，见 music_controller.dart
  /// 构造器注释；af 写入在未挂 player 时是带守卫的 no-op）。
  final MusicController? music;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = music ?? MediaStores.instance.music;
    return SettingsDetailScaffold(
      title: Text(l10n.audioTitle),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final gains = controller.equalizerGains;
          return SettingsList(
            sections: [
              SettingsSection(
                title: Text(l10n.equalizerSection),
                bottomInfo: Text(controller.equalizerEnabled
                    ? l10n.equalizerEnabledInfo
                    : l10n.equalizerDisabledInfo),
                tiles: [
                  SettingsTile.switchTile(
                    leading: Icons.equalizer_rounded,
                    title: Text(l10n.equalizerEnableTitle),
                    description: Text(l10n.equalizerEnableDescription),
                    initialValue: controller.equalizerEnabled,
                    onToggle: (value) => controller.setEqualizerEnabled(
                        value ?? !controller.equalizerEnabled),
                  ),
                  SettingsDropdownTile<String>(
                    leading: Icons.tune_rounded,
                    title: Text(l10n.equalizerPresetTitle),
                    description: Text(controller.equalizerPreset == 'custom'
                        ? l10n.equalizerPresetCustomInfo
                        : l10n.equalizerPresetPickInfo),
                    value: kPresetNames.contains(controller.equalizerPreset)
                        ? controller.equalizerPreset
                        : 'flat',
                    options: audioEqualizerPresetLabels(l10n),
                    enabled: controller.equalizerEnabled,
                    onChanged: (preset) =>
                        controller.applyEqualizerPreset(preset),
                  ),
                ],
              ),
              SettingsSection(
                title: Text(l10n.equalizerGainSection),
                tiles: [
                  for (var band = 0; band < MusicController.bandCount; ++band)
                    IgnorePointer(
                      ignoring: !controller.equalizerEnabled,
                      child: Opacity(
                        opacity: controller.equalizerEnabled ? 1.0 : 0.5,
                        child: SettingsSliderTile(
                          leading: Icons.graphic_eq_rounded,
                          title: Text('${_bandLabels[band]} Hz'),
                          value: (gains.length > band ? gains[band] : 0.0)
                              .clamp(-MusicController.maxGain,
                                  MusicController.maxGain),
                          min: -MusicController.maxGain,
                          max: MusicController.maxGain,
                          divisions: (MusicController.maxGain * 2).round(),
                          valueLabel:
                              '${gains.length > band ? gains[band].round() : 0} dB',
                          onChanged: (value) =>
                              controller.setEqualizerBand(band, value),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
