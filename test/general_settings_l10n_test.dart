// Localization-chain test for the third settings page migrated to
// AppLocalizations: the general settings page
// (lib/pages/settings/general_settings.dart) — plus the restore-defaults
// control (施工件 B), the UI slot of 1.x SettingsService::restoreDefaults.
//
// Same chain as audio_settings_l10n_test.dart (R4) but one step further:
// GeneralSettingsPage has no injectable dependency, so this mounts the REAL
// page on the MediaStores-under-fake-path-provider bootstrap
// (kazumi_alignment_ui_test.dart / music_lyrics_page_test.dart pattern —
// QStandardPaths::setTestModeEnabled equivalent, no user data touched, no
// network). The GStorage box opens under the temporary root like main().
//
// Locked here, per locale (zh = the SPEC §1 default, en = the reserved
// second locale):
// - app bar title / section titles / tile titles + descriptions / dropdown
//   option labels (tab keys reused as the startup-page option names)
// - the scan-depth value label ('2 层' / '2 levels' — the 层数 unit comes
//   from the arb, the number is interpolated)
// - the restore flow: tap the「恢复默认设置」tile → EmoDialog danger confirm
//   (error-colored FilledButton) → cancel keeps everything → confirm resets
//   the quality/behavior/music sections and the page + session controllers
//   show the defaults immediately (the "相关设置页即时刷新" contract: the
//   MobX mirrors re-sync through reloadFromSettings)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/bean/settings/settings_detail_scaffold.dart';
import 'package:emoplay/l10n/generated/app_localizations.dart';
import 'package:emoplay/l10n/generated/app_localizations_en.dart';
import 'package:emoplay/l10n/generated/app_localizations_zh.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/settings/general_settings.dart';
import 'package:emoplay/services/storage/storage.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Widget _harness(Locale locale) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      // Embedded pane scope: this is how the page renders inside the wide
      // settings shell (SettingsDetailScaffold then picks the plain AppBar;
      // the SysAppBar fallback reads GStorage, which the bootstrap below
      // initializes against the temporary root).
      home: SettingsPaneScope(
        embedded: true,
        showBackButton: false,
        onBack: () {},
        child: const GeneralSettingsPage(),
      ),
    );

/// Mutates the persisted sections + the session controllers into
/// non-default states BEFORE the page mounts, the way a returning user's
/// settings.json would look. Quality tier/contentMode go through the store
/// directly (driving the controller setters would run the engine apply path
/// without an engine); interpolation/ICC/equalizer go through their
/// controllers' own setters — all engine-guarded no-ops headless — so the
/// restore step can prove a REAL observable transition (true→false).
Future<void> _mutateToNonDefaults() async {
  final stores = MediaStores.instance;
  final settings = stores.settings;
  settings.qualityTier = 'high';
  settings.qualityContentMode = 'anime';
  settings.resumeOnReopen = false;
  settings.libraryMaxDepth = 5;
  settings.librarySkipHidden = false;
  stores.quality.interpolation.setEnabled(true);
  stores.quality.icc.setEnabled(true);
  await stores.music.setEqualizerEnabled(true);
  expect(settings.save(), isTrue);
}

