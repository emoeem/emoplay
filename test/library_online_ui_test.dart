import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/library/library_page.dart';

/// M4-T7 UI smoke: the library grid's 联网补全 entry on NFO-less video
/// cells (M4-T6 'NFO 信息' badge unchanged where NFO exists), the details
/// sheet's 联网补全 action and the inline online-result card.
///
/// Everything here is engineered to send ZERO requests, mirroring the
/// local-first contract under test:
///  - settings.json is seeded with the online section enabled so the gate
///    chain reaches the cache gate — the seeded media_online.json record
///    answers there (gate 4: cache hit, no request; the provider behind
///    gate 5 is never constructed), while the real default remains OFF
///    (asserted by the service tests);
///  - TestWidgetsFlutterBinding would answer any accidental HTTP with 400,
///    so a gate regression fails loudly instead of leaking a request.
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-online-ui-');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('onlineFallbackEntrySheetActionAndCachedCard', (tester) async {
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    // Exactly one NFO-backed video and one NFO-less video, so the badge
    // lookups are deterministic.
    final movieDir = Directory('${tempDir.path}/Movies')..createSync();
    File('${movieDir.path}/movie.nfo').writeAsStringSync(
        '<movie><title>NFO 电影</title><year>2020</year>'
        '<plot>电影剧情。</plot></movie>');
    File('${movieDir.path}/film.mkv').writeAsStringSync('v');
    File('${tempDir.path}/plain.mkv').writeAsStringSync('v');
    final plainPath = '${tempDir.path}/plain.mkv';

    // Seed the §7 library.json BEFORE MediaStores.init() reads it.
    Map<String, Object?> entry(String path) => <String, Object?>{
          'path': path,
          'title': path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
          'type': 'video',
          'size': 10,
          'lastPlayed': '',
        };
    File('${tempDir.path}/library.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'version': 1,
          'directories': [movieDir.path],
          'entries': [entry('${movieDir.path}/film.mkv'), entry(plainPath)],
        }));

    // Seed settings.json with the online section ENABLED (the switch's
    // real default is off). With the seeded cache hit below, the gate chain
    // answers at gate 4 — the provider (and any real HTTP) is never
    // reached; TestWidgetsFlutterBinding would 400 any accidental request,
    // failing loudly instead of leaking.
    File('${tempDir.path}/settings.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'online': <String, Object?>{
            'enabled': true,
            'apiKey': 'ui-seed-key',
          },
        }));

    // Seed media_online.json (the M4-T7 cache) with a hit for the NFO-less
    // video — the sheet must render this card without any request.
    File('${tempDir.path}/media_online.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'version': 1,
          'entries': <String, Object?>{
            plainPath: <String, Object?>{
              'fetchedAt': '2026-11-12T00:00:00.000Z',
              'provider': 'tmdb',
              'metadata': <String, Object?>{
                'provider': 'tmdb',
                'providerId': 27205,
                'mediaType': 'movie',
                'title': 'Inception',
                'originalTitle': 'Inception',
                'year': 2010,
                'rating': 8.4,
                'plot': 'A thief who steals corporate secrets.',
                'genres': <String>[],
                'posterUrl': 'https://image.tmdb.org/t/p/w500/poster.jpg',
                'query': 'plain',
              },
            },
          },
        }));

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });
    // Drain the NFO scan queue so film.mkv's badge reads 'NFO 信息'.
    await binding.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        if (MediaStores.instance.nfoMeta.infoFor('${movieDir.path}/film.mkv') !=
            null) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The badge now exists on BOTH video cells with distinct tooltips.
    expect(find.byTooltip('NFO 信息'), findsOneWidget);
    expect(find.byTooltip('联网补全'), findsOneWidget);

    // The NFO-less cell's badge opens the sheet with the online offer and
    // the seeded cache hit rendered inline (no request happened — the
    // master switch is still OFF, so nothing COULD have been sent).
    await tester.tap(find.byTooltip('联网补全'));
    await tester.pumpAndSettle();
    expect(find.text('本条目没有本地 NFO 数据——可用下方联网补全，或自行放置 NFO/海报文件。'),
        findsOneWidget);
    expect(find.text('联网补全结果（tmdb）'), findsOneWidget);
    expect(find.textContaining('Inception'), findsWidgets);
    expect(find.textContaining('仅记录不下载'), findsOneWidget,
        reason: 'poster URL stays text — no UI-side fetches');

    // Running the action answers from the cache (gate 4) with the
    // graceful toast — still zero requests.
    await tester.tap(find.widgetWithText(FilledButton, '联网补全'));
    await tester.pumpAndSettle();
    expect(find.text('来自缓存（media_online.json），未发请求'), findsOneWidget);
    // Let the SnackBar's auto-dismiss timer fire (fake-async clock) so no
    // timer is left pending at teardown.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // The NFO-backed cell keeps the M4-T6 sheet (local facts, no online
    // card — its cache record does not exist).
    await tester.tapAt(const Offset(20, 20)); // dismiss modal
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('NFO 信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('电影剧情。'), findsWidgets);
    expect(find.text('联网补全结果（tmdb）'), findsNothing);
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
