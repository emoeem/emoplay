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
// Pure UI logic beyond creation stays runtime-verifiable on a real machine
// (docs/architecture.md known limits — same note as 1.x).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/media_stores.dart';
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
}

/// QStandardPaths::setTestModeEnabled equivalent: redirects the
/// application-support resolution used by MediaStores.init().
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
