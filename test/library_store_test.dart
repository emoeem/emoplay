import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';

/// Headless unit tests for the media library. The storage file path is
/// injected per test (temp directory), the scan runs against a tree built in
/// a temp directory with the exact layout and byte sizes of the committed
/// 1.x fixtures (mpv-emo tests/fixtures/library — the generator comments
/// live in the C++ test; the sizes matter because the sort tests pin them).
///
/// Case-for-case port of mpv-emo tests/test_library_store.cpp; assertion
/// values are the behavioural contract and are copied verbatim. Two
/// mechanical adaptations, both documented at the case:
///  * QSignalSpy counts on distinct Qt signals become state assertions — a
///    ChangeNotifier merges the individual signals, so "no notification"
///    is asserted as "no state change / no file written".
///  * QTRY_*/QTRY_VERIFY polling becomes pumpUntil().
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-library-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String fixturePath([String relative = '']) => relative.isEmpty
      ? '${tempDir.path}/fixtures/library'
      : '${tempDir.path}/fixtures/library/$relative';

  // Committed-fixture tree with pinned byte sizes (movie.mkv 99 B is the
  // largest, ep1.mkv 14 B the smallest of the 6 Movies entries).
  Future<void> writeFixtureTree() async {
    final files = <String, int>{
      'Movies/movie.mkv': 99,
      'Movies/BIG.MKV': 20,
      'Movies/trailer.mp4': 18,
      'Movies/readme.txt': 10,
      'Movies/.hidden.mkv': 13,
      'Movies/Season 1/ep1.mkv': 14,
      'Movies/Season 1/theme.wav': 15,
      'Movies/Season 1/Deep/nested.mp4': 13,
      'Movies/Season 1/Deep/Deepest/too-deep.mp4': 9,
      'Music/track.flac': 17,
      'Music/album/song.mp3': 15,
    };
    for (final entry in files.entries) {
      final file = File(fixturePath(entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString('x' * entry.value);
    }
  }

  LibraryEntry findEntry(List<LibraryEntry> entries, String title) =>
      entries.firstWhere(
        (entry) => entry.title == title,
        orElse: () => const LibraryEntry(path: ''),
      );

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Map<String, Object?> entryJson(
    String path,
    String title,
    String type,
    int size,
    String lastPlayed,
  ) =>
      {
        'path': path,
        'title': title,
        'type': type,
        'size': size,
        'lastPlayed': lastPlayed,
      };

  /// Writes a library.json with pre-built entries (the 1.x model tests start
  /// the store from a hand-written file for a synchronous initial state).
  Future<String> writeLibraryFile(List<Map<String, Object?>> entries) async {
    final file = File('${tempDir.path}/library.json');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'directories': <String>[],
        'entries': entries,
      }),
      flush: true,
    );
    return file.path;
  }

  group('pure scan logic', () {
    test('mediaTypeClassification', () {
      expect(LibraryStore.mediaTypeForSuffix('mkv'), 'video');
      expect(LibraryStore.mediaTypeForSuffix('webm'), 'video');
      expect(LibraryStore.mediaTypeForSuffix('flac'), 'audio');
      expect(LibraryStore.mediaTypeForSuffix('opus'), 'audio');
      expect(LibraryStore.mediaTypeForSuffix('txt'), '');
      expect(LibraryStore.mediaTypeForSuffix('exe'), '');
      expect(LibraryStore.mediaTypeForSuffix(''), '');
    });

    // Movies fixture (default options: maxDepth 2, skipHidden):
    //   movie.mkv / trailer.mp4 / BIG.MKV (depth 0, video)
    //   Season 1/ep1.mkv (video), Season 1/theme.wav (audio)   — depth 1
    //   Season 1/Deep/nested.mp4 (video)                       — depth 2
    //   Season 1/Deep/Deepest/too-deep.mp4                     — depth 3, skipped
    //   readme.txt (no media extension) and .hidden.mkv (hidden), skipped
    // Result must be sorted by title case-insensitively (BIG before ep1).
    test('scanClassifiesSkipsAndSorts', () async {
      await writeFixtureTree();
      final entries = await LibraryStore.scanDirectories(
          [fixturePath('Movies')], const ScanOptions());

      expect(entries, hasLength(6));
      expect(entries[0].title, 'BIG');
      expect(entries[1].title, 'ep1');
      expect(entries[2].title, 'movie');
      expect(entries[3].title, 'nested');
      expect(entries[4].title, 'theme');
      expect(entries[5].title, 'trailer');

      // Uppercase extension classifies like its lower-case form.
      expect(entries[0].type, 'video');
      expect(findEntry(entries, 'theme').type, 'audio');
      expect(findEntry(entries, 'ep1').type, 'video');

      // Title is the file name without extensions; size is the file size.
      final movie = findEntry(entries, 'movie');
      expect(movie.path, isNotEmpty);
      expect(movie.path, fixturePath('Movies/movie.mkv'));
      expect(movie.size, File(fixturePath('Movies/movie.mkv')).lengthSync());

      // Excluded entries.
      expect(findEntry(entries, 'readme').path, isEmpty);
      expect(findEntry(entries, 'hidden').path, isEmpty);
      expect(findEntry(entries, 'too-deep').path, isEmpty);
    });

    test('scanDepthAndHiddenOptions', () async {
      await writeFixtureTree();
      final dirs = [fixturePath('Movies')];

      expect(
        await LibraryStore.scanDirectories(
            dirs, const ScanOptions(maxDepth: 1)),
        hasLength(5),
      );

      // maxDepth <= 0 means unlimited: too-deep.mp4 (depth 3) is included.
      expect(
        await LibraryStore.scanDirectories(
            dirs, const ScanOptions(maxDepth: 0)),
        hasLength(7),
      );

      // Turning the hidden filter off adds .hidden.mkv.
      expect(
        await LibraryStore.scanDirectories(dirs,
            const ScanOptions(maxDepth: 2, skipHidden: false)),
        hasLength(7),
      );
    });

    test('scanDedupesAcrossDirectories', () async {
      await writeFixtureTree();
      final dirs = [fixturePath('Movies'), fixturePath('Movies/Season 1')];
      // Movies alone yields 6 (depth <= 2); the Season 1 walk re-finds
      // ep1/theme/nested but reaches too-deep.mp4 at its own depth 2. The
      // union is 7 unique files and the overlapping ones appear once each.
      final entries = await LibraryStore.scanDirectories(
          dirs, const ScanOptions());
      expect(entries, hasLength(7));
      for (final title in ['ep1', 'theme', 'nested']) {
        final occurrences =
            entries.where((entry) => entry.title == title).length;
        expect(occurrences, 1);
      }
      expect(findEntry(entries, 'too-deep').path, isNotEmpty);

      // Scanning the same directory twice neither duplicates nor doubles.
      expect(
        await LibraryStore.scanDirectories(
            [fixturePath('Movies'), fixturePath('Movies')],
            const ScanOptions()),
        hasLength(6),
      );
    });

    test('scanProgressAndCancellation', () async {
      await writeFixtureTree();
      var last = 0;
      var calls = 0;
      final entries = await LibraryStore.scanDirectories(
          [fixturePath('Movies')], const ScanOptions(),
          progress: (found) {
        last = found;
        calls++;
      });
      expect(entries, hasLength(6));
      // The final call reports every file found; with 6 files there is no
      // intermediate (every-32) call.
      expect(last, 6);
      expect(calls, 1);

      // A cancelled walk stops early and returns what it has.
      var checks = 0;
      final partial = await LibraryStore.scanDirectories(
          [fixturePath('Movies')], const ScanOptions(),
          cancelled: () => ++checks > 3);
      expect(partial.length, lessThan(6));
    });
  });

  group('folder list', () {
    test('defaultPathIsLibraryJsonInAppData', () async {
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() => PathProviderPlatform.instance = previous);

      final path = await LibraryStore.defaultFilePath();
      expect(p.isAbsolute(path), isTrue);
      expect(path, endsWith('library.json'));
      // Test mode redirects the app-support location away from the user's
      // real data (1.x asserted the ".qttest" marker; here the injected
      // fake directory).
      expect(path, contains(tempDir.path));
    });

    test('addRemoveDirectoryValidatesAndPersists', () async {
      await writeFixtureTree();
      final file = '${tempDir.path}/library.json';
      final store = LibraryStore(file);
      addTearDown(store.dispose);

      // Non-directories are rejected (and nothing is persisted: the file
      // only appears once a real change lands — the 1.x spy asserted zero
      // directoriesChanged).
      expect(store.addDirectory('/nonexistent/nope'), isFalse);
      expect(store.addDirectory(fixturePath('Movies/movie.mkv')), isFalse);
      expect(File(file).existsSync(), isFalse);

      // Adding a directory succeeds; the trailing-slash form dedupes.
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      expect(store.addDirectory('${fixturePath('Movies')}/'), isFalse);
      expect(store.directories, hasLength(1));

      // The folder list survives a reload.
      await pumpUntil(() => !store.isScanning);
      final reloaded = LibraryStore(file);
      addTearDown(reloaded.dispose);
      expect(reloaded.directories, store.directories);
    });

    test('addDirectoryAcceptsFileUrl', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      // The picker dialogs hand over file:// URLs (1.x MpvEngine::loadFile
      // convention).
      final url = Uri.file(fixturePath('Music')).toString();
      expect(store.addDirectory(url), isTrue);
      expect(store.directories, hasLength(1));
      expect(store.directories.first, fixturePath('Music'));
    });

    test('removeDirectoryDropsItsEntries', () async {
      await writeFixtureTree();
      final file = '${tempDir.path}/library.json';
      final store = LibraryStore(file);
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);
      expect(store.entryList, hasLength(6));

      store.removeDirectory(fixturePath('Movies'));
      expect(store.directories, isEmpty);
      expect(store.entryList, isEmpty);

      // Unknown folders are a silent no-op (no state change, so no
      // notification either — 1.x asserted the signal count).
      store.removeDirectory('/unknown/dir');
      expect(store.directories, isEmpty);

      final reloaded = LibraryStore(file);
      addTearDown(reloaded.dispose);
      expect(reloaded.directories, isEmpty);
      expect(reloaded.entryList, isEmpty);
    });

    // The removed folder's path prefix must not swallow sibling folders
    // whose names merely start with the same string ("A" vs "AB").
    test('removeDirectoryPrefixDoesNotCatchSiblings', () async {
      final base = Directory('${tempDir.path}/siblings');
      await Directory('${base.path}/A').create(recursive: true);
      await Directory('${base.path}/AB').create(recursive: true);
      await File('${base.path}/A/x.mkv').writeAsString('x');
      await File('${base.path}/AB/y.mkv').writeAsString('y');

      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory('${base.path}/A'), isTrue);
      expect(store.addDirectory('${base.path}/AB'), isTrue);
      await pumpUntil(() => !store.isScanning);
      expect(store.entryList, hasLength(2));

      store.removeDirectory('${base.path}/A');
      expect(store.entryList, hasLength(1));
      expect(store.entryList.first.path, '${base.path}/AB/y.mkv');
    });
  });

  group('scans', () {
    test('autoScanAfterAddFindsEntries', () async {
      await writeFixtureTree();
      final file = '${tempDir.path}/library.json';
      final store = LibraryStore(file);
      addTearDown(store.dispose);

      // addDirectory kicks off a scan in the worker isolate.
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => store.entryList.length == 6);
      expect(store.isScanning, isFalse);
      expect(store.scanFileCount, 6);

      // The scan results are persisted.
      final reloaded = LibraryStore(file);
      addTearDown(reloaded.dispose);
      expect(reloaded.entryList, hasLength(6));
      expect(findEntry(reloaded.entryList, 'movie').type, 'video');
    });

    test('chainedScanCoversLateFolders', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      // The second add lands while the first scan is likely still running;
      // the request must be chained (or restarted), never dropped.
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      expect(store.addDirectory(fixturePath('Music')), isTrue);

      await pumpUntil(() => store.entryList.length == 8); // 6 Movies + 2 Music
      expect(store.isScanning, isFalse);
      expect(findEntry(store.entryList, 'track').type, 'audio');
      expect(findEntry(store.entryList, 'song').type, 'audio');
    });

    test('scanUpdatesScanningAndCountProperties', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);

      store.requestScan();
      // scanning = true lands synchronously (1.x emitted scanningChanged
      // before returning from requestScan).
      expect(store.isScanning, isTrue);
      await pumpUntil(() => !store.isScanning);
      expect(store.scanFileCount, 6);
    });

    test('requestScanWithoutDirectoriesKeepsEmpty', () async {
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      store.requestScan();
      await pumpUntil(() => !store.isScanning);
      expect(store.entryList, isEmpty);
    });

    test('rescanPreservesLastPlayed', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);

      final moviePath = fixturePath('Movies/movie.mkv');
      store.notePlayed(moviePath);
      final stamp = findEntry(store.entryList, 'movie').lastPlayed;
      expect(stamp, isNotEmpty);

      store.requestScan();
      await pumpUntil(() => !store.isScanning);
      expect(store.entryList, hasLength(6));
      expect(findEntry(store.entryList, 'movie').lastPlayed, stamp);
    });
  });

  group('lastPlayed + persistence', () {
    test('notePlayedUpdatesAndPersists', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);

      store.notePlayed(fixturePath('Movies/Season 1/ep1.mkv'));
      final stamp = findEntry(store.entryList, 'ep1').lastPlayed;
      expect(DateTime.tryParse(stamp), isNotNull);

      final reloaded = LibraryStore('${tempDir.path}/library.json');
      addTearDown(reloaded.dispose);
      expect(findEntry(reloaded.entryList, 'ep1').lastPlayed, stamp);
    });

    test('notePlayedUnknownPathIsIgnored', () async {
      await writeFixtureTree();
      final file = '${tempDir.path}/library.json';
      final store = LibraryStore(file);
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);

      store.notePlayed('/unknown/file.mkv');
      store.notePlayed('');
      expect(store.entryList, hasLength(6));
      // Nothing about the unknown notes touched the persisted file.
      final reloaded = LibraryStore(file);
      addTearDown(reloaded.dispose);
      expect(findEntry(reloaded.entryList, 'ep1').lastPlayed, '');
    });

    test('corruptFileRecoversToEmpty', () async {
      await writeFixtureTree();
      final file = '${tempDir.path}/library.json';
      await File(file).writeAsString('this is not json {{{');

      final store = LibraryStore(file);
      addTearDown(store.dispose);
      expect(store.directories, isEmpty);
      expect(store.entryList, isEmpty);

      // Adding a directory must overwrite the broken file with valid JSON.
      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => !store.isScanning);
      final reloaded = LibraryStore(file);
      addTearDown(reloaded.dispose);
      expect(reloaded.directories, hasLength(1));
      expect(reloaded.entryList, hasLength(6));
    });
  });

  group('LibraryModel', () {
    test('modelMirrorsStoreEntries', () async {
      final filePath = await writeLibraryFile([
        entryJson('/media/A/alpha.mkv', 'alpha', 'video', 10, ''),
        entryJson('/media/B/Zeta.flac', 'Zeta', 'audio', 20, ''),
      ]);

      final store = LibraryStore(filePath);
      addTearDown(store.dispose);
      expect(store.entryList, hasLength(2));

      final model = LibraryModel(store);
      addTearDown(model.dispose);
      expect(model.count, 2);

      expect(model.pathAt(0), '/media/A/alpha.mkv');
      expect(model.titleAt(1), 'Zeta');
      expect(model.typeAt(1), 'audio');
      expect(model.sizeAt(1), 20);
      expect(model.lastPlayedAt(0), '');
      // Out-of-range rows report nothing (1.x data(QModelIndex(), role)
      // returned an empty QVariant).
      expect(model.pathAt(5), '');
      expect(model.pathAt(-1), '');
    });

    test('modelRolesExposeEntryFields', () async {
      // 1.x roleNames() mapped PathRole/TitleRole/TypeRole/SizeRole/
      // LastPlayedRole to "path"/"title"/"type"/"size"/"lastPlayed"; the
      // 2.0 rows expose the same fields through the *At(row) accessors
      // (library_model.dart role-lookup note).
      final filePath = await writeLibraryFile([
        entryJson('/media/A/alpha.mkv', 'alpha', 'video', 10, ''),
      ]);

      final store = LibraryStore(filePath);
      addTearDown(store.dispose);
      final model = LibraryModel(store);
      addTearDown(model.dispose);
      expect(model.count, 1);

      expect(model.pathAt(0), '/media/A/alpha.mkv'); // PathRole -> "path"
      expect(model.titleAt(0), 'alpha'); // TitleRole -> "title"
      expect(model.typeAt(0), 'video'); // TypeRole -> "type"
      expect(model.sizeAt(0), 10); // SizeRole -> "size"
      expect(model.lastPlayedAt(0), ''); // LastPlayedRole -> "lastPlayed"
    });

    test('modelFilterNarrowsAndResets', () async {
      final filePath = await writeLibraryFile([
        entryJson('/media/A/alpha.mkv', 'alpha', 'video', 10, ''),
        entryJson('/media/B/Zeta.flac', 'Zeta', 'audio', 20, ''),
      ]);

      final store = LibraryStore(filePath);
      addTearDown(store.dispose);
      final model = LibraryModel(store);
      addTearDown(model.dispose);
      expect(model.count, 2);
      expect(model.filter, '');

      // Title match, case-insensitive.
      model.filter = 'ALP';
      expect(model.count, 1);
      expect(model.titleAt(0), 'alpha');

      // Path match, case-insensitive; title of the other row does not match.
      model.filter = '/media/b';
      expect(model.count, 1);
      expect(model.titleAt(0), 'Zeta');

      // No match.
      model.filter = 'nothing-matches';
      expect(model.count, 0);

      // Resetting the filter restores everything.
      model.filter = '';
      expect(model.count, 2);
    });

    test('modelFollowsStoreUpdates', () async {
      await writeFixtureTree();
      // Start with one fake entry; adding a real folder replaces the store's
      // list, and the model must follow without any manual refresh.
      final filePath = await writeLibraryFile([
        entryJson('/gone/fake.mkv', 'fake', 'video', 1, ''),
      ]);

      final store = LibraryStore(filePath);
      addTearDown(store.dispose);
      final model = LibraryModel(store);
      addTearDown(model.dispose);
      expect(model.count, 1);

      expect(store.addDirectory(fixturePath('Movies')), isTrue);
      await pumpUntil(() => model.count == 6);
      expect(findEntry(store.entryList, 'fake').path, isEmpty);
      // The filtered view follows too. ("movie" would match every entry via
      // the Movies folder inside the path, so pin one unique title instead.)
      model.filter = 'ep1';
      expect(model.count, 1);
      expect(model.pathAt(0), fixturePath('Movies/Season 1/ep1.mkv'));
    });

    test('modelWithoutServiceHasEmptyThumbnailRole', () async {
      final filePath = await writeLibraryFile([
        entryJson('/media/A/alpha.mkv', 'alpha', 'video', 10, ''),
      ]);
      final store = LibraryStore(filePath);
      addTearDown(store.dispose);
      final model = LibraryModel(store); // no ThumbnailService: legacy wiring
      addTearDown(model.dispose);
      expect(model.count, 1);
      expect(model.thumbnailAt(0), '');
    });

    test('modelTypeFilterSelectsKind', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath()), isTrue);

      final model = LibraryModel(store);
      addTearDown(model.dispose);
      await pumpUntil(() => model.count == 7, timeout: const Duration(seconds: 20));

      model.typeFilter = 'video';
      expect(model.count, 4);
      for (var row = 0; row < model.count; row++) {
        expect(model.typeAt(row), 'video');
      }

      model.typeFilter = 'audio';
      expect(model.count, 3);
      for (var row = 0; row < model.count; row++) {
        expect(model.typeAt(row), 'audio');
      }

      // Unknown values normalise to "all" instead of emptying the grid.
      model.typeFilter = 'bogus';
      expect(model.typeFilter, 'all');
      expect(model.count, 7);
    });

    test('modelSortModesReorderRows', () async {
      await writeFixtureTree();
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(fixturePath()), isTrue);

      final model = LibraryModel(store);
      addTearDown(model.dispose);
      await pumpUntil(() => model.count == 7, timeout: const Duration(seconds: 20));

      List<String> titles() =>
          [for (var row = 0; row < model.count; row++) model.titleAt(row)];

      model.sortMode = 'title';
      expect(
          titles(),
          ['BIG', 'ep1', 'movie', 'song', 'theme', 'track', 'trailer']);

      model.sortMode = 'titleDesc';
      expect(titles().first, 'trailer');

      model.sortMode = 'size';
      expect(titles().first, 'movie'); // 99 bytes, the largest fixture
      expect(titles().last, 'ep1'); // 14 bytes

      // "recent" puts the never-played entries last and the newest first.
      model.sortMode = 'recent';
      expect(model.lastPlayedAt(0), '');
      final movie = fixturePath('Movies/movie.mkv');
      store.notePlayed(movie);
      await pumpUntil(() => model.pathAt(0) == movie,
          timeout: const Duration(seconds: 5));
    });
  });

  group('cancellation through the real worker isolate', () {
    test('cancelWhileIdleIsNoop', () async {
      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);

      store.cancelScan(); // nothing running: must not flip the state
      expect(store.isScanning, isFalse);
    });

    test('cancelDuringScanKeepsPartialResultAndRecovers', () async {
      final media = Directory('${tempDir.path}/media');
      await media.create();
      // Enough files that the walk is still running when the cancel lands.
      for (var i = 0; i < 400; i++) {
        await File(
                '${media.path}/clip${i.toString().padLeft(4, '0')}.mkv')
            .writeAsString('x');
      }

      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);
      expect(store.addDirectory(media.path), isTrue);

      store.cancelScan();
      await pumpUntil(() => !store.isScanning,
          timeout: const Duration(seconds: 30));
      // Whatever the worker managed to collect is applied, and never more
      // than the folder holds.
      expect(store.entryList.length, lessThanOrEqualTo(400));

      // A cancel must not poison the store: a fresh scan still finds
      // everything.
      store.requestScan();
      await pumpUntil(
          () => !store.isScanning && store.entryList.length == 400,
          timeout: const Duration(seconds: 30));
    });
  });
}

/// QStandardPaths::setTestModeEnabled equivalent: redirects the
/// application-support resolution used by LibraryStore.defaultFilePath().
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
