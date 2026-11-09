import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/library_store.dart';

/// Data-compatibility gate for the 1.x -> 2.0 migration: the sample JSON
/// documents of docs/SPEC.md §7 ("与 1.x 逐字段一致") are fed verbatim into
/// HistoryStore / LibraryStore and read back, and the 2.0 writers must emit
/// the same field-for-field schema again so 1.x files stay readable.
///
/// The §7 samples are shown with empty-string placeholders; the load tests
/// use schema-conformant documents with realistic values plus the two
/// interesting schema cases the samples pin down:
///   * every field of every entry present exactly as named in §7;
///   * `lastPlayed` is written as `null` by foreign writers (§7 sample) and
///     must load as "" (LibraryEntry.fromJson's documented null tolerance);
///   * the literal §7 placeholder entry (path "") is skipped on load, the
///     same defensive skip 1.x had (mpv-emo
///     src/history/HistoryStore.cpp:183).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-spec7-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // The §7 history.json schema, filled with realistic values.
  const String spec7History = '''
{
  "version": 1,
  "entries": [
    {
      "path": "/home/emo/Videos/Aurora OVA [1080p].mkv",
      "title": "Aurora OVA",
      "position": 733.5,
      "duration": 1620.0,
      "lastPlayedAt": "2026-01-01T00:00:00.000Z"
    },
    {
      "path": "/home/emo/Music/Second Album/02 - Night Drive.flac",
      "title": "02 - Night Drive",
      "position": 0.0,
      "duration": 0.0,
      "lastPlayedAt": "2025-12-31T23:59:59.000Z"
    }
  ]
}
''';

  // The §7 library.json schema, filled with realistic values; lastPlayed is
  // null exactly like the §7 sample shows.
  const String spec7Library = '''
{
  "version": 1,
  "directories": ["/home/emo/Videos", "/home/emo/Music"],
  "entries": [
    {
      "path": "/home/emo/Videos/Aurora OVA [1080p].mkv",
      "title": "Aurora OVA",
      "type": "video",
      "size": 146800640,
      "lastPlayed": null
    },
    {
      "path": "/home/emo/Music/Second Album/02 - Night Drive.flac",
      "title": "02 - Night Drive",
      "type": "audio",
      "size": 33554432,
      "lastPlayed": "2026-01-01T12:00:00.000Z"
    }
  ]
}
''';

  group('HistoryStore reads SPEC §7 history.json', () {
    test('spec7SampleLoadsFieldForField', () {
      final file = File('${tempDir.path}/history.json')
        ..writeAsStringSync(spec7History);

      final store = HistoryStore(null, file.path);
      addTearDown(store.dispose);

      expect(store.entries, hasLength(2));
      expect(store.entries[0].path, '/home/emo/Videos/Aurora OVA [1080p].mkv');
      expect(store.entries[0].title, 'Aurora OVA');
      expect(store.entries[0].position, 733.5);
      expect(store.entries[0].duration, 1620.0);
      expect(store.entries[0].lastPlayedAt, '2026-01-01T00:00:00.000Z');
      expect(store.entries[1].path,
          '/home/emo/Music/Second Album/02 - Night Drive.flac');
      expect(store.entries[1].title, '02 - Night Drive');
      expect(store.entries[1].position, 0.0);
      expect(store.entries[1].duration, 0.0);
      expect(store.entries[1].lastPlayedAt, '2025-12-31T23:59:59.000Z');
    });

    test('spec7PlaceholderSampleSkipsEmptyPathEntry', () {
      // The literal §7 sample with its "" placeholders: the empty-path entry
      // is skipped, exactly like 1.x (HistoryStore.cpp:183).
      final file = File('${tempDir.path}/history.json')
        ..writeAsStringSync(
            '{"version":1,"entries":[{"path":"","title":"","position":0.0,'
            '"duration":0.0,"lastPlayedAt":"2026-01-01T00:00:00.000Z"}]}');

      final store = HistoryStore(null, file.path);
      addTearDown(store.dispose);

      expect(store.entries, isEmpty);
    });

    test('rewrittenFileKeepsSpec7ShapeAndStaysReadable', () {
      final file = File('${tempDir.path}/history.json')
        ..writeAsStringSync(spec7History);

      final store = HistoryStore(null, file.path);
      addTearDown(store.dispose);

      // A playback record on top of the imported 1.x data must persist the
      // merged list back into the §7 shape.
      store.recordPlayback('/home/emo/Videos/Other.mkv', 'Other', 12.0, 90.0);

      final written = jsonDecode(file.readAsStringSync()) as Map<Object?, Object?>;
      expect(written.keys, containsAll(<String>['version', 'entries']));
      expect(written['version'], 1);
      final entries = written['entries'] as List<Object?>;
      expect(entries, hasLength(3));
      for (final entry in entries) {
        expect((entry! as Map).keys.toSet(),
            <String>{'path', 'title', 'position', 'duration', 'lastPlayedAt'});
      }

      // A fresh store reads the merged file back, 1.x order semantics kept
      // (newest at the top, existing entries preserved below it).
      final reloaded = HistoryStore(null, file.path);
      addTearDown(reloaded.dispose);
      expect(reloaded.entries.first.path, '/home/emo/Videos/Other.mkv');
      expect(reloaded.entries[1].path, '/home/emo/Videos/Aurora OVA [1080p].mkv');
      expect(reloaded.entries[1].position, 733.5);
      expect(reloaded.entries[2].lastPlayedAt, '2025-12-31T23:59:59.000Z');
    });
  });

  group('LibraryStore reads SPEC §7 library.json', () {
    test('spec7SampleLoadsFieldForField', () {
      final file = File('${tempDir.path}/library.json')
        ..writeAsStringSync(spec7Library);

      final store = LibraryStore(file.path);
      addTearDown(store.dispose);

      expect(store.directories, <String>['/home/emo/Videos', '/home/emo/Music']);
      expect(store.entryList, hasLength(2));

      final video = store.entryList[0];
      expect(video.path, '/home/emo/Videos/Aurora OVA [1080p].mkv');
      expect(video.title, 'Aurora OVA');
      expect(video.type, 'video');
      expect(video.size, 146800640);
      // §7 sample writes lastPlayed as null; it loads back as "".
      expect(video.lastPlayed, '');
      expect(video.hasLastPlayed, isFalse);

      final audio = store.entryList[1];
      expect(audio.type, 'audio');
      expect(audio.size, 33554432);
      expect(audio.lastPlayed, '2026-01-01T12:00:00.000Z');
      expect(audio.hasLastPlayed, isTrue);
    });

    test('rewrittenFileKeepsSpec7ShapeAndStaysReadable', () {
      final file = File('${tempDir.path}/library.json')
        ..writeAsStringSync(spec7Library);

      final store = LibraryStore(file.path);
      addTearDown(store.dispose);

      // "played inside the library" updates lastPlayed and persists in the
      // §7 shape (no scan, no new files needed).
      store.notePlayed('/home/emo/Videos/Aurora OVA [1080p].mkv');

      final written = jsonDecode(file.readAsStringSync()) as Map<Object?, Object?>;
      expect(written.keys, containsAll(<String>['version', 'directories', 'entries']));
      expect(written['version'], 1);
      expect(written['directories'], <String>['/home/emo/Videos', '/home/emo/Music']);
      for (final entry in written['entries'] as List<Object?>) {
        expect((entry! as Map).keys.toSet(),
            <String>{'path', 'title', 'type', 'size', 'lastPlayed'});
      }

      // A fresh store reads the rewritten file back; the played entry keeps
      // its ISO 8601 timestamp, the untouched one is back to "".
      final reloaded = LibraryStore(file.path);
      addTearDown(reloaded.dispose);
      expect(reloaded.entryList[0].lastPlayed, isNotEmpty);
      expect(DateTime.tryParse(reloaded.entryList[0].lastPlayed), isNotNull);
      expect(reloaded.entryList[1].lastPlayed, '2026-01-01T12:00:00.000Z');
      expect(reloaded.directories, <String>['/home/emo/Videos', '/home/emo/Music']);
    });
  });
}
