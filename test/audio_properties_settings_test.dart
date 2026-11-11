// M5-T2 音频属性（replaygain）设置动线的整链 widget 用例：音频页瓦片 →
// EmoPlaySettings.audioReplaygain（settings.json `audio` 段）→
// MediaStores.rebuildStartupMpvProperties（审计表与后续 Player 的预置重
// 排）→ MpvPlayerProperties.replaygainMpvValue 的 mpv 词汇（off/track/
// album → no/track/album）。
//
// 挂 REAL MediaStores（general_settings_l10n_test.dart 的假
// path_provider 先例：MediaStores.init 全部落进临时根；无 mpv 导入决策
// 时 compat 选项为空表，预置=纯 EmoPlay 默认 + 重定向 + M5-T2 音频属
// 性）。对存活 Player 的即时下发半在无 player 时是带守卫的 no-op（页面
// 处理器读 diagnosticsPlayer 为 null 直接跳过），live-libmpv 半在
// mpv_player_properties_test.dart 的 audioProperties 用例。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/mpv/config/mpv_player_properties.dart';
import 'package:emoplay/pages/settings/audio_settings.dart';
import 'package:emoplay/services/storage/storage.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Widget _harness() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      // Embedded pane scope: this is how the page renders inside the wide
      // settings shell (SettingsDetailScaffold then picks the plain AppBar).
      home: SettingsPaneScope(
        embedded: true,
        showBackButton: false,
        onBack: () {},
        child: const AudioSettingsPage(),
      ),
    );

Future<void> _pumpPage(WidgetTester tester) async {
  // Tall headless viewport: the audio page stacks the EQ sections above the
  // M5-T2「音频属性」section (lazy ListView.builder — must be built to be
  // findable).
  tester.view.physicalSize = const Size(1000, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness());
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay_audio_props_');
    // QStandardPaths::setTestModeEnabled equivalent: everything
    // MediaStores.init() builds lands under the temporary directory.
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });
    // Mirror main.dart's Hive bootstrap so the GStorage box opens under the
    // temp root, never the user's data.
    await Hive.initFlutter('${tempDir.path}/hive');
    await GStorage.init();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  tearDown(() async {
    // Leave the stores at their defaults for the next case.
    MediaStores.instance.settings.restoreDefaults();
    MediaStores.instance.settings.save();
  });

  Future<void> pickReplaygain(WidgetTester tester, String label) async {
    await tester.tap(find.text('ReplayGain 响度均衡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('replaygainTilePersistsAndRebuildsStartupPreset',
      (tester) async {
    await _pumpPage(tester);

    // New section renders on the production path (settings from
    // MediaStores) with the 1.x-status-quo default 'off' → '关闭'.
    expect(find.text('音频属性'), findsOneWidget);
    expect(find.text('ReplayGain 响度均衡'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    final settings = MediaStores.instance.settings;
    Map<String, String> preset() => MediaStores.instance.startupMpvProperties;
    expect(preset()['replaygain'], 'no');
    expect(preset()['gapless-audio'], 'weak');

    // Tap through the dropdown: off → track. The tile must persist the
    // settings key AND rebuild the startup preset in the same gesture.
    await pickReplaygain(tester, '按音轨');
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainTrack);
    expect(find.text('按音轨'), findsOneWidget);
    final json = File(settings.filePath).readAsStringSync();
    expect(json, contains('"replaygain": "track"'));
    expect(preset()['replaygain'], 'track');

    // track → album → off: the full three-state vocabulary round-trips
    // through the tile, each state landing in the store, the file and the
    // preset with its mpv-side value.
    await pickReplaygain(tester, '按专辑');
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainAlbum);
    expect(
        File(settings.filePath).readAsStringSync(),
        contains('"replaygain": "album"'));
    expect(preset()['replaygain'], 'album');

    await pickReplaygain(tester, '关闭');
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainOff);
    expect(preset()['replaygain'], 'no');
    // gapless pin untouched by the round-trip (注释与行为一致的另一面).
    expect(preset()['gapless-audio'], 'weak');
  });

  testWidgets('replaygainTileSurvivesUnknownStorageValueViaGuard',
      (tester) async {
    // 守卫链的页面侧见证：手改 settings.json 塞进未知词汇后重新加载，页面
    // 以回落后的 '关闭' 渲染，预置仍钉 'no'（MpvPlayerProperties
    // .replaygainValues 白名单契约；臆测一个增益档比拒绝更危险）。
    final settings = MediaStores.instance.settings;
    File(settings.filePath).writeAsStringSync('''
{
    "audio": {"replaygain": "bogus-gain"}
}
''');
    expect(settings.load(), isTrue);
    expect(settings.audioReplaygain, MpvPlayerProperties.replaygainOff);
    settings.save();

    await _pumpPage(tester);
    expect(find.text('关闭'), findsOneWidget);
    expect(MediaStores.instance.startupMpvProperties['replaygain'], 'no');
  });
}
