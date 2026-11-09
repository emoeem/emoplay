import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';

/// Robustness round (OVERNIGHT-LOOP §四 backlog #6, WORK_REPORT
/// 2026-11-10 §6.4 "健壮性轮"): the edge inputs the happy-path suites do not
/// cover. Every case here runs headless against real filesystem inputs —
/// no GUI, no real ffmpeg (the corrupt-media chain uses the same stub-script
/// pattern as test/thumbnail_service_test.dart).
///
/// Coverage map (what was already locked elsewhere, cross-referenced):
///  * no-ffmpeg degradation: thumbnail_service_test.dart
///    (probeMissingBinaryReportsUnavailable / requestWithMissingBinaryDegrades
///    Gracefully / cacheHitIsServedWithoutFfmpeg) — not duplicated here.
///  * corrupt *storage* files (library.json / history.json / settings.json):
///    corruptFileRecoversToEmpty in library_store_test.dart:445 and
///    history_store_test.dart:130, corruptFileResetsToDefaults in
///    emoplay_settings_test.dart:101 — this file covers corrupt *media*
///    files instead (scan-side extension contract + thumbnail-chain
///    terminal failure with the zero-seek fallback).
///  * empty-directory-list scans: requestScanWithoutDirectoriesKeepsEmpty
///    (library_store_test.dart:384) — this file covers the empty-*result*
///    cases (non-media-only folders, empty model) plus persistence shape.
///  * settings↔scanner wiring semantics: settings_service_semantics_test.dart
///    (port of the remaining mpv-emo test_settings_service.cpp slots).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-robust-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

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

  Future<void> chmod(String path, String mode) =>
      Process.run('chmod', <String>[mode, path]);

  // Denies all access to |directory| and reports whether the deny is
  // effective (listSync throws). Under root — or on a filesystem that
  // ignores permission bits — the walk would succeed, so the permission
  // cases skip instead of passing vacuously (the QSKIP contract's shape:
  // thumbnail_service_test.dart guards POSIX-only stubs the same way).
  // Permissions are restored before returning either way, so the tearDown
  // recursive delete always succeeds.
  Future<bool> denyIsEffective(Directory directory) async {
    await chmod(directory.path, '000');
    try {
      directory.listSync();
      await chmod(directory.path, '755'); // root / noexec-mode fs: skip
      return false;
    } catch (_) {
      return true;
    }
  }

  List<String> readInvocations(String logPath) {
    final log = File(logPath);
    if (!log.existsSync()) {
      return const <String>[];
    }
    return log
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  group('super-long paths', () {
    test('scanHandlesMaxByteFileNameComponent', () async {
      // Linux NAME_MAX = 255 bytes per component: a 250-byte stem + '.mkv'
      // fits; the scan must classify it by extension and report the real
      // byte size (size read is wrapped in try/catch at
      // library_store.dart:421-426 — here it must not need the fallback).
      final name = 'a' * 250;
      final file = File('${tempDir.path}/$name.mkv');
      await file.writeAsString('x' * 7);

      final entries = await LibraryStore.scanDirectories(
        [tempDir.path],
        const ScanOptions(maxDepth: 0),
      );

      expect(entries, hasLength(1));
      expect(entries.first.title, name); // completeBaseName semantics
      expect(entries.first.type, 'video');
      expect(entries.first.size, 7);
      expect(entries.first.path, file.path);
    });

    test('scanFindsFileInDeepNesting', () async {
      // 80 nested directories with 30-byte names (~2.5 KB path, safely under
      // PATH_MAX but far beyond the default scan depth): with maxDepth 0
      // (unlimited) the walk must reach the deepest file.
      var path = tempDir.path;
      for (var i = 0; i < 80; i++) {
        path = '$path/${'d' * 30}';
      }
      await Directory(path).create(recursive: true);
      final deep = File('$path/deep.mkv');
      await deep.writeAsString('x' * 5);

      final entries = await LibraryStore.scanDirectories(
        [tempDir.path],
        const ScanOptions(maxDepth: 0),
      );

      expect(entries, hasLength(1));
      expect(entries.first.path, deep.path);
      expect(entries.first.size, 5);
    });

    test('cacheKeyStaysFixedWidthForBeyondLimitPaths', () {
      // A path string beyond PATH_MAX (4096 on Linux) never reaches the
      // filesystem, but the pure cache-key function must still produce the
      // bounded <sha1>.jpg name (sha1 of the raw UTF-8 bytes).
      final overLimit = '/media/${'x' * 6000}.mkv';
      expect(overLimit.length, greaterThan(4096));

      final cache = ThumbnailService.cachePathFor('cache', overLimit, 123);
      expect(
        RegExp(r'cache/[0-9a-f]{40}\.jpg$').hasMatch(cache),
        isTrue,
      );
      // Distinct over-limit paths still hash apart.
      expect(
        ThumbnailService.cachePathFor('cache', '${overLimit}x', 123),
        isNot(cache),
      );
    });

    test('thumbnailRequestOnBeyondLimitPathDropsSilently', () async {
      // requestThumbnail() stats the file first (thumbnail_service.dart:227).
      // A beyond-PATH_MAX path cannot exist as a file, so the stat resolves
      // to "not a file" and the request is dropped: no throw, no queue
      // growth, no thumbnail (the stale-library-entry contract).
      final overLimit = '/media/${'x' * 6000}.mkv';
      final service = ThumbnailService(
        '${tempDir.path}/thumbs',
        ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
      );
      addTearDown(service.dispose);

      expect(
        () => service.requestThumbnail(overLimit),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.cachedThumbnailPath(overLimit), '');

      // The service stays usable for normal paths afterwards: the request
      // is stat'ed, queued for generation and then dropped by the
      // unavailable-ffmpeg guard (thumbnail_service.dart:251-256) — no
      // throw, no ready event, empty thumbnail role.
      final ready = <ThumbnailReady>[];
      final subscription = service.onThumbnailReady.listen(ready.add);
      addTearDown(subscription.cancel);
      final normal = File('${tempDir.path}/normal.mkv');
      await normal.writeAsString('x');
      expect(
        () => service.requestThumbnail(normal.path),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.cachedThumbnailPath(normal.path), '');
      expect(ready, isEmpty);
    });
  });

  group('permission-denied directories', () {
    test('scanSkipsUnreadableSubdirectoryAndKeepsSiblings', () async {
      final locked = Directory('${tempDir.path}/locked');
      await locked.create();
      await File('${locked.path}/locked.mkv').writeAsString('x');
      final sibling = File('${tempDir.path}/a.mkv');
      await sibling.writeAsString('x' * 3);

      if (!await denyIsEffective(locked)) {
        return; // root or mode-ignoring filesystem: case not exercisable
      }
      try {
        // The unreadable level is not collectable (listSync failure caught
        // at library_store.dart:368-375) but must not abort the walk: the
        // sibling file is still found.
        final entries = await LibraryStore.scanDirectories(
          [tempDir.path],
          const ScanOptions(maxDepth: 0),
        );
        expect(entries, hasLength(1));
        expect(entries.first.path, sibling.path);
        expect(entries.first.size, 3);
      } finally {
        await chmod(locked.path, '755');
      }
    });

    test('scanOfUnreadableRootYieldsEmptyWithoutThrow', () async {
      final locked = Directory('${tempDir.path}/locked-root');
      await locked.create();
      await File('${locked.path}/inside.mkv').writeAsString('x');

      if (!await denyIsEffective(locked)) {
        return;
      }
      try {
        // The root itself exists (stat on the path only needs +x on the
        // parent), so the walk runs and fails on listSync — an empty result,
        // never an exception out of scanDirectories.
        expect(locked.existsSync(), isTrue);
        final entries = await LibraryStore.scanDirectories(
          [locked.path],
          const ScanOptions(maxDepth: 0),
        );
        expect(entries, isEmpty);
      } finally {
        await chmod(locked.path, '755');
      }
    });

    test('storeScanCompletesWithLockedSubdirectory', () async {
      // Through the real worker isolate: an unreadable branch inside a
      // scanned folder must not kill the isolate or leave isScanning stuck
      // (the worker-death recovery at library_store.dart:613-627 exists for
      // genuine crashes — a permission error is a caught walk failure, the
      // scan completes normally and persists).
      final media = Directory('${tempDir.path}/media');
      await media.create();
      await File('${media.path}/a.mkv').writeAsString('x' * 5);
      final locked = Directory('${media.path}/locked');
      await locked.create();
      await File('${locked.path}/locked.mkv').writeAsString('x');

      if (!await denyIsEffective(locked)) {
        return;
      }
      try {
        final store = LibraryStore('${tempDir.path}/library.json');
        addTearDown(store.dispose);

        expect(store.addDirectory(media.path), isTrue);
        await pumpUntil(() => !store.isScanning);
        expect(store.entryList, hasLength(1));
        expect(store.entryList.first.path, '${media.path}/a.mkv');
        expect(store.lastScanCancelled, isFalse);

        // The partial-but-healthy result was persisted (empty-entries shape
        // is covered separately; here: exactly the readable file).
        final document =
            jsonDecode(File('${tempDir.path}/library.json').readAsStringSync())
                as Map<Object?, Object?>;
        expect(document['version'], 1);
        expect((document['entries'] as List<Object?>), hasLength(1));
      } finally {
        await chmod(locked.path, '755');
      }
    });
  });

  group('corrupt media files', () {
    // Stub ffmpeg for corrupt inputs: probe stage reports "Duration: N/A"
    // (what real ffmpeg prints for an unparseable/corrupt stream), frame
    // grab always fails. The invocation log lets the test pin the fallback
    // seek and the terminal failure.
    Future<String> writeCorruptStub() async {
      final logPath = '${tempDir.path}/invocations.log';
      final script = File('${tempDir.path}/ffmpeg-stub.sh');
      await script.writeAsString('''
#!/bin/sh
# ffmpeg stub for corrupt-media inputs: duration probe answers N/A, the
# frame grab fails without writing output.
LOG='$logPath'

printf '%s\\n' "\$*" >> "\$LOG"

case " \$* " in
  *" -version "*)
    echo "ffmpeg version 6.1.1-stub Copyright (c) stub"
    exit 0
    ;;
esac

case " \$* " in
  *" -frames:v "*)
    echo "stub: generation failed (corrupt input)" >&2
    exit 1
    ;;
esac

echo "  Duration: N/A, start: 0.000000" >&2
echo "At least one output file must be specified" >&2
exit 1
''');
      await Process.run('chmod', <String>['755', script.path]);
      return script.path;
    }

    test('scanCountsCorruptAndZeroByteFilesByExtension', () async {
      // Scanning is extension-based by contract (library_store.dart:500-509,
      // "no content sniffing"): garbage bytes and zero-byte files carrying a
      // media suffix are library entries with their true sizes. Playback
      // robustness is mpv's own concern, not the library's.
      final corrupt = File('${tempDir.path}/corrupt.mkv');
      await corrupt.writeAsBytes(
          utf8.encode('not a real video') + const <int>[0, 1, 2, 255]);
      final empty = File('${tempDir.path}/empty.mp4');
      await empty.create();

      final entries = await LibraryStore.scanDirectories(
        [tempDir.path],
        const ScanOptions(maxDepth: 0),
      );

      expect(entries, hasLength(2));
      expect(entries.first.title, 'corrupt');
      expect(entries.first.type, 'video');
      expect(entries.first.size, corrupt.lengthSync());
      expect(entries.last.title, 'empty');
      expect(entries.last.type, 'video');
      expect(entries.last.size, 0);
    });

    test('thumbnailChainOnCorruptMediaFallsBackToZeroSeekAndStops',
        () async {
      final cacheDir = '${tempDir.path}/thumbs';
      final corrupt = File('${tempDir.path}/corrupt.mkv');
      await corrupt.writeAsBytes(
          utf8.encode('not a real video') + const <int>[0, 1, 2, 255]);
      final empty = File('${tempDir.path}/empty.mp4');
      await empty.create();

      final stubPath = await writeCorruptStub();
      final service = ThumbnailService(cacheDir, ffmpegBinary: stubPath);
      addTearDown(service.dispose);
      await service.probe();
      expect(service.isAvailable, isTrue);

      final ready = <ThumbnailReady>[];
      final subscription = service.onThumbnailReady.listen(ready.add);
      addTearDown(subscription.cancel);
      service.requestThumbnail(corrupt.path);
      service.requestThumbnail(empty.path);

      // Two serial chains: 1 probe + 2 stages each = 5 invocations total.
      final logPath = '${tempDir.path}/invocations.log';
      await pumpUntil(() => readInvocations(logPath).length >= 5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final invocations = readInvocations(logPath);
      expect(invocations, hasLength(5));
      expect(invocations[0], '-version');
      // Both corrupt inputs ran a duration probe…
      final probes =
          invocations.where((line) => line.startsWith('-i ')).toList();
      expect(probes, hasLength(2));
      expect(probes, contains('-i ${corrupt.path}'));
      expect(probes, contains('-i ${empty.path}'));
      // …and both frame grabs sought the zero fallback (duration parser
      // returned -1 for "Duration: N/A", seekPositionFor clamped to 0.000).
      final grabs = invocations
          .where((line) => line.contains('-frames:v'))
          .toList();
      expect(grabs, hasLength(2));
      for (final grab in grabs) {
        expect(grab, contains('-ss 0.000'));
      }

      // Terminal failure: nothing became ready, no cache files, and the
      // paths will not be retried within this session (_failed,
      // thumbnail_service.dart:251-256) — repeating the model's request
      // pattern adds no invocations.
      expect(ready, isEmpty);
      expect(service.cachedThumbnailPath(corrupt.path), '');
      expect(service.cachedThumbnailPath(empty.path), '');
      expect(
        Directory(cacheDir).listSync().whereType<File>(),
        isEmpty,
      );
      service.requestThumbnail(corrupt.path);
      service.requestThumbnail(empty.path);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(readInvocations(logPath), hasLength(5));
    });
  });

  group('empty library', () {
    test('scanOfNonMediaOnlyDirectoryPersistsEmptyEntries', () async {
      // A folder the user added but that holds only non-media files: the
      // scan completes through the real worker isolate with zero entries
      // and the persisted library.json keeps the documented §7 shape
      // ({"version":1,"directories":[…],"entries":[]}).
      await File('${tempDir.path}/readme.txt').writeAsString('notes');
      await File('${tempDir.path}/cover.nfo').writeAsString('info');

      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);

      expect(store.addDirectory(tempDir.path), isTrue);
      await pumpUntil(() => !store.isScanning);

      expect(store.entryList, isEmpty);
      expect(store.scanFileCount, 0);
      expect(store.lastScanCancelled, isFalse);

      final document =
          jsonDecode(File('${tempDir.path}/library.json').readAsStringSync())
              as Map<Object?, Object?>;
      expect(document['version'], 1);
      expect(document['directories'], <String>[tempDir.path]);
      expect(document['entries'], <Object?>[]);
    });

    test('modelOverEmptyLibraryHasZeroRowsAndEmptyRoles', () async {
      final libraryPath = '${tempDir.path}/library.json';
      await File(libraryPath).writeAsString(
          '{"version":1,"directories":[],"entries":[]}');

      final store = LibraryStore(libraryPath);
      addTearDown(store.dispose);
      // ffmpeg missing: even if rows existed, no thumbnails would arrive.
      final service = ThumbnailService(
        '${tempDir.path}/thumbs',
        ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
      );
      addTearDown(service.dispose);
      await service.probe();
      expect(service.isAvailable, isFalse);

      final model = LibraryModel(store, service);
      addTearDown(model.dispose);

      expect(model.count, 0);
      // Out-of-range roles stay guarded (library_model.dart:100-112) — the
      // grid binds roles for every index it renders, including an empty one.
      expect(model.titleAt(0), '');
      expect(model.thumbnailAt(0), '');

      // Filtering an empty model stays empty (no requests, no crash).
      model.filter = 'anything';
      expect(model.count, 0);
      expect(model.thumbnailAt(0), '');
    });
  });
}
