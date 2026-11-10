// R6 UI-polish guard tests: the style-layer details aligned with
// Kazumi@7265274 must stay aligned. These mount the real pages headless
// (same MediaStores-under-fake-path-provider bootstrap as
// music_lyrics_page_test.dart — no user data touched, no network).
//
// Locked invariants:
//   1. The About page's "GPL-3.0 许可证" tile opens THIS project's LICENSE
//      (Kazumi's own about tile points at its own repository; the import
//      briefly pointed at Kazumi's LICENSE instead).
//   2. GeneralEmptyState action buttons use the Kazumi StateActionButton
//      idiom (lib/bean/widget/state_presentation.dart, ported verbatim)
//      instead of raw FilledButtons — home (recent plays) and library
//      (empty index) are the two pages mountable without libmpv/network;
//      the player tab uses the same idiom and is covered by analyze-only.
//
// The plugins-page badge/hint recolors stay on theme colorScheme pairs by
// construction (no hardcoded Color() left in that file); they are asserted
// statically in CI by the hardcoded-color grep, not here — mounting
// PluginsPage would fire a real manifest fetch (no injectable fetcher on
// the page path) and the suite keeps tests network-free.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:emoplay/bean/widget/state_presentation.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/about/about_page.dart';
import 'package:emoplay/pages/home/home_page.dart';
import 'package:emoplay/pages/library/library_page.dart';
import 'package:emoplay/services/storage/storage.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay_ui_alignment_');
    // QStandardPaths::setTestModeEnabled equivalent: everything
    // MediaStores.init() builds lands under the temporary directory.
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await _initStoresForTests();
    // The About page's SysAppBar resolves DesktopWindowConfig.showWindowButton
    // (a lazily-evaluated static over GStorage); mirror main.dart's Hive
    // bootstrap so the box opens under the temp root, never the user's data.
    await Hive.initFlutter('${tempDir.path}/hive');
    await GStorage.init();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('aboutLicenseTileOpensEmoPlayLicense', (tester) async {
    final launcher = _RecordingUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('GPL-3.0 许可证'));
    // openAboutLink is fire-and-forget from the gesture handler; flush the
    // async gap before reading the recorded launch.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(launcher.launched, [
      'https://github.com/emoeem/emoplay/blob/main/LICENSE',
    ]);
  });

  testWidgets('homeEmptyStateUsesKazumiStateActionButton', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The "recent plays" empty state keeps its copy and now carries the
    // Kazumi 48px pill action instead of a raw FilledButton.
    expect(find.text('播放过的媒体会出现在这里'), findsOneWidget);
    final action = tester.widget<StateActionButton>(
      find.byType(StateActionButton),
    );
    expect(action.text, '选择媒体文件');
    _expectKazumiPillStyle(tester);
  });

  testWidgets('libraryEmptyStateUsesKazumiStateActionButton', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Desktop headless: no directories and no phone scanner, so the single
    // action is "添加媒体文件夹" in the StateActionButton idiom.
    expect(find.text('媒体库还是空的'), findsOneWidget);
    final action = tester.widget<StateActionButton>(
      find.byType(StateActionButton),
    );
    expect(action.text, '添加媒体文件夹');
    _expectKazumiPillStyle(tester);
  });
}

/// StateActionButton.styleOf signature: a 64×48 pill (Kazumi's empty-state
/// button), distinguishable from a raw M3 FilledButton (default 40px height,
/// null style). The home page header intentionally keeps raw quick-action
/// buttons — only the empty-state actions adopt the idiom.
void _expectKazumiPillStyle(WidgetTester tester) {
  final inner = tester.widget<FilledButton>(
    find
        .descendant(
          of: find.byType(StateActionButton),
          matching: find.byType(FilledButton),
        )
        .first,
  );
  expect(inner.style?.minimumSize?.resolve({}), const Size(64, 48));
  expect(inner.style?.padding?.resolve({}),
      const EdgeInsets.symmetric(horizontal: 24, vertical: 12));
}

/// MediaStores.init() must complete before any page mounts; the async work
/// (file IO inside plugin/compat setup) needs runAsync outside the test
/// fake-async zone, exactly like music_lyrics_page_test.dart.
Future<void> _initStoresForTests() async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  await binding.runAsync(() async {
    await MediaStores.init();
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Records external launches instead of touching the host (the suite runs
/// with no desktop portal available).
class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}
