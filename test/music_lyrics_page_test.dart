// Headless instantiation test for the music-mode overlay page
// (lib/pages/player/music_lyrics_page.dart) — case-for-case port of
// mpv-emo tests/test_music_page.cpp (pageInstantiates).
//
// 1.x mounted qml/MusicPage.qml offscreen with a null-engine controller and
// asserted: creation without QML errors, one slider per equalizer band, the
// mounted switch mirroring the persisted enabled state, and the panel
// starting collapsed. 2.0 mounts the real widget against the global
// MediaStores under a fake path provider (no real user data touched); the
// band sliders live inside the collapsible equalizer panel, so the slider
// count is asserted after exposing it (1.x asserted eqPanelVisible's
// collapsed default the same way).
//
// M5-T3 additions (docs/EMOPLAY-3.0-ROADMAP.md §五): timestamp-driven
// highlight positioning, the bilingual translation rows and the no-lyrics
// graceful degradation. Lyrics are seeded through MusicController's
// @visibleForTesting debugSeedLyrics — the same exposed shape attachPlayer +
// _loadLyrics + _onPositionChanged produce, because flutter_test has no
// libmpv to drive the real path (same note as below: pure UI logic beyond
// creation stays runtime-verifiable on a real machine).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/music/lrc_parser.dart';
import 'package:emoplay/music/music_controller.dart';
import 'package:emoplay/pages/player/music_lyrics_page.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay_music_page_');
    // QStandardPaths::setTestModeEnabled equivalent: everything
    // MediaStores.init() builds lands under the temporary directory.
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Boots the page with the given lyrics seeded at [index] (MediaStores is
  /// a process-wide singleton; init() re-runs are no-ops).
  Future<void> pumpPage(
    WidgetTester tester, {
    List<LrcLine> lines = const <LrcLine>[],
    int index = -1,
  }) async {
    await tester.runAsync(() async {
      await MediaStores.init();
      final music = MediaStores.instance.music;
      // The overlay only renders its content in audio mode (1.x showed the
      // page outright; 2.0 overlays the video surface).
      music.setAudioMode(true);
      music.debugSeedLyrics(lines: lines, index: index);
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MusicLyricsPage()),
    ));
    await tester.pumpAndSettle();
  }

  TextStyle styleOf(WidgetTester tester, Finder finder) =>
      DefaultTextStyle.of(tester.element(finder)).style;

  testWidgets('pageInstantiates', (tester) async {
    // 1.x seeded the persisted enabled EQ before creating the page; the
    // controller must come up with the switch already on.
    await tester.runAsync(() async {
      await MediaStores.init();
      final music = MediaStores.instance.music;
      await music.setEqualizerEnabled(true);
      // The overlay only renders its content in audio mode (1.x showed the
      // page outright; 2.0 overlays the video surface).
      music.setAudioMode(true);
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MusicLyricsPage()),
    ));
    await tester.pumpAndSettle();
    // Creation without errors (1.x: component.create() non-null, no QML
    // warnings — a half-created page would surface here).
    expect(tester.takeException(), isNull);
    // The page actually built (header, not the collapsed overlay).
    expect(find.text('Music'), findsOneWidget);

    // Collapsed by default; exposing it again must not error out.
    expect(find.byType(Slider), findsNothing);
    // The overlay's full-surface GestureDetector registers onDoubleTap (1.x
    // MouseArea absorbed clicks), so the button's single tap only wins the
    // gesture arena once the double-tap window has elapsed — advance the
    // fake clock past it before settling.
    await tester.tap(find.text('均衡器'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The equalizer row builds one slider per band.
    expect(find.byType(Slider), findsNWidgets(MusicController.bandCount));
    // The mounted switch mirrors the persisted enabled state (no
    // declarative binding on checked; the imperative sync provides the
    // initial value).
    final eqSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(eqSwitch.value, isTrue);
  });

  testWidgets('lyricsFollowPositionedByTimestamp', (tester) async {
    // 20 timestamped lines (200 px per 5 lines of content, more than the
    // viewport) with playback at line 10: the list must have scrolled so the
    // active line sits at the viewport centre — positioning driven purely by
    // the .lrc timestamps the controller derives lyricIndex from.
    await pumpPage(
      tester,
      index: 10,
      lines: [
        for (var i = 0; i < 20; ++i)
          LrcLine(time: i * 5.0, text: 'Line $i'),
      ],
    );
    expect(tester.takeException(), isNull);

    final listRect = tester.getRect(find.byType(ListView));
    final activeCenter = tester.getCenter(find.text('Line 10'));
    expect(
      (activeCenter.dy - listRect.center.dy).abs(),
      lessThanOrEqualTo(4.0),
      reason: 'the line the .lrc timestamps select must be centred',
    );

    // The active line is the visually highlighted one (bigger than its
    // neighbours), so the scroll lands on the right row.
    expect(styleOf(tester, find.text('Line 10')).fontSize, 22);
    expect(styleOf(tester, find.text('Line 9')).fontSize, 16);
    expect(styleOf(tester, find.text('Line 11')).fontSize, 16);
  });

  testWidgets('translationRowsRenderBilingually', (tester) async {
    // Bilingual .lrc convention (music_lyrics_page.dart header): adjacent
    // entries sharing one timestamp group into original + translation. The
    // active pair renders both, the translation in its own dimmer style; the
    // inactive pair renders both too.
    await pumpPage(
      tester,
      index: 0,
      lines: const [
        LrcLine(time: 10.0, text: 'Hello world'),
        LrcLine(time: 10.0, text: '你好，世界'),
        LrcLine(time: 20.0, text: 'Second line'),
        LrcLine(time: 20.0, text: '第二行'),
      ],
    );
    expect(tester.takeException(), isNull);

    // Both languages of the active pair render (bilingual layout).
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('你好，世界'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(find.text('第二行'), findsOneWidget);

    // Active original keeps the highlight style; its translation uses the
    // dedicated translation style (smaller, softer blue).
    expect(styleOf(tester, find.text('Hello world')).fontSize, 22);
    final activeTranslation = styleOf(tester, find.text('你好，世界'));
    expect(activeTranslation.fontSize, 14);
    expect(activeTranslation.color, const Color(0xFF8fb3ff));

    // Inactive translation: smaller and dimmer than the active one.
    final idleTranslation = styleOf(tester, find.text('第二行'));
    expect(idleTranslation.fontSize, 12);
    expect(idleTranslation.color, const Color(0xFF585862));
  });

  testWidgets('emptyLyricsDegradeGracefully', (tester) async {
    // No .lrc resolved: the page keeps its header/EQ chrome and shows the
    // placement hint instead of an empty list or an error.
    await pumpPage(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Music'), findsOneWidget);
    expect(
      find.text('未找到歌词 — 请在音频文件旁放置同名 .lrc 文件'),
      findsOneWidget,
    );
    // No lyric list is mounted for the empty case.
    expect(find.byType(ListView), findsNothing);
    // The rest of the page stays usable (EQ panel still opens).
    await tester.tap(find.text('均衡器'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsNWidgets(MusicController.bandCount));
  });
}

/// QStandardPaths::setTestModeEnabled equivalent: redirects the
/// application-support resolution used by MediaStores.init().
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
