import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/favorites_store.dart';
import 'package:emoplay/media/library_store.dart';

/// Headless unit tests for the M4-T3 favorites collection (EmoPlay 3.0
/// roadmap docs/EMOPLAY-3.0-ROADMAP.md M4-T3). The storage file path is
/// injected per test (temp directory), exactly like the other store tests.
///
/// Locked contracts (roadmap 验收: 增删 / 去重 / 损坏 JSON 降级 / 原子写 /
/// lastPlayed 不受影响):
///  * favorites.json is a NEW file whose rows are exactly
///    {"path", "addedAt"} — the MediaItem identity plus the favorite-only
///    timestamp, never a §7 field;
///  * the path is the unique key (duplicates collapse, first addedAt wins);
///  * the order is the user's ReorderableListView order and persists;
///  * a corrupt file degrades to an empty collection and the next mutation
///    rewrites a valid document (the house corrupt-store contract);
///  * the store never touches library.json — notePlayed stamps and
///    favorite mutations are fully isolated.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-favorites-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String favoritesPath() => '${tempDir.path}/favorites.json';
  String libraryPath() => '${tempDir.path}/library.json';

  /// Writes a library.json in the §7 shape with one played entry (the
  /// lastPlayed stamp the isolation test must protect).
  void writeLibraryFile() {
    File(libraryPath()).writeAsStringSync(jsonEncode(<String, Object?>{
      'version': 1,
      'directories': ['/media/root'],
      'entries': [
        <String, Object?>{
          'path': '/media/root/movie.mkv',
          'title': 'movie',
          'type': 'video',
          'size': 10,
          'lastPlayed': '2026-11-01T10:00:00.000',
        },
      ],
    }));
  }

  test('addRemoveToggleRoundTrip', () {
    final store = FavoritesStore(favoritesPath());
    expect(store.count, 0);
    expect(store.contains('/media/a.mkv'), isFalse);

    expect(store.add('/media/a.mkv'), isTrue);
    expect(store.add('/media/b.mkv'), isTrue);
    expect(store.count, 2);
    expect(store.contains('/media/a.mkv'), isTrue);

    // The badge contract: toggle removes a favorite, adds it back otherwise.
    expect(store.toggle('/media/a.mkv'), isFalse);
    expect(store.contains('/media/a.mkv'), isFalse);
    expect(store.toggle('/media/a.mkv'), isTrue);
    // b keeps its position at the front (a was re-appended at the end).
    expect(store.entries.map((entry) => entry.path).toList(),
        ['/media/b.mkv', '/media/a.mkv']);

    expect(store.remove('/media/b.mkv'), isTrue);
    expect(store.remove('/media/never-added.mkv'), isFalse);
    expect(store.add(''), isFalse); // empty path is not a favorite
    expect(store.count, 1);
  });

  test('addDedupesByPathAndKeepsFirstAddedAt', () {
    final store = FavoritesStore(favoritesPath());
    expect(store.add('/media/a.mkv'), isTrue);
    final firstAddedAt = store.entries.single.addedAt;
    expect(firstAddedAt, isNotEmpty);

    // The duplicate is rejected — the path is the unique key, so no second
    // row can appear and the original addedAt survives.
    expect(store.add('/media/a.mkv'), isFalse);
    expect(store.count, 1);
    expect(store.entries.single.addedAt, firstAddedAt);
    expect(store.entries.single.path, '/media/a.mkv');
  });

  test('reorderFollowsReorderableListViewIndexesAndPersists', () {
    final store = FavoritesStore(favoritesPath());
    store.add('/media/1.mkv');
    store.add('/media/2.mkv');
    store.add('/media/3.mkv');

    // Indexes follow the ReorderableListView.onReorderItem contract (the
    // widget adjusts for the removed row): dragging 1.mkv between 2.mkv and
    // 3.mkv reports (0, 1) in post-removal coordinates and the item lands
    // between them.
    store.reorder(0, 1);
    expect(store.entries.map((entry) => entry.path).toList(),
        ['/media/2.mkv', '/media/1.mkv', '/media/3.mkv']);

    // Moving the last item to the front.
    store.reorder(2, 0);
    expect(store.entries.map((entry) => entry.path).toList(),
        ['/media/3.mkv', '/media/2.mkv', '/media/1.mkv']);

    // Out-of-range indexes and same-position drops are no-ops.
    final before = store.entries.map((entry) => entry.path).toList();
    store.reorder(-1, 0);
    store.reorder(0, 99);
    store.reorder(1, 1);
    expect(store.entries.map((entry) => entry.path).toList(), before);

    // The user's order IS the persisted order.
    final reloaded = FavoritesStore(favoritesPath());
    expect(reloaded.entries.map((entry) => entry.path).toList(), before);
  });

  test('corruptJsonDegradesToEmptyAndNextWriteRebuilds', () {
    File(favoritesPath()).writeAsStringSync('{ not json at all');
    var store = FavoritesStore(favoritesPath());
    expect(store.count, 0, reason: 'corrupt file degrades to empty');

    // The collection stays usable: the next mutation rewrites a valid
    // document over the garbage (the corrupt-store contract).
    expect(store.add('/media/a.mkv'), isTrue);
    final reloaded = FavoritesStore(favoritesPath());
    expect(reloaded.entries.single.path, '/media/a.mkv');

    // A document of the wrong shape (valid JSON, not an object / not an
    // entries array) degrades the same way.
    File(favoritesPath()).writeAsStringSync(jsonEncode(['not', 'an', 'object']));
    store = FavoritesStore(favoritesPath());
    expect(store.count, 0);
  });

  test('loadDropsMalformedRowsAndCollapsesDuplicates', () {
    File(favoritesPath()).writeAsStringSync(jsonEncode(<String, Object?>{
      'version': 1,
      'entries': [
        <String, Object?>{'path': '/media/keep.mkv', 'addedAt': '2026-01-01T00:00:00.000'},
        <String, Object?>{'addedAt': 'no path'},
        <String, Object?>{'path': 42},
        'not even a map',
        <String, Object?>{'path': '/media/keep.mkv', 'addedAt': '2026-02-02T00:00:00.000'},
      ],
    }));
    final store = FavoritesStore(favoritesPath());
    expect(store.count, 1, reason: 'junk rows dropped, duplicate collapsed');
    expect(store.entries.single.path, '/media/keep.mkv');
    expect(store.entries.single.addedAt, '2026-01-01T00:00:00.000',
        reason: 'first occurrence wins');
  });

  test('atomicWriteLeavesNoTempFileAndSurvivesReload', () {
    final store = FavoritesStore(favoritesPath());
    store.add('/media/a.mkv');
    store.add('/media/b.mkv');
    store.remove('/media/a.mkv');

    // The temp+rename commit consumed its temp file: only the target
    // remains, and its content round-trips through a fresh store.
    final siblings = File('${tempDir.path}/favorites.json.tmp').existsSync();
    expect(siblings, isFalse, reason: 'temp file renamed away, never left behind');
    final reloaded = FavoritesStore(favoritesPath());
    expect(reloaded.count, 1);
    expect(reloaded.entries.single.path, '/media/b.mkv');
    final document =
        jsonDecode(File(favoritesPath()).readAsStringSync()) as Map<Object?, Object?>;
    expect(document['version'], 1);
  });

  test('favoritesNeverTouchLibraryLastPlayed', () {
    writeLibraryFile();
    final library = LibraryStore(libraryPath());
    final favorites = FavoritesStore(favoritesPath());

    // The library entry is played (a lastPlayed stamp exists) and favorited;
    // favorite mutations of every kind follow (one favorite survives at the
    // end so the document-shape assertions below see a real row).
    expect(library.entryList.single.lastPlayed, '2026-11-01T10:00:00.000');
    favorites.add('/media/root/movie.mkv');
    favorites.add('/media/root/other.mkv');
    favorites.reorder(0, 1);
    favorites.toggle('/media/root/other.mkv');
    expect(favorites.entries.single.path, '/media/root/movie.mkv');

    // library.json is byte-for-byte the store's own business: a fresh
    // LibraryStore still carries the stamp.
    final reloadedLibrary = LibraryStore(libraryPath());
    expect(reloadedLibrary.entryList.single.lastPlayed,
        '2026-11-01T10:00:00.000');

    // And favorites.json itself holds no §7 field at all — the persisted
    // record is only (path, addedAt).
    final document =
        jsonDecode(File(favoritesPath()).readAsStringSync()) as Map<Object?, Object?>;
    final rows = document['entries'] as List<Object?>;
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect((row as Map<Object?, Object?>).containsKey('lastPlayed'), isFalse);
      // `row` is promoted by the cast above — no further casts needed.
      expect(row.containsKey('position'), isFalse);
      expect(row.containsKey('title'), isFalse);
    }
  });
}
