// Localization-chain test for the second page migrated to AppLocalizations:
// the audio settings page (lib/pages/settings/audio_settings.dart) — R4
// round, the execution slice of R3 建议 3 ("从设置页挑一类把字符串换成
// AppLocalizations 取用").
//
// R3 `c943414` proved the arb → gen-l10n → page chain on the tab shell
// (test/menu_l10n_test.dart). This test re-proves the chain on a settings
// page and goes one step further: AudioSettingsPage takes an injectable
// MusicController, so the REAL page mounts here — no MediaStores.init, no
// route tree, no platform channels (MusicController() without settings
// keeps every mutation in memory per its constructor doc, and the af write
// is a guarded no-op without an attached player).
//
// Locked here, per locale (zh = the SPEC §1 default, en = the reserved
// second locale):
// - app bar title / section titles / tile titles + descriptions
// - the equalizer-off bottom info, flipping live to the on-info after
//   toggling the enable tile (row tap → onToggle(null) → setEqualizerEnabled)
// - the preset dropdown's single-source label map audioEqualizerPresetLabels
// - the ten universal-unit band rows ('31 Hz'..'16k Hz', scrolled into view
//   because SettingsList is a lazy ListView.builder)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/l10n/generated/app_localizations_en.dart';
import 'package:emoplay/l10n/generated/app_localizations_zh.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/music/music_controller.dart';
import 'package:emoplay/pages/settings/audio_settings.dart';

Widget _harness(Locale locale, MusicController music) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      // Embedded pane scope: this is how the page renders inside the wide
      // settings shell (SettingsDetailScaffold then picks the plain AppBar;
      // the SysAppBar fallback reads GStorage, which only exists after
      // main()'s init and stays out of scope for an l10n chain test).
      home: SettingsPaneScope(
        embedded: true,
        showBackButton: false,
        onBack: () {},
        child: AudioSettingsPage(music: music),
      ),
    );

void main() {
  testWidgets('audioSettingsRendersZhAndTogglesInfo', (tester) async {
    final music = MusicController();
    await tester.pumpWidget(_harness(const Locale('zh'), music));
    await tester.pumpAndSettle();

    // Off state — a fresh controller has equalizerEnabled == false, so the
    // disabled info is what the page shows.
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('均衡器'), findsOneWidget);
    expect(find.text('启用均衡器'), findsOneWidget);
    expect(find.text('10 段 ISO 倍频程均衡，写入 mpv af 链'), findsOneWidget);
    expect(find.text('预设'), findsOneWidget);
    expect(find.text('已停用 — mpv 音频滤镜链保持不动'), findsOneWidget);

    // Toggle via the row tap path (onToggle(null) → !equalizerEnabled):
    // the footer must flip live to the applied-info string.
    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    expect(find.text('已应用于 mpv 音频滤镜链（整链写入；关闭时恢复变速基线）'),
        findsOneWidget);
    expect(music.equalizerEnabled, isTrue);
  });

  testWidgets('audioSettingsBandRowsReachAllTenBands', (tester) async {
    await tester.pumpWidget(
        _harness(const Locale('zh'), MusicController()));
    await tester.pumpAndSettle();

    // Lazy list: drag until the last band row is built, then assert every
    // band row rendered (Hz is a universal unit and stays out of the arb).
    const bands = <String>[
      '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
    ];
    await tester.scrollUntilVisible(
      find.text('16k Hz'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final band in bands) {
      expect(find.text('$band Hz'), findsOneWidget,
          reason: 'missing band row: $band');
    }
    // Group title for the gain sliders.
    expect(find.text('频段增益（dB）'), findsOneWidget);
  });

  testWidgets('audioSettingsRendersEn', (tester) async {
    await tester.pumpWidget(
        _harness(const Locale('en'), MusicController()));
    await tester.pumpAndSettle();

    // The reserved en locale must serve the en arb values, not zh fallbacks.
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Enable equalizer'), findsOneWidget);
    expect(find.text('Disabled — the mpv audio filter chain is left untouched'),
        findsOneWidget);
    expect(find.text('音频'), findsNothing);
    expect(find.text('均衡器'), findsNothing);
  });

  test('presetLabelMapCoversBuiltinNamesBothLocales', () {
    // The dropdown and this assertion share audioEqualizerPresetLabels as a
    // single source; keys must stay aligned with the persisted
    // settings.json music.equalizerPreset vocabulary (flat/bass/vocal/live;
    // 'custom' never appears as a pickable option).
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();
    final zhLabels = audioEqualizerPresetLabels(zh);
    final enLabels = audioEqualizerPresetLabels(en);
    expect(zhLabels.keys.toList(), <String>['flat', 'bass', 'vocal', 'live']);
    expect(enLabels.keys.toList(), zhLabels.keys.toList());
    expect(zhLabels['flat'], '平坦');
    expect(zhLabels['bass'], '低音增强');
    expect(zhLabels['vocal'], '人声');
    expect(zhLabels['live'], '现场');
    expect(enLabels['flat'], 'Flat');
    expect(enLabels['bass'], 'Bass boost');
    expect(enLabels['vocal'], 'Vocal');
    expect(enLabels['live'], 'Live');
  });

  test('replaygainLabelMapCoversPersistedVocabularyBothLocales', () {
    // M5-T2 replaygain 下拉与该断言共用 audioReplaygainLabels 单一来源；
    // 键集必须与 settings.json audio.replaygain 的持久化词汇（即
    // MpvPlayerProperties.replaygainValues，off/track/album）对齐，并与
    // build() 预置里 replaygainMpvValue 的映射（off→no）语义一致。
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();
    final zhLabels = audioReplaygainLabels(zh);
    final enLabels = audioReplaygainLabels(en);
    expect(zhLabels.keys.toList(), MpvPlayerProperties.replaygainValues);
    expect(enLabels.keys.toList(), zhLabels.keys.toList());
    expect(zhLabels['off'], '关闭');
    expect(zhLabels['track'], '按音轨');
    expect(zhLabels['album'], '按专辑');
    expect(enLabels['off'], 'Off');
    expect(enLabels['track'], 'Per track');
    expect(enLabels['album'], 'Per album');
  });
}