/// Pumps the page on a tall headless viewport: SettingsList is a lazy
/// ListView.builder, so the default test surface never builds the
/// bottom「恢复」section (audio test's scrollUntilVisible alternative —
/// this page is small enough to build whole).
Future<void> _pumpPage(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(1000, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(locale));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay_general_l10n_');
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

  testWidgets('generalSettingsRendersZh', (tester) async {
    await _mutateToNonDefaults();
    await _pumpPage(tester, const Locale('zh'));

    // Page title + section titles.
    expect(find.text('常规'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);
    expect(find.text('媒体库扫描'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    // Desktop-only window-behavior section (isDesktop() on the test host).
    expect(find.text('窗口行为'), findsOneWidget);
    expect(find.text('关闭窗口时'), findsOneWidget);
    // Default exit behavior (SettingsKeys.exitBehavior default = 2).
    expect(find.text('每次都询问'), findsOneWidget);
    // Startup-page dropdown shows the persisted route's tab label.
    expect(find.text('首页'), findsOneWidget);

    // Behavior tiles show the mutated values (page reads the live store).
    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('扫描深度'), findsOneWidget);
    expect(find.text('5 层'), findsOneWidget);
    expect(find.text('跳过隐藏文件'), findsOneWidget);

    // Restore slot (施工件 B).
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('恢复默认设置'), findsOneWidget);
    expect(find.text('将画质、常规与音频偏好重置为默认值'), findsOneWidget);
  });

  testWidgets('restoreDefaultsDialogCancelKeepsEverything', (tester) async {
    await _mutateToNonDefaults();
    await _pumpPage(tester, const Locale('zh'));

    await tester.tap(find.text('恢复默认设置'));
    await tester.pumpAndSettle();

    // Danger confirm dialog: title/body/cancel/error-colored confirm.
    expect(find.text('恢复默认设置？'), findsOneWidget);
    expect(
        find.text('画质、常规（继续播放与扫描参数）与音频均衡器将回到默认值。'
            '媒体库与观看历史不会删除；mpv 配置导入决策不受影响。'),
        findsOneWidget);
    final titleContext = tester.element(find.text('恢复默认设置？'));
    final errorColor = Theme.of(titleContext).colorScheme.error;
    final confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '恢复默认'));
    expect(confirmButton.style?.backgroundColor?.resolve({}), errorColor);

    // Cancel: nothing changes — the store and the page keep the values.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final settings = MediaStores.instance.settings;
    expect(settings.qualityTier, 'high');
    expect(settings.libraryMaxDepth, 5);
    expect(find.text('5 层'), findsOneWidget);
  });

  testWidgets('restoreDefaultsDialogConfirmResetsSectionsAndRefreshes',
      (tester) async {
    await _mutateToNonDefaults();
    await _pumpPage(tester, const Locale('zh'));
    expect(find.text('5 层'), findsOneWidget);

    await tester.tap(find.text('恢复默认设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复默认'));
    await tester.pumpAndSettle();

    // Store: the three sections are back at their defaults.
    final settings = MediaStores.instance.settings;
    expect(settings.resumeOnReopen, isTrue);
    expect(settings.libraryMaxDepth, 2);
    expect(settings.librarySkipHidden, isTrue);
    expect(settings.qualityContentMode, 'auto');
    expect(settings.qualityTier, 'off');
    expect(settings.musicEqualizerEnabled, isFalse);
    expect(settings.musicEqualizerPreset, 'flat');

    // The page itself refreshed immediately — no restart needed.
    expect(find.text('2 层'), findsOneWidget);
    expect(find.text('5 层'), findsNothing);

    // The session controllers re-synced through reloadFromSettings: the
    // quality / audio pages (mounted elsewhere) show defaults too, and the
    // toggled controllers actually flipped (real transitions, not
    // coincidental defaults).
    final stores = MediaStores.instance;
    expect(stores.quality.interpolation.enabled, isFalse);
    expect(stores.quality.icc.enabled, isFalse);
    expect(stores.music.equalizerEnabled, isFalse);
    expect(stores.music.equalizerPreset, 'flat');

    // Success toast.
    expect(find.text('已恢复默认设置'), findsOneWidget);
  });

  testWidgets('generalSettingsRendersEn', (tester) async {
    await _pumpPage(tester, const Locale('en'));

    // The reserved en locale must serve the en arb values, not zh fallbacks.
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Startup'), findsOneWidget);
    expect(find.text('Scan depth'), findsOneWidget);
    expect(find.text('2 levels'), findsOneWidget);
    expect(find.text('Restore default settings'), findsOneWidget);
    expect(find.text('Window behavior'), findsOneWidget);
    expect(find.text('常规'), findsNothing);
    expect(find.text('继续播放'), findsNothing);
    expect(find.text('恢复默认设置'), findsNothing);
  });

  test('scanDepthLayersPlaceholderRendersBothLocales', () {
    // The interpolated unit label: the arb placeholder carries the number
    // (audioEqualizerPresetLabels 单一来源测试的同款直取约定).
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();
    expect(zh.scanDepthLayers(3), '3 层');
    expect(zh.scanDepthUnlimited, '不限');
    expect(en.scanDepthLayers(3), '3 levels');
    expect(en.scanDepthUnlimited, 'Unlimited');
  });
}
