import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/library_model.dart';
import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';

/// Headless unit tests for the P6 v2 thumbnail service. No real ffmpeg is
/// ever executed:
///  - pure logic (cache-key hashing, seek computation, duration parsing,
///    queue scheduling) is tested directly;
///  - the probe/generation process chain runs against a stub *shell script*
///    that emulates the three ffmpeg invocation shapes the service uses
///    (`-version`, `-i` duration probe, `-frames:v` frame grab). The stub is
///    written per test into a temp directory, so each test controls its own
///    behavior (banner validation, generation success/failure);
///  - the "ffmpeg missing" degradation path uses a binary path that cannot
///    exist.
/// The stub needs a POSIX shell; the Linux CI provides one (1.x had the same
/// Q_OS_UNIX guard).
///
/// Case-for-case port of mpv-emo tests/test_thumbnail_service.cpp; assertion
/// values are the behavioural contract and are copied verbatim. One value
/// changed deliberately: the frame-grab filter is scale=320:-2 — the 2.0
/// invariant (docs/SPEC.md §4.7) adopts the fix for the odd-height rejection
/// 1.x documented as a known limitation of its scale=320:-1.
void main() {
  late Directory tempDir;
  final shellAvailable = Platform.isLinux || Platform.isMacOS;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-thumbs-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // Non-empty placeholder payload for cache files. The service contract only
  // requires the file to exist and be non-empty; nothing in these tests
  // decodes image data, so the bytes need not be a decodable JPEG.
  List<int> stubImageBytes() => utf8.encode('stub-thumbnail-payload\n');

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  // Writes the stub image file and the ffmpeg stub script into |dir| and
  // returns the script path. The stub appends every argument vector it
  // receives to invocations.log so tests can assert the exact command lines
  // (one line per invocation, space-joined args). |durationSleepSeconds|
  // pauses the duration-probe stage, opening a deterministic in-flight
  // window for the queueing/teardown tests.
  Future<String> writeStub({
    bool failGenerate = false,
    bool badVersion = false,
    int durationSleepSeconds = 0,
  }) async {
    final jpegPath = '${tempDir.path}/stub-image.bin';
    await File(jpegPath).writeAsBytes(stubImageBytes());

    final logPath = '${tempDir.path}/invocations.log';
    final script = File('${tempDir.path}/ffmpeg-stub.sh');
    await script.writeAsString('''
#!/bin/sh
# ffmpeg stub for ThumbnailService tests — no real ffmpeg.
LOG='$logPath'
JPEG='$jpegPath'
FAIL_GENERATE='${failGenerate ? 1 : 0}'
BAD_VERSION='${badVersion ? 1 : 0}'
SLEEP='$durationSleepSeconds'

printf '%s\\n' "\$*" >> "\$LOG"

case " \$* " in
  *" -version "*)
    if [ "\$BAD_VERSION" = "1" ]; then
      echo "definitely not an ffmpeg"
    else
      echo "ffmpeg version 6.1.1-stub Copyright (c) stub"
    fi
    exit 0
    ;;
esac

case " \$* " in
  *" -frames:v "*)
    if [ "\$FAIL_GENERATE" = "1" ]; then
      echo "stub: generation failed" >&2
      exit 1
    fi
    out=""
    for a in "\$@"; do out="\$a"; done
    cat "\$JPEG" > "\$out"
    exit 0
    ;;
esac

# Duration probe: real ffmpeg exits 1 without an output file.
sleep "\$SLEEP"
echo "Input #0, matroska, from '\$2':" >&2
echo "  Duration: 00:02:00.00, start: 0.000000, bitrate: 1000 kb/s" >&2
echo "At least one output file must be specified" >&2
exit 1
''');
    await Process.run('chmod', <String>['755', script.path]);
    return script.path;
  }

  // Creates a fake media file (existence is all the service stats).
  Future<String> writeMediaFile({String name = 'movie.mkv'}) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsString('not really a video\n');
    return path;
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

  test('cachePathForIsSha1OfPathAndMtime', () {
    const path = '/media/movie.mkv';
    const mtimeMs = 1700000000000;

    final cachePath = ThumbnailService.cachePathFor('cache', path, mtimeMs);

    // Spec: <cacheDir>/<sha1(path + mtime)>.jpg — recomputed here from the
    // documented hash input.
    final expected = 'cache/'
        '${sha1.convert(utf8.encode(path) + utf8.encode('$mtimeMs'))}'
        '.jpg';
    expect(cachePath, expected);

    final name = cachePath.split('/').last;
    expect(RegExp(r'^[0-9a-f]{40}\.jpg$').hasMatch(name), isTrue);
  });

  test('cachePathForChangesWithMtime', () {
    const path = '/media/movie.mkv';
    final forMtime = ThumbnailService.cachePathFor('cache', path, 1700000000000);
    // Same inputs -> same name (stable), different mtime/path -> new name
    // (editing a file invalidates its thumbnail).
    expect(ThumbnailService.cachePathFor('cache', path, 1700000000000),
        forMtime);
    expect(
        ThumbnailService.cachePathFor('cache', path, 1700000000001),
        isNot(forMtime));
    expect(ThumbnailService.cachePathFor('cache', '${path}x', 1700000000000),
        isNot(forMtime));
  });

  test('seekPositionComputesTenPercent', () {
    // 10% of the duration, formatted for ffmpeg's -ss.
    expect(ThumbnailService.seekPositionFor(120.0), '12.000');
    expect(ThumbnailService.seekPositionFor(5.0), '0.500');
    // Unknown/invalid durations seek to 0.
    expect(ThumbnailService.seekPositionFor(0.0), '0.000');
    expect(ThumbnailService.seekPositionFor(-10.0), '0.000');
    expect(ThumbnailService.seekPositionFor(double.nan), '0.000');
  });

  test('durationParserHandlesFfmpegOutput', () {
    // The exact stderr shape ffmpeg prints for `-i file` with no output
    // (plus the trailing error and exit 1, which the parser ignores).
    const stderrText = 'Input #0, matroska, from \'movie.mkv\':\n'
        '  Metadata:\n'
        '  Duration: 00:02:00.00, start: 0.000000, bitrate: 1000 kb/s\n'
        'At least one output file must be specified\n';
    expect(ThumbnailService.durationFromFfmpegStderr(stderrText), 120.0);
    expect(
        ThumbnailService.durationFromFfmpegStderr(
            '  Duration: 01:00:00.500, start: 0.0'),
        3600.5);
    // "Duration: N/A" (live sources) and garbage -> unknown duration.
    expect(
        ThumbnailService.durationFromFfmpegStderr(
            '  Duration: N/A, start: 0.000000'),
        -1.0);
    expect(ThumbnailService.durationFromFfmpegStderr(''), -1.0);
  });

  test('queueDedupesAndKeepsFifoOrder', () {
    final queue = ThumbnailQueue();
    expect(queue.isEmpty, isTrue);
    expect(queue.size, 0);

    expect(queue.enqueue('a'), isTrue);
    expect(queue.enqueue('b'), isTrue);
    expect(queue.enqueue('a'), isFalse); // duplicate request: dropped
    expect(queue.enqueue(''), isFalse); // empty path: rejected
    expect(queue.size, 2);
    expect(queue.contains('a'), isTrue);
    expect(queue.contains('b'), isTrue);

    expect(queue.takeNext(), 'a'); // FIFO
    expect(queue.takeNext(), 'b');
    expect(queue.takeNext(), ''); // drained
    expect(queue.isEmpty, isTrue);

    expect(queue.enqueue('c'), isTrue);
    queue.clear();
    expect(queue.isEmpty, isTrue);
    expect(queue.contains('c'), isFalse);
  });

  test('probeAcceptsVersionBanner', () async {
    if (!shellAvailable) {
      return; // the ffmpeg stub script needs a POSIX shell
    }
    final stubPath = await writeStub();
    final service =
        ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
    addTearDown(service.dispose);

    await service.probe();
    expect(service.isAvailable, isTrue);
  });

  test('probeRejectsNonFfmpegBanner', () async {
    if (!shellAvailable) {
      return;
    }
    final stubPath = await writeStub(badVersion: true);
    final service =
        ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
    addTearDown(service.dispose);

    await service.probe();
    expect(service.isAvailable, isFalse);
  });

  test('probeMissingBinaryReportsUnavailable', () async {
    final service = ThumbnailService(
      '${tempDir.path}/thumbs',
      ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
    );
    addTearDown(service.dispose);

    await service.probe();
    expect(service.isAvailable, isFalse);
  });

  test('requestGeneratesThumbnailThroughStubChain', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final mtimeMs = File(mediaPath).statSync().modified.millisecondsSinceEpoch;
    final expectedCache =
        ThumbnailService.cachePathFor('${tempDir.path}/thumbs', mediaPath, mtimeMs);

    final stubPath = await writeStub();
    final service =
        ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
    addTearDown(service.dispose);
    await service.probe();
    expect(service.isAvailable, isTrue);

    final ready = <ThumbnailReady>[];
    final subscription = service.onThumbnailReady.listen(ready.add);
    addTearDown(subscription.cancel);
    service.requestThumbnail(mediaPath);
    await pumpUntil(() => ready.isNotEmpty);
    expect(ready.first.path, mediaPath);
    expect(ready.first.cacheFile, expectedCache);
    expect(service.cachedThumbnailPath(mediaPath), expectedCache);
    expect(File(expectedCache).existsSync(), isTrue);
    expect(File(expectedCache).lengthSync() > 0, isTrue);

    // The serial chain ran exactly two children: the duration probe
    // (`-i file`, expected exit 1) and the frame grab at 10% of the stub's
    // 120 s duration with the spec'd filter; the output path is the last
    // argument.
    final invocations =
        readInvocations('${tempDir.path}/invocations.log');
    expect(invocations, hasLength(3));
    expect(invocations[0], '-version');
    expect(invocations[1], '-i $mediaPath');
    expect(invocations[2], contains('-ss 12.000'));
    expect(invocations[2], contains('-i $mediaPath'));
    expect(invocations[2], contains('-frames:v 1'));
    // 2.0 invariant (SPEC §4.7): scale=320:-2 fixes the odd-height rejection
    // 1.x carried as a known limitation of -1.
    expect(invocations[2], contains('-vf scale=320:-2'));
    expect(invocations[2], endsWith(expectedCache));

    // Idempotent: an already-known-ready path is never regenerated.
    service.requestThumbnail(mediaPath);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(readInvocations('${tempDir.path}/invocations.log'), hasLength(3));
    expect(ready, hasLength(1));
  });

  test('requestFailureIsNotRetried', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final logPath = '${tempDir.path}/invocations.log';

    final stubPath = await writeStub(failGenerate: true);
    final service =
        ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
    addTearDown(service.dispose);
    await service.probe();
    expect(service.isAvailable, isTrue);

    final ready = <ThumbnailReady>[];
    final subscription = service.onThumbnailReady.listen(ready.add);
    addTearDown(subscription.cancel);
    service.requestThumbnail(mediaPath);
    // Three stub invocations: the -version probe, the duration probe and
    // the failed frame grab — then the queue stops.
    await pumpUntil(() => readInvocations(logPath).length >= 3);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ready, isEmpty);
    expect(service.cachedThumbnailPath(mediaPath), '');

    // No retry loop: still exactly three invocations later, and a repeated
    // request does not requeue the failed path.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(readInvocations(logPath), hasLength(3));
    service.requestThumbnail(mediaPath);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(readInvocations(logPath), hasLength(3));
    expect(ready, isEmpty);
  });

  test('requestWithMissingBinaryDegradesGracefully', () async {
    final mediaPath = await writeMediaFile();
    final cacheDir = '${tempDir.path}/thumbs';

    final service = ThumbnailService(
      cacheDir,
      ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
    );
    addTearDown(service.dispose);
    await service.probe();
    expect(service.isAvailable, isFalse);

    final ready = <ThumbnailReady>[];
    final subscription = service.onThumbnailReady.listen(ready.add);
    addTearDown(subscription.cancel);
    service.requestThumbnail(mediaPath);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ready, isEmpty);
    expect(service.cachedThumbnailPath(mediaPath), '');
    // Nothing was ever generated; the UI keeps its type icons.
    expect(
        Directory(cacheDir).listSync().whereType<File>().length, 0);
  });

  test('cacheHitIsServedWithoutFfmpeg', () async {
    final mediaPath = await writeMediaFile();
    final cacheDir = '${tempDir.path}/thumbs';
    await Directory(cacheDir).create(recursive: true);
    final expectedCache = ThumbnailService.cachePathFor(
        cacheDir,
        mediaPath,
        File(mediaPath).statSync().modified.millisecondsSinceEpoch);
    await File(expectedCache).writeAsBytes(stubImageBytes());

    // No ffmpeg at all: previously generated cache files are still served
    // (only generation needs the binary).
    final service = ThumbnailService(
      cacheDir,
      ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
    );
    addTearDown(service.dispose);
    await service.probe();
    expect(service.isAvailable, isFalse);

    final ready = <ThumbnailReady>[];
    final subscription = service.onThumbnailReady.listen(ready.add);
    addTearDown(subscription.cancel);
    service.requestThumbnail(mediaPath);
    await pumpUntil(() => ready.isNotEmpty);
    expect(ready.first.path, mediaPath);
    expect(ready.first.cacheFile, expectedCache);
    expect(service.cachedThumbnailPath(mediaPath), expectedCache);
  });

  test('requestThumbnailIsNotRequeuedWhileInFlight', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final logPath = '${tempDir.path}/invocations.log';
    final expectedCache = ThumbnailService.cachePathFor(
        '${tempDir.path}/thumbs',
        mediaPath,
        File(mediaPath).statSync().modified.millisecondsSinceEpoch);

    // A 1 s duration-probe sleep opens a wide in-flight window.
    final stubPath = await writeStub(durationSleepSeconds: 1);
    final service =
        ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
    addTearDown(service.dispose);
    await service.probe();
    expect(service.isAvailable, isTrue);

    final ready = <ThumbnailReady>[];
    final subscription = service.onThumbnailReady.listen(ready.add);
    addTearDown(subscription.cancel);
    service.requestThumbnail(mediaPath);
    // Chain in flight (duration probe asleep); the repeat request is what
    // the model sends on every rebuild — it must be dropped, not requeued.
    await pumpUntil(() => readInvocations(logPath).length >= 2); // -version + -i
    service.requestThumbnail(mediaPath);
    await pumpUntil(() => ready.isNotEmpty); // the first chain completes
    expect(service.cachedThumbnailPath(mediaPath), expectedCache);

    // No second chain for the same cache key: still exactly three stub
    // invocations (version, duration, generate) and one ready event.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(readInvocations(logPath), hasLength(3));
    expect(ready, hasLength(1));
  });

  test('disposeDoesNotHatchChildrenForQueuedWork', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final secondPath = await writeMediaFile(name: 'second.mkv');
    final logPath = '${tempDir.path}/invocations.log';
    final abortedCache = ThumbnailService.cachePathFor(
        '${tempDir.path}/thumbs',
        mediaPath,
        File(mediaPath).statSync().modified.millisecondsSinceEpoch);

    final stubPath = await writeStub(durationSleepSeconds: 1);
    final ready = <ThumbnailReady>[];
    {
      final service =
          ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: stubPath);
      await service.probe();
      expect(service.isAvailable, isTrue);
      final subscription = service.onThumbnailReady.listen(ready.add);
      service.requestThumbnail(mediaPath); // chain in flight (asleep)
      service.requestThumbnail(secondPath); // queued, never started
      await pumpUntil(() => readInvocations(logPath).length >= 2);
      expect(ready, isEmpty);
      // Destroy with a chain in flight and work queued: no generation stage
      // may hatch and the queued item must stay untouched (1.x
      // destructorDoesNotHatchChildrenForQueuedWork).
      service.dispose();
      subscription.cancel();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // The killed duration probe left the log at two lines; a reentering
    // teardown would advance to startGeneration (line 3) and then start the
    // queued second item (line 4).
    expect(readInvocations(logPath), hasLength(2));
    // The aborted chain never completed and never emitted ready.
    expect(ready, isEmpty);
    expect(File(abortedCache).existsSync(), isFalse);
  });

  group('LibraryModel thumbnail wiring', () {
    Future<String> writeLibraryFile(String realPath) async {
      final file = File('${tempDir.path}/library.json');
      await file.writeAsString(
          '{"version":1,"directories":[],"entries":['
          '{"path":"$realPath","title":"aaa","type":"video","size":10,"lastPlayed":""},'
          '{"path":"/nonexistent/gone.mkv","title":"zzz","type":"audio","size":20,"lastPlayed":""}]}');
      return file.path;
    }

    // Writes a two-entry library.json — |realPath| as "aaa" (row 0), a
    // nonexistent path as "zzz" (row 1) — so row indices are deterministic
    // (titles control the model's sort order).
    test('modelExposesThumbnailRole', () async {
      if (!shellAvailable) {
        return;
      }
      final mediaPath = await writeMediaFile();
      final libraryPath = await writeLibraryFile(mediaPath);
      final cacheDir = '${tempDir.path}/thumbs';
      final expectedCache = ThumbnailService.cachePathFor(
          cacheDir,
          mediaPath,
          File(mediaPath).statSync().modified.millisecondsSinceEpoch);

      final store = LibraryStore(libraryPath);
      addTearDown(store.dispose);
      expect(store.entryList, hasLength(2));

      final stubPath = await writeStub();
      final service =
          ThumbnailService(cacheDir, ffmpegBinary: stubPath);
      addTearDown(service.dispose);
      await service.probe();
      expect(service.isAvailable, isTrue);

      final model = LibraryModel(store, service);
      addTearDown(model.dispose);

      // Nothing cached yet: rows report empty thumbnails (placeholder).
      expect(model.thumbnailAt(0), '');
      expect(model.thumbnailAt(1), '');

      // Generation runs in the background; the model asks for thumbnails on
      // rebuild (its constructor), ready paths flow back through the
      // service notification (1.x dataChanged(ThumbnailRole)).
      await pumpUntil(() => model.thumbnailAt(0) == expectedCache);
      // The missing file never gets one.
      expect(model.thumbnailAt(1), '');
    });

    test('modelKeepsPlaceholderWhenServiceUnavailable', () async {
      final mediaPath = await writeMediaFile();
      final libraryPath = await writeLibraryFile(mediaPath);

      final store = LibraryStore(libraryPath);
      addTearDown(store.dispose);
      final service = ThumbnailService(
        '${tempDir.path}/thumbs',
        ffmpegBinary: '/nonexistent-dir-for-tests/ffmpeg-should-not-exist',
      );
      addTearDown(service.dispose);
      await service.probe();
      expect(service.isAvailable, isFalse);

      // The model's constructor rebuild already requested thumbnails; the
      // unavailable service drops them and the role stays empty (the grid
      // keeps its type icons). No crash, no queue growth on repeated
      // rebuilds.
      final model = LibraryModel(store, service);
      addTearDown(model.dispose);
      expect(model.count, 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(model.thumbnailAt(0), '');
      expect(model.thumbnailAt(1), '');

      // Re-filtering triggers another rebuild + requests; still graceful.
      model.filter = 'aaa';
      expect(model.count, 1);
      expect(model.thumbnailAt(0), '');
    });

  });
}
