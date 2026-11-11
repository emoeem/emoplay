import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/media_stores.dart';
import 'package:emoplay/pages/library/library_grid_groups.dart';
import 'package:emoplay/pages/library/library_page.dart';

/// M4-T2 guard tests (EmoPlay 3.0 roadmap): the library grid groups by
/// directory or last-played year-month under pinned headers (Kazumi
/// popular_page 范式) while search / typeFilter / sortMode keep their
/// model-side semantics.
///
///  * Grouping keys + group order + within-group stability are tested as
///    pure logic (library_grid_groups.dart);
///  * "筛选后分组" runs a real LibraryModel over a real LibraryStore so the
///    filter/typeFilter/sort pipeline is the one the page feeds in;
///  * the pinned-structure smoke mounts the real page headless (the same
///    MediaStores-under-fake-path-provider bootstrap as
///    kazumi_alignment_ui_test.dart) against a seeded library.json and
///    asserts the SliverPinnedHeader / SliverMainAxisGroup / SliverGrid
///    structure in group order.
void main() {
  // Real-async-zone temp directory: widget tests must not create it inside
  // testWidgets (real IO futures never fire in the fake-async zone).
  late Directory sharedTempDir;
  setUp(() async {
    sharedTempDir = await Directory.systemTemp.createTemp('emoplay-pinned-');
  });
  tearDown(() async {
    try {
      await sharedTempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('directoryGroupsKeyOnParentFolderInCaseInsensitiveOrder', () {
    final entries = [
      _entry('/media/Beta/ep2.mkv'),
      _entry('/media/alpha/movie.mkv'),
      _entry('/media/alpha/extra/trailer.mp4'),
      _entry('/media/Beta/ep1.mkv'),
    ];

    final groups = groupLibraryEntries(entries,
        mode: LibraryGroupMode.directory);

    // One group per parent directory (alpha and alpha/extra are distinct
    // keys), ordered case-insensitively by path (the model's "path" sort
    // convention), label = the folder's own name.
    expect(groups.map((group) => group.key).toList(),
        ['/media/alpha', '/media/alpha/extra', '/media/Beta']);
    expect(groups.map((group) => group.label).toList(),
        ['alpha', 'extra', 'Beta']);
    // Rows keep the input order inside a group (sort semantics preserved).
    expect(groups[0].entries.map((entry) => entry.path).toList(),
        ['/media/alpha/movie.mkv']);
    expect(groups[1].entries.map((entry) => entry.path).toList(),
        ['/media/alpha/extra/trailer.mp4']);
    expect(groups[2].entries.map((entry) => entry.path).toList(),
        ['/media/Beta/ep2.mkv', '/media/Beta/ep1.mkv']);
  });

  test('yearMonthGroupsNewestFirstWithUnplayedLast', () {
    final entries = [
      _entry('/media/never.mkv'),
      _entry('/media/jan.mkv', lastPlayed: '2026-01-15T10:00:00.000'),
      _entry('/media/nov.mkv', lastPlayed: '2026-11-02T08:00:00.000'),
      _entry('/media/jan2.mkv', lastPlayed: '2026-01-03T22:00:00.000'),
    ];

    final groups = groupLibraryEntries(entries,
        mode: LibraryGroupMode.yearMonth);

    expect(groups.map((group) => group.key).toList(),
        ['2026-11', '2026-01', '']);
    expect(groups.map((group) => group.label).toList(),
        ['2026年11月', '2026年1月', '未播放']);
    expect(groups[1].entries.map((entry) => entry.path).toList(),
        ['/media/jan.mkv', '/media/jan2.mkv'],
        reason: 'within-group order follows the caller (the "recent" sort '
            'delivers newest first inside the same month)');
  });

  test('filterTypeAndSortSemanticsSurviveGrouping', () {
    // The real pipeline: §7 library.json -> LibraryStore -> LibraryModel
    // (filter / typeFilter / sortMode) -> groups. Expectations: the audio
    // file (theme.wav) and the non-matching title (unrelated.mkv) drop, the
    // size sort (largest first) orders the survivors, and grouping only
    // partitions them — it never re-sorts.
    final entries = [
      _entry('/media/s1/ep1.mkv', size: 14, title: 'ep1'),
      _entry('/media/s1/ep9.mkv', size: 99, title: 'ep9'),
      _entry('/media/s1/unrelated.mkv', size: 200, title: 'unrelated'),
      _entry('/media/s2/ep5.mkv', size: 40, title: 'ep5'),
      _entry('/media/s2/theme.wav', size: 15, title: 'theme'),
    ];
    final tempDir = Directory.systemTemp.createTempSync('emoplay-group-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final libraryFile = File('${tempDir.path}/library.json');
    libraryFile.writeAsStringSync(jsonEncode(<String, Object?>{
      'version': 1,
      'directories': ['/media/s1', '/media/s2'],
      'entries': [for (final entry in entries) entry.toJson()],
    }));
    final model = LibraryModel(LibraryStore(libraryFile.path));
    addTearDown(model.dispose);

    model
      ..typeFilter = 'video'
      ..filter = 'ep'
      ..sortMode = 'size';
    final visible = model.visible;
    expect(
        visible.map((entry) => entry.path).toList(),
        ['/media/s1/ep9.mkv', '/media/s2/ep5.mkv', '/media/s1/ep1.mkv'],
        reason: 'typeFilter+filter keep the three "ep" videos; the size sort '
            'orders them largest first across directories');

    final groups =
        groupLibraryEntries(visible, mode: LibraryGroupMode.directory);
    expect(groups.map((group) => group.key).toList(),
        ['/media/s1', '/media/s2']);
    // The size sort survives inside each group (grouping only partitions).
    expect(groups[0].entries.map((entry) => entry.size).toList(), [99, 14]);
    expect(groups[1].entries.map((entry) => entry.size).toList(), [40]);
  });

  testWidgets('pinnedGroupStructureSmoke', (tester) async {
    // The temp directory comes from setUp (real async zone) — creating it
    // inside testWidgets would block on the fake-async event loop.
    final tempDir = sharedTempDir;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // Seed the §7 library.json BEFORE MediaStores.init() reads it: two
    // roots, entries in both, so the grid shows three pinned groups.
    File('${tempDir.path}/library.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'version': 1,
          'directories': ['$tempDir/Movies', '$tempDir/Music'],
          'entries': [
            <String, Object?>{
              'path': '$tempDir/Movies/movie.mkv',
              'title': 'movie',
              'type': 'video',
              'size': 10,
              'lastPlayed': ''
            },
            <String, Object?>{
              'path': '$tempDir/Movies/Season 1/ep1.mkv',
              'title': 'ep1',
              'type': 'video',
              'size': 11,
              'lastPlayed': ''
            },
            <String, Object?>{
              'path': '$tempDir/Music/song.flac',
              'title': 'song',
              'type': 'audio',
              'size': 12,
              'lastPlayed': ''
            },
          ],
        }));

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      await MediaStores.init();
    });

    // Tall surface: every group's cells must be built for the text finds.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The pinned paradigm: one pinned header per group above its grid (this
    // Flutter version has no SliverPinnedHeader shorthand — the structure is
    // SliverPersistentHeader(pinned: true) inside SliverMainAxisGroup).
    expect(find.byType(SliverMainAxisGroup), findsNWidgets(3));
    final pinnedHeaders =
        tester.widgetList<SliverPersistentHeader>(
            find.byType(SliverPersistentHeader));
    expect(pinnedHeaders.length, 3);
    for (final header in pinnedHeaders) {
      expect(header.pinned, isTrue);
    }
    expect(find.byType(SliverGrid), findsNWidgets(3));
    // Group headers in group order (case-insensitive by path: Movies <
    // Movies/Season 1 < Music).
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    // Rows are inside the groups (the pre-M4-T2 plain GridView is gone).
    expect(find.text('movie'), findsOneWidget);
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('song'), findsOneWidget);
  });
}

LibraryEntry _entry(String path, {int size = 10, String title = '', String lastPlayed = ''}) =>
    LibraryEntry(
      path: path,
      title: title.isEmpty ? path.split('/').last : title,
      type: path.endsWith('.flac') || path.endsWith('.wav') ? 'audio' : 'video',
      size: size,
      lastPlayed: lastPlayed,
    );

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
