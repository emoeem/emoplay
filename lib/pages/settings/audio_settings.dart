// 设置中心「音频」分类页 (SPEC §6 category 4)：EQ 开关、预设、10 段增益
// 滑块。驱动的是 M7 音乐层 MusicController（挂在当前播放器上的同一个实
// 例），每次改动既持久化 settings.json 的 music 段也实时重挂 mpv af 链
// （1.x MusicController 契约）。链式考证见 music/equalizer.dart 文件头。
import 'package:flutter/material.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/music_controller.dart';

/// 10 个固定频点的短标签（31.25 Hz .. 16 kHz）。
const List<String> _bandLabels = <String>[
  '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k', //
];

const Map<String, String> _presetLabels = <String, String>{
  'flat': '平坦',
  'bass': '低音增强',
  'vocal': '人声',
  'live': '现场',
};

class AudioSettingsPage extends StatelessWidget {
  const AudioSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final music = MediaStores.instance.music;
    return SettingsDetailScaffold(
      title: const Text('音频'),
      body: ListenableBuilder(
        listenable: music,
        builder: (context, _) {
          final gains = music.equalizerGains;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('均衡器'),
                bottomInfo: Text(music.equalizerEnabled
                    ? '已应用于 mpv 音频滤镜链（整链写入；关闭时恢复变速基线）'
                    : '已停用 — mpv 音频滤镜链保持不动'),
                tiles: [
                  SettingsTile.switchTile(
                    leading: Icons.equalizer_rounded,
                    title: const Text('启用均衡器'),
                    description: const Text('10 段 ISO 倍频程均衡，写入 mpv af 链'),
                    initialValue: music.equalizerEnabled,
                    onToggle: (value) =>
                        music.setEqualizerEnabled(value ?? !music.equalizerEnabled),
                  ),
                  SettingsDropdownTile<String>(
                    leading: Icons.tune_rounded,
                    title: const Text('预设'),
                    description: Text(music.equalizerPreset == 'custom'
                        ? '已手动调整 — 当前为自定义曲线'
                        : '选择一个内置曲线'),
                    value: kPresetNames.contains(music.equalizerPreset)
                        ? music.equalizerPreset
                        : 'flat',
                    options: _presetLabels,
                    enabled: music.equalizerEnabled,
                    onChanged: (preset) => music.applyEqualizerPreset(preset),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('频段增益（dB）'),
                tiles: [
                  for (var band = 0; band < MusicController.bandCount; ++band)
                    IgnorePointer(
                      ignoring: !music.equalizerEnabled,
                      child: Opacity(
                        opacity: music.equalizerEnabled ? 1.0 : 0.5,
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
                              music.setEqualizerBand(band, value),
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
