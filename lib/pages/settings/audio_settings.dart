// 设置中心「音频」分类页 (SPEC §6 category 4)：EQ 开关、预设、10 段增益
// 滑块（M7 音乐层 MusicController，每次改动既持久化 settings.json 的
// music 段也实时重挂 mpv af 链，1.x MusicController 契约）；M5-T2 起
// 增加「音频属性」分组：replaygain 三态开关（settings.json `audio`
// 段）。链式考证见 music/equalizer.dart 文件头与
// mpv/config/mpv_player_properties.dart 的 M5-T2 考证块。
//
// replaygain 瓦片与 EQ 的写法差异：EQ 的状态/下发都在 MusicController
// 上，而 replaygain 是全局播放属性——持久化在 settings.json 的 audio
// 段，下发走 MpvPlayerProperties 通道：切换时 save() → 重排启动预置
// （MediaStores.rebuildStartupMpvProperties，审计表与后续每个 Player
// 生效）→ 对存活的当前 Player 经 applyReplaygain 即时下发（M5-T1
// applyPlaylistMode 的双动线同款）。[settings] 注入参数只服务测试，与
// [music] 同款：生产路径保持 MediaStores 单例；两者皆缺（l10n 链测试
// 的裸 MusicController 路径）时音频属性瓦片以默认值渲染、切换为带守卫
// 的 no-op。
//
// R4 i18n：第二个迁移到 AppLocalizations 的页面（R3 建议 3「从设置页挑
// 一类」的执行件；生成链已由 R3 c943414 在页签壳验证）。预设标签表收敛
// 为顶层 [audioEqualizerPresetLabels]（menuTabLabels 同款约定：下拉与
// l10n 链测试共用单一来源）；频点数值与 Hz/dB 是通用记号，不进 arb。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:emoplay/bean/dialog/dialog_helper.dart';
import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/bean/settings/settings_dropdown_tile.dart';
import 'package:emoplay/bean/settings/settings_list.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/music/equalizer.dart';
import 'package:emoplay/music/music_controller.dart';
import 'package:emoplay/settings/emoplay_settings.dart';

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

/// replaygain 下拉的标签表：键 = settings.json `audio.replaygain` 的持久
/// 化值（MpvPlayerProperties.replaygainValues 单一来源），值 = 当前语言
/// 显示名。
Map<String, String> audioReplaygainLabels(AppLocalizations l10n) =>
    <String, String>{
      MpvPlayerProperties.replaygainOff: l10n.replaygainOff,
      MpvPlayerProperties.replaygainTrack: l10n.replaygainTrack,
      MpvPlayerProperties.replaygainAlbum: l10n.replaygainAlbum,
    };

class AudioSettingsPage extends StatelessWidget {
  const AudioSettingsPage({super.key, this.music, this.settings});

  /// 生产路径取 MediaStores 单例；测试注入裸 MusicController()（无
  /// settings、无 player：均衡器改动只留内存，见 music_controller.dart
  /// 构造器注释；af 写入在未挂 player 时是带守卫的 no-op）。
  final MusicController? music;

  /// M5-T2 测试注入位（与 [music] 同款约定）：音频属性段的状态源。缺省时
  /// 生产路径取 MediaStores.instance.settings；MediaStores 未就绪（l10n
  /// 链测试）为 null，音频属性瓦片以默认值渲染、切换 no-op。
  final EmoPlaySettings? settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = music ?? MediaStores.instance.music;
    final audioSettings = settings ??
        (MediaStores.isReady ? MediaStores.instance.settings : null);
    return SettingsDetailScaffold(
      title: Text(l10n.audioTitle),
      body: ListenableBuilder(
        // replaygain 状态在 EmoPlaySettings（ChangeNotifier）上，EQ 状态在
        // MusicController 上——两路通知都驱动重建（Listenable.merge）。
        listenable: Listenable.merge([
          controller,
          ?audioSettings,
        ]),
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
              SettingsSection(
                title: Text(l10n.audioPropertiesSection),
                tiles: [
                  // M5-T2 replaygain 三态开关（mpv replaygain 属性，off/
                  // track/album → no/track/album 映射与考证见
                  // mpv_player_properties.dart 文件头）。默认 off = 1.x
                  // 现状（mpv 默认 no，1.x 从未写过该属性）。
                  SettingsDropdownTile<String>(
                    leading: Icons.graphic_eq_rounded,
                    title: Text(l10n.audioReplaygainTitle),
                    description: Text(l10n.audioReplaygainDescription),
                    value: audioSettings?.audioReplaygain ??
                        MpvPlayerProperties.replaygainOff,
                    options: audioReplaygainLabels(l10n),
                    onChanged: (value) => _applyReplaygainChange(
                        context, audioSettings, value),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // M5-T2 replaygain 切换动线（写法契约见页头注释）：先落盘，再重排预置
  // （rebuildStartupMpvProperties 内部的 compat.startupOptions() 会重读
  // settings.json，顺序不能反），最后对存活的当前 Player 即时下发。三者
  // 失败都不阻塞：save 失败照 M5-T1 player_settings 先例弹 toast；下发
  // 失败由 apply 通道逐键记日志。
  void _applyReplaygainChange(
    BuildContext context,
    EmoPlaySettings? audioSettings,
    String value,
  ) {
    if (audioSettings == null) {
      return; // 裸控制器测试路径：无 settings 可写（页头注释约定）。
    }
    audioSettings.audioReplaygain = value;
    if (!audioSettings.save()) {
      // l10n 页面用既有 settingsSaveFailed 契约（player_settings.dart 的
      // 硬编码中文是 M5-T1 未 l10n 化页面，两条动线不可互相照抄）。
      EmoDialog.showToast(
        context: context,
        message: AppLocalizations.of(context).settingsSaveFailed,
      );
    }
    if (!MediaStores.isReady) {
      return;
    }
    MediaStores.instance.rebuildStartupMpvProperties();
    final player = MediaStores.instance.diagnosticsPlayer;
    final platform = player?.platform;
    if (platform is NativePlayer) {
      unawaited(
          MpvPlayerProperties.applyReplaygain(platform, value));
    }
  }
}
