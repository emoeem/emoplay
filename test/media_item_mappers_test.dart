import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/history_store.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/models/media_item.dart';
import 'package:emoplay/models/media_item_mappers.dart';
import 'package:emoplay/models/playback_session.dart';

/// M4-T0 mapper contract tests (EmoPlay 3.0 roadmap
/// docs/EMOPLAY-3.0-ROADMAP.md §四 step 1): the §7 sample documents — the
/// same 1.x-shaped JSONs docs/SPEC.md §7 pins and
/// test/data_compat_spec7_test.dart feeds through the stores — go in,
/// [MediaItem]s come out, and every field the model represents is asserted
/// lossless. The mapper layer is read-only: the three §7 files are never
/// rewritten from here (settings.json has no media entries to map at all —
/// pinned by the last test).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-mappers-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // The §7 history.json schema, filled with realistic values (verbatim
  // from test/data_compat_spec7_test.dart — the shared 1.x sample).
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

  // The §7 library.json schema; lastPlayed is null exactly like the §7
  // sample shows (foreign-writer shape).
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

  // The §7 settings.json schema (quality/behavior/music only — config, no
  // media entries).
  const String spec7Settings = '''
{
  "importDecision": "full",
  "dontAskAgain": false,
  "selectedFiles": [],
  "lastImportSummary": null,
  "importedAt": null,
  "quality": {"contentMode":"anime","qualityTier":"high","toneMappingMode":"auto","scaleOverride":null,"debandMode":"off","manualShaderList":[],"interpolation":{"enabled":false,"preset":"MEMC_01"},"icc":{"enabled":false,"profilePath":""}},
  "behavior": {"resumeOnReopen":true,"libraryMaxDepth":2,"librarySkipHidden":true},
  "music": {"equalizerEnabled":false,"equalizerPreset":"flat","equalizerGains":[0,0,0,0,0,0,0,0,0,0]}
}
''';

  group('history.json → MediaItem', () {
    test('mapsEveryFieldLosslessly', () {
      final entries = (jsonDecode(spec7History)['entries'] as List<Object?>)
          .map((value) => HistoryEntry.fromJson(value! as Map<Object?, Object?>))
          .toList();

      final video = mediaItemFromHistoryEntry(entries[0]);
      expect(video.path, '/home/emo/Videos/Aurora OVA [1080p].mkv');
      expect(video.title, 'Aurora OVA');
      expect(video.duration, 1620.0);
      expect(video.lastPlayed, DateTime.parse('2026-01-01T00:00:00.000Z'));
      expect(video.lastPlayed!.isUtc, isTrue);
      // Classifier vocabulary derived from the extension (nothing in the
      // JSON to lose).
      expect(video.type, 'video');
      // Unknown in the source, unknown in the model.
      expect(video.size, 0);

      final audio = mediaItemFromHistoryEntry(entries[1]);
      expect(audio.path, '/home/emo/Music/Second Album/02 - Night Drive.flac');
      expect(audio.title, '02 - Night Drive');
      expect(audio.duration, 0.0); // the unknown sentinel survives
      expect(audio.lastPlayed, DateTime.parse('2025-12-31T23:59:59.000Z'));
      expect(audio.type, 'audio');
    });

    test('positionStaysAHistoryFactNotAMediaFact', () {
      // The resume point (733.5) has no MediaItem slot by design: it is a
      // playback fact consumed at open time (openAt semantics, SPEC §4.4
      // invariant 4), not a media fact. The mapper must not consume or
      // alter it — HistoryEntry keeps owning it.
      final entry = HistoryEntry.fromJson(
          (jsonDecode(spec7History)['entries'] as List<Object?>).first!
              as Map<Object?, Object?>);
      final item = mediaItemFromHistoryEntry(entry);

      expect(entry.position, 733.5); // untouched by mapping
      expect(item.duration, 1620.0); // duration is the media fact
      // The session carries the resume seconds when playback opens.
      const session = PlaybackSession(
          items: [MediaItem(path: 'p')], startIndex: 0, startPosition: 733.5);
      expect(session.startPosition, 733.5);
    });

    test('unparseableOrEmptyTimestampsDegradeToNull', () {
      final entry = HistoryEntry(
          path: '/a/b.mkv',
          title: 'b',
          position: 0.0,
          duration: 0.0,
          lastPlayedAt: 'not-a-date');
      expect(mediaItemFromHistoryEntry(entry).lastPlayed, isNull);

      final neverPlayed = HistoryEntry(
          path: '/a/c.mkv',
          title: 'c',
          position: 0.0,
          duration: 0.0,
          lastPlayedAt: '');
      expect(mediaItemFromHistoryEntry(neverPlayed).lastPlayed, isNull);
    });
  });

  group('library.json → MediaItem', () {
    test('mapsEveryFieldLosslessly', () {
      final entries = (jsonDecode(spec7Library)['entries'] as List<Object?>)
          .map((value) => LibraryEntry.fromJson(value! as Map<Object?, Object?>))
          .toList();

      final video = mediaItemFromLibraryEntry(entries[0]);
      expect(video.path, '/home/emo/Videos/Aurora OVA [1080p].mkv');
      expect(video.title, 'Aurora OVA');
      expect(video.type, 'video');
      expect(video.size, 146800640);
      // §7 sample writes lastPlayed as null → loads as "" → maps to null.
      expect(video.lastPlayed, isNull);
      // library.json carries no duration: unknown stays unknown.
      expect(video.duration, 0.0);

      final audio = mediaItemFromLibraryEntry(entries[1]);
      expect(audio.type, 'audio');
      expect(audio.size, 33554432);
      expect(audio.lastPlayed, DateTime.parse('2026-01-01T12:00:00.000Z'));
    });

    test('emptyTypePassesThroughUnchanged', () {
      // A foreign writer can store type "" (LibraryEntry.fromJson keeps
      // it); the model's vocabulary is not extended and no normalisation
      // is invented — "" stays "".
      final entry = LibraryEntry.fromJson(<Object?, Object?>{
        'path': '/x/odd.bin',
        'title': 'odd',
        'type': '',
        'size': 1,
        'lastPlayed': null,
      });
      expect(mediaItemFromLibraryEntry(entry).type, '');
    });
  });

  group('MediaItem ↔ PlayerPlaylistItem', () {
    test('playlistRoundTripKeepsPathAndTitle', () {
      const item = MediaItem(
        path: '/home/emo/Videos/Aurora OVA [1080p].mkv',
        title: 'Aurora OVA',
        type: 'video',
        size: 146800640,
        duration: 1620.0,
        container: 'matroska,webm',
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
      );

      final row = item.toPlaylistItem();
      expect(row.path, item.path);
      expect(row.title, item.title);

      final back = row.toMediaItem();
      // The (path, title) row round-trips into the model losslessly; the
      // extension slots are not row facts and reset to unknown.
      expect(back, MediaItem(path: item.path, title: item.title));
      expect(back.container, isNull);
      expect(back.videoCodec, isNull);
    });

    test('metaCacheMergeFillsExtensionSlotsViaCopyWith', () {
      // The M4-T4 seam: a store-derived item gains ffprobe facts without
      // losing them (copyWith merge, the field-losslessness contract of
      // the model layer).
      const base = MediaItem(
          path: '/a/b.mkv', title: 'b', type: 'video', size: 42);
      final merged = base.copyWith(
        container: 'matroska,webm',
        videoCodec: 'hevc',
        audioCodec: 'flac',
        width: 3840,
        height: 2160,
        duration: 1620.0,
      );

      expect(merged.path, base.path);
      expect(merged.title, base.title);
      expect(merged.type, base.type);
      expect(merged.size, base.size);
      expect(merged.container, 'matroska,webm');
      expect(merged.videoCodec, 'hevc');
      expect(merged.audioCodec, 'flac');
      expect(merged.width, 3840);
      expect(merged.height, 2160);
      expect(base == merged, isFalse);
      expect(base, base.copyWith()); // copyWith() with nothing is identity
      expect(base.hashCode, base.copyWith().hashCode);
    });
  });

  group('PlaybackSession', () {
    test('derivesFromMappedStoreEntries', () {
      final entries = (jsonDecode(spec7History)['entries'] as List<Object?>)
          .map((value) => HistoryEntry.fromJson(value! as Map<Object?, Object?>))
          .map(mediaItemFromHistoryEntry)
          .toList();

      final session = PlaybackSession(
        items: entries,
        startIndex: 1,
        startPosition: 733.5,
        origin: 'history',
      );

      expect(session.items, hasLength(2));
      expect(session.startItem!.path,
          '/home/emo/Music/Second Album/02 - Night Drive.flac');
      expect(session.startPosition, 733.5);
      expect(session.isMusic, isFalse);
      expect(PlaybackSession.knownOrigins, contains(session.origin));

      final same = PlaybackSession(
          items: entries, startIndex: 1, startPosition: 733.5, origin: 'history');
      expect(session == same, isTrue);
      expect(session.hashCode, same.hashCode);
    });

    test('emptySessionIsTheIdleState', () {
      const session = PlaybackSession.empty;
      expect(session.items, isEmpty);
      expect(session.isEmpty, isTrue);
      expect(session.startIndex, -1);
      expect(session.startItem, isNull);
      expect(session.startPosition, isNull);
      expect(session.isMusic, isFalse);
      expect(session.origin, isNull);

      // Out-of-range start index degrades to no start item, like the
      // player page's currentItem contract.
      const off = PlaybackSession(items: [MediaItem(path: '/a.mkv')], startIndex: 5);
      expect(off.startItem, isNull);
    });
  });

  group('store-level 1.x samples → model', () {
    test('storesLoadSampleFilesAndMapWithoutRewritingThem', () {
      // "1.x 真实文件样例进、模型出" at the store level: the sample
      // documents land on disk, the real stores load them, every entry
      // maps, and the files on disk stay byte-identical (the mapper layer
      // is read-only — the §7 rewrite contract belongs to the stores, not
      // here).
      final historyFile = File('${tempDir.path}/history.json')
        ..writeAsStringSync(spec7History);
      final libraryFile = File('${tempDir.path}/library.json')
        ..writeAsStringSync(spec7Library);
      final historyBytes = historyFile.readAsBytesSync();
      final libraryBytes = libraryFile.readAsBytesSync();

      final history = HistoryStore(null, historyFile.path);
      addTearDown(history.dispose);
      final library = LibraryStore(libraryFile.path);
      addTearDown(library.dispose);

      final items = <MediaItem>[
        for (final entry in history.entries) mediaItemFromHistoryEntry(entry),
        for (final entry in library.entryList) mediaItemFromLibraryEntry(entry),
      ];

      expect(items, hasLength(4));
      // The unique key is the path: history and library describe the same
      // two files, so the unified view agrees with the 1.x semantics.
      expect(items.map((item) => item.path).toSet(), hasLength(2));
      expect(
          items.where((item) => item.path == '/home/emo/Videos/Aurora OVA [1080p].mkv'),
          hasLength(2));

      // The store files were not touched by the mapping round.
      expect(historyFile.readAsBytesSync(), historyBytes);
      expect(libraryFile.readAsBytesSync(), libraryBytes);
    });
  });

  group('settings.json', () {
    test('carriesNoMediaEntriesForTheModelLayer', () {
      // The third §7 file is pure configuration: it has no media-entry
      // shape the unified model could map, so this layer deliberately
      // defines no settings→MediaItem mapper and never writes the file.
      // The pin keeps the "三份 JSON 一个字段不改" boundary explicit on
      // the model side (rewriting settings.json stays the stores' contract,
      // guarded by data_compat_spec7_test.dart / emoplay_settings_test.dart).
      final document = jsonDecode(spec7Settings) as Map<Object?, Object?>;
      expect(document.containsKey('entries'), isFalse);
      expect(document['quality'], isA<Map<Object?, Object?>>());
      expect(document['behavior'], isA<Map<Object?, Object?>>());
      expect(document['music'], isA<Map<Object?, Object?>>());
    });
  });
}
