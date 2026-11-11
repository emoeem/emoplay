import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/library/library_page.dart';

/// M4-T6 UI smoke (user addition 2026-11-12): the library page's 按剧集分组
/// (show → season → episode, nested SliverMainAxisGroups) and 按电影分组
/// views, the local poster art, the NFO info badge and the details sheet.
///
/// The same MediaStores-under-fake-path-provider bootstrap as
/// library_grid_grouping_test.dart: a real temp directory holds real NFO/
/// poster files, library.json is seeded before init, and the NFO scan queue
/// is drained through runAsync before any assertion.
void main() {
  late Directory sharedTempDir;
  setUp(() async {
    sharedTempDir = await Directory.systemTemp.createTemp('emoplay-nfo-ui-');
  });
  tearDown(() async {
    try {
      await sharedTempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('episodeAndMovieViewsPlusNfoSheet', (tester) async {
    final tempDir = sharedTempDir;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    // Real filesystem facts for the NFO/poster scan.
    final showDir = Directory('${tempDir.path}/Shows/TVShow')
      ..createSync(recursive: true);
    File('${showDir.path}/tvshow.nfo').writeAsStringSync(
        '<tvshow><title>NFO Show</title><plot>The show plot.</plot></tvshow>');
    File('${showDir.path}/poster.jpg').writeAsStringSync('poster');
    File('${showDir.path}/Show.S01E01.mkv').writeAsStringSync('v');
    File('${showDir.path}/Show.S01E01.nfo').writeAsStringSync(
        '<episodedetails><title>第一集</title><season>1</season><episode>1</episode>'
        '<plot>第一集剧情。</plot><thumb>https://img/e1.jpg</thumb></episodedetails>');
    File('${showDir.path}/Show.S01E02.mkv').writeAsStringSync('v');
    File('${showDir.path}/Show.S01E02.nfo').writeAsStringSync(
        '<episodedetails><title>第二集</title><season>1</season><episode>2</episode>'
        '<plot>第二集剧情。</plot><thumb>https://img/e2.jpg</thumb></episodedetails>');
    File('${showDir.path}/Show.S02E01.mkv').writeAsStringSync('v');

    final movieDir = Directory('${tempDir.path}/Movies')
      ..createSync(recursive: true);
    File('${movieDir.path}/movie.nfo').writeAsStringSync(
        '<movie><title>NFO 电影</title><year>2020</year><rating>8.5</rating>'
        '<plot>电影剧情。</plot><thumb>https://img/m.jpg</thumb></movie>');
    File('${movieDir.path}/film.mkv').writeAsStringSync('v');
    File('${movieDir.path}/poster.jpg').writeAsStringSync('poster');

    File('${tempDir.path}/plain.mkv').writeAsStringSync('v');

    // Seed the §7 library.json BEFORE MediaStores.init() reads it.
    File('${tempDir.path}/library.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'version': 1,
          'directories': [
            showDir.path,
            movieDir.path,
          ],
          'entries': [
            _entry('${showDir.path}/Show.S01E01.mkv'),
            _entry('${showDir.path}/Show.S01E02.mkv'),
            _entry('${showDir.path}/Show.S02E01.mkv'),
            _entry('${movieDir.path}/film.mkv'),
            _entry('${tempDir.path}/plain.mkv'),
          ],
        }));

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });

    // Drain the NFO scan queue for every seeded video (deadline-guarded).
    final videoPaths = <String>[
      '${showDir.path}/Show.S01E01.mkv',
      '${showDir.path}/Show.S01E02.mkv',
      '${showDir.path}/Show.S02E01.mkv',
      '${movieDir.path}/film.mkv',
      '${tempDir.path}/plain.mkv',
    ];
    await binding.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        final drained = videoPaths
            .every((path) => MediaStores.instance.nfoMeta.infoFor(path) != null);
        if (drained) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    for (final path in videoPaths) {
      expect(MediaStores.instance.nfoMeta.infoFor(path), isNotNull,
          reason: 'NFO scan must have settled for $path');
    }

    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Directory view: local poster art renders on the cells (the TV show
    // and the movie both have same-directory poster.jpg files).
    expect(find.byType(Image), findsWidgets);

    // The NFO info badge opens the details sheet (克制的 NFO 数据展示).
    // M4-T7 widened the badge to every video cell (NFO-less cells carry the
    // 联网补全 tooltip), so the NFO-backed sheet is addressed by tooltip —
    // same intent, deterministic under the widened badge set.
    await tester.tap(find.byTooltip('NFO 信息').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('简介'), findsWidgets);
    expect(find.textContaining('仅记录不下载'), findsOneWidget,
        reason: 'the sheet shows the recorded <thumb> URLs as data — '
            'nothing is fetched');
    await tester.tapAt(const Offset(20, 20)); // modal barrier dismiss
    await tester.pumpAndSettle();

    // ---- 按剧集分组 -------------------------------------------------------
    await tester.tap(find.byTooltip('网格分组方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按剧集分组'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The show header carries the tvshow.nfo title (NFO override of the
    // file-name-derived "Show").
    expect(find.text('NFO Show'), findsOneWidget);
    // Season headers, specials label excluded (no season 0 here).
    expect(find.text('第 1 季'), findsOneWidget);
    expect(find.text('第 2 季'), findsOneWidget);
    // Episode cells prefer their NFO episode titles; the NFO-less episode
    // keeps its file name.
    expect(find.text('第一集'), findsOneWidget);
    expect(find.text('第二集'), findsOneWidget);
    expect(find.text('Show.S02E01'), findsOneWidget);
    // The marker-less videos land in the trailing group (no row is hidden).
    expect(find.text('未识别剧集'), findsOneWidget);

    // ---- 按电影分组 -------------------------------------------------------
    await tester.tap(find.byTooltip('网格分组方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按电影分组'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Movies are the videos WITHOUT an episode marker, keyed by the NFO
    // title when one exists ("NFO 电影") and the file title otherwise
    // ("plain" — header + its cell, two widgets); the episode-marker files
    // belong to the episodes view.
    expect(find.text('NFO 电影'), findsOneWidget);
    expect(find.text('plain'), findsNWidgets(2));
    expect(find.text('第一集'), findsNothing);
  });
}

Map<String, Object?> _entry(String path) => <String, Object?>{
      'path': path,
      // The scanner's title convention: completeBaseName (last extension
      // stripped).
      'title': path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
      'type': 'video',
      'size': 10,
      'lastPlayed': '',
    };

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
