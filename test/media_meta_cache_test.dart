import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/media_meta_cache.dart';
import 'package:emoplay/media/thumbnail_service.dart';

/// Headless unit tests for the M4-T4 metadata cache (EmoPlay 3.0 roadmap
/// docs/EMOPLAY-3.0-ROADMAP.md §四 step 3, M4-T4). No real ffprobe is ever
/// executed:
///  - pure logic (the shared sha1 key, the ffprobe JSON parsers) is tested
///    directly;
///  - the probe/two-stage chain runs against a stub *shell script* that
///    emulates the ffprobe invocation shapes the cache uses (`-version`,
///    `-show_format`, `-show_streams`), with per-test failure/hang knobs —
///    the same harness pattern as test/thumbnail_service_test.dart;
///  - the "ffprobe missing" degradation path uses a binary path that
///    cannot exist.
///
/// The performance guard lives here too (roadmap M4-T4 verification:
/// "缓存命中不触发进程"): a cache hit must complete without spawning any
/// child, asserted through the stub's invocation log.
void main() {
  late Directory tempDir;
  final shellAvailable = Platform.isLinux || Platform.isMacOS;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-meta-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // Local function (Dart has no local getters): the path moves with
  // every test's fresh temp dir.
  String metaFilePath() => '${tempDir.path}/media_meta.json';

  // Canned real-shape ffprobe output (ffprobe 8.0, verified 2026-11-12);
  // the streams fixture leads with an attached-pic cover stream — the case
  // every mp3/m4a with embedded art produces — before the real video.
  const String stubFormatJson = '{"format": {"filename": "x.mkv", '
      '"format_name": "matroska,webm", "duration": "120.000000"}}';
  const String stubStreamsJson = '{"streams": ['
      '{"codec_type": "video", "codec_name": "mjpeg", "width": 600, '
      '"height": 600, "disposition": {"attached_pic": 1}},'
      '{"codec_type": "video", "codec_name": "h264", "width": 1920, '
      '"height": 1080, "disposition": {"attached_pic": 0}},'
      '{"codec_type": "audio", "codec_name": "aac", "width": null, '
      '"height": null, "disposition": {"attached_pic": 0}}]}';

  // Writes the ffprobe stub script into |dir| and returns its path. Every
  // invocation appends its argument vector to invocations.log (one
  // space-joined line each) so tests can assert exact command lines AND
  // that no child was spawned at all. Knobs: failStreams makes the
  // -show_streams stage exit 1; hangStages makes every probe stage (not
  // -version) sleep forever, recording its pid first for kill assertions.
  Future<String> writeStub({
    bool failStreams = false,
    bool hangStages = false,
  }) async {
    final logPath = '${tempDir.path}/invocations.log';
    final formatPath = '${tempDir.path}/format.json';
    final streamsPath = '${tempDir.path}/streams.json';
    final markerPath = '${tempDir.path}/hung.pid';
    await File(formatPath).writeAsString(stubFormatJson);
    await File(streamsPath).writeAsString(stubStreamsJson);

    final script = File('${tempDir.path}/ffprobe-stub.sh');
    await script.writeAsString('''
#!/bin/sh
# ffprobe stub for MediaMetaCache tests — no real ffprobe.
LOG='$logPath'
FORMAT='$formatPath'
STREAMS='$streamsPath'
FAIL_STREAMS='${failStreams ? 1 : 0}'
HANG='${hangStages ? 1 : 0}'
MARKER='$markerPath'

printf '%s\\n' "\$*" >> "\$LOG"

case " \$* " in
  *" -version "*)
    echo "ffprobe version 7.0-stub"
    exit 0
    ;;
esac

if [ "\$HANG" = "1" ]; then
  echo \$\$ > "\$MARKER"
  while true; do sleep 0.1; done
fi

case " \$* " in
  *" -show_format "*)
    cat "\$FORMAT"
    exit 0
    ;;
esac

case " \$* " in
  *" -show_streams "*)
    if [ "\$FAIL_STREAMS" = "1" ]; then
      echo "stub: streams stage failed" >&2
      exit 1
    fi
    cat "\$STREAMS"
    exit 0
    ;;
esac

exit 1
''');
    await Process.run('chmod', <String>['755', script.path]);
    return script.path;
  }

  // Creates a fake media file (existence + mtime are all the cache stats).
  Future<String> writeMediaFile({String name = 'movie.mkv'}) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsString('not really a video\n');
    return path;
  }

  List<String> readInvocations() {
    final log = File('${tempDir.path}/invocations.log');
    if (!log.existsSync()) {
      return const <String>[];
    }
    return log
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  test('cacheKeyIsTheThumbnailSha1Key', () {
    const path = '/media/movie.mkv';
    const mtimeMs = 1700000000000;

    // "键沿用 thumbnail_service 的 sha1(path+mtimeMs)": the key must be the
    // basename ThumbnailService.cachePathFor hashes for the same inputs.
    final thumbnailPath =
        ThumbnailService.cachePathFor('/any/dir', path, mtimeMs);
    expect(MediaMetaCache.cacheKeyFor(path, mtimeMs),
        thumbnailPath.split('/').last.replaceAll('.jpg', ''));
    expect(RegExp(r'^[0-9a-f]{40}$')
        .hasMatch(MediaMetaCache.cacheKeyFor(path, mtimeMs)), isTrue);

    // Same inputs stable; a changed mtime/path moves the key (an edited
    // file invalidates both caches with one mtime bump).
    expect(MediaMetaCache.cacheKeyFor(path, mtimeMs),
        MediaMetaCache.cacheKeyFor(path, mtimeMs));
    expect(MediaMetaCache.cacheKeyFor(path, mtimeMs + 1),
        isNot(MediaMetaCache.cacheKeyFor(path, mtimeMs)));
    expect(MediaMetaCache.cacheKeyFor('${path}x', mtimeMs),
        isNot(MediaMetaCache.cacheKeyFor(path, mtimeMs)));
  });

  test('streamsParserSkipsAttachedPicAndMalformedInput', () {
    final meta = streamsMetaFromFfprobeJson(stubStreamsJson);
    // The cover-art stream (mjpeg 600x600, attached_pic=1) is not the
    // video: the primary video stream wins.
    expect(meta.videoCodec, 'h264');
    expect(meta.width, 1920);
    expect(meta.height, 1080);
    expect(meta.audioCodec, 'aac');

    expect(containerFromFfprobeJson(stubFormatJson), 'matroska,webm');
    expect(
        containerFromFfprobeJson('{"format": {"format_name": ""}}'), isNull);
    expect(containerFromFfprobeJson('{"format": {}}'), isNull);

    // Malformed / wrong-shape documents degrade, never throw.
    expect(containerFromFfprobeJson('not json {'), isNull);
    expect(containerFromFfprobeJson('[]'), isNull);
    expect(streamsMetaFromFfprobeJson('not json {'), const MediaMeta());
    expect(streamsMetaFromFfprobeJson('{"streams": "x"}'), const MediaMeta());
    expect(streamsMetaFromFfprobeJson('{"streams": [{"codec_type": "video"}]}'),
        const MediaMeta());
    // Audio-only file: no video facts, audio codec kept.
    expect(
        streamsMetaFromFfprobeJson(
            '{"streams": [{"codec_type": "audio", "codec_name": "flac"}]}'),
        const MediaMeta(audioCodec: 'flac'));
  });

  test('twoStageChainProducesFullMetaAndPersistsIt', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final stubPath = await writeStub();

    final cache = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: stubPath);
    addTearDown(cache.dispose);
    await cache.probe();
    expect(cache.isAvailable, isTrue);

    final meta = await cache.requestMeta(mediaPath);
    expect(meta, isNotNull);
    expect(meta!.container, 'matroska,webm');
    expect(meta.videoCodec, 'h264');
    expect(meta.audioCodec, 'aac');
    expect(meta.width, 1920);
    expect(meta.height, 1080);

    // The two-stage chain ran exactly: version probe, then -show_format,
    // then -show_streams, each as a proper process-list argv.
    final invocations = readInvocations();
    expect(invocations, hasLength(3));
    expect(invocations[0], '-version');
    expect(invocations[1],
        '-v error -print_format json -show_format $mediaPath');
    expect(invocations[2],
        '-v error -print_format json -show_streams $mediaPath');

    // The record landed in media_meta.json (new file) under the sha1 key,
    // and a fresh instance on the same file reads the same value back.
    final key = MediaMetaCache.cacheKeyFor(
        mediaPath, File(mediaPath).statSync().modified.millisecondsSinceEpoch);
    final written =
        jsonDecode(File(metaFilePath()).readAsStringSync()) as Map<Object?, Object?>;
    expect(written['version'], 1);
    expect((written['entries'] as Map<Object?, Object?>)[key], isNotNull);

    final reloaded =
        MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: stubPath);
    addTearDown(reloaded.dispose);
    expect(reloaded.metaFor(mediaPath), meta);
  });

  test('cacheHitSpawnsNoProcesses', () async {
    // Performance guard (M4-T4: "缓存命中不触发进程"): a hit answers from
    // the map — no ffprobe child, not even a version probe, and it works
    // with the binary entirely absent (only generation needs it).
    final mediaPath = await writeMediaFile();
    final key = MediaMetaCache.cacheKeyFor(
        mediaPath, File(mediaPath).statSync().modified.millisecondsSinceEpoch);
    const stored = MediaMeta(
        container: 'matroska,webm',
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080);
    await File(metaFilePath()).writeAsString(jsonEncode(<String, Object?>{
      'version': 1,
      'entries': <String, Object?>{key: stored.toJson()},
    }));

    // No probe() call, nonexistent binary: the hit path must not care.
    final cache = MediaMetaCache(
      filePath: metaFilePath(),
      ffprobeBinary: '/nonexistent-dir-for-tests/ffprobe-should-not-exist',
    );
    addTearDown(cache.dispose);

    expect(cache.metaFor(mediaPath), stored); // synchronous lookup
    expect(await cache.requestMeta(mediaPath), stored); // async hit
    expect(readInvocations(), isEmpty); // zero children spawned
    expect(File('${tempDir.path}/invocations.log').existsSync(), isFalse);
  });

  test('corruptJsonDegradesToEmptyCacheAndRebuilds', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    await File(metaFilePath()).writeAsString('{ this is not json');

    final cache = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: await writeStub());
    addTearDown(cache.dispose);
    await cache.probe();
    expect(cache.isAvailable, isTrue);
    // Corrupt file → empty in-memory cache, no throw.
    expect(cache.metaFor(mediaPath), isNull);

    // The next request probes fresh and overwrites the corrupt file.
    final meta = await cache.requestMeta(mediaPath);
    expect(meta!.container, 'matroska,webm');
    final reloaded = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: 'irrelevant');
    addTearDown(reloaded.dispose);
    expect(reloaded.metaFor(mediaPath), meta);
  });

  test('timeoutForceKillsHungProbeAndDoesNotRetry', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final stubPath = await writeStub(hangStages: true);

    final cache = MediaMetaCache(
      filePath: metaFilePath(),
      ffprobeBinary: stubPath,
      jobTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(cache.dispose);
    await cache.probe();
    expect(cache.isAvailable, isTrue);

    final meta = await cache.requestMeta(mediaPath);
    // Both stages were killed at the budget: nothing cached, key failed.
    expect(meta, isNull);
    expect(cache.metaFor(mediaPath), isNull);

    // The force kill actually landed: the hung child recorded in the
    // marker no longer exists (SIGTERM default disposition).
    final marker = File('${tempDir.path}/hung.pid');
    expect(marker.existsSync(), isTrue);
    final pid = int.parse(marker.readAsStringSync().trim());
    final alive = await Process.run('kill', <String>['-0', '$pid']);
    expect(alive.exitCode, isNot(0), reason: 'hung ffprobe stub still alive');

    // The chain ran version + stage 1 + stage 2 = three invocations; the
    // failed key is not retried (a repeated request spawns nothing more).
    expect(readInvocations(), hasLength(3));
    expect(await cache.requestMeta(mediaPath), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(readInvocations(), hasLength(3));
  });

  test('missingFfprobeDegradesGracefully', () async {
    final mediaPath = await writeMediaFile();

    final cache = MediaMetaCache(
      filePath: metaFilePath(),
      ffprobeBinary: '/nonexistent-dir-for-tests/ffprobe-should-not-exist',
    );
    addTearDown(cache.dispose);
    await cache.probe();
    expect(cache.isAvailable, isFalse);

    // Requests complete null, spawn nothing, and never throw.
    expect(await cache.requestMeta(mediaPath), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(readInvocations(), isEmpty);
    expect(File(metaFilePath()).existsSync(), isFalse);
  });

  test('streamsStageFailureKeepsContainerOnly', () async {
    if (!shellAvailable) {
      return;
    }
    final mediaPath = await writeMediaFile();
    final stubPath = await writeStub(failStreams: true);

    final cache = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: stubPath);
    addTearDown(cache.dispose);
    await cache.probe();

    final meta = await cache.requestMeta(mediaPath);
    // Partial degradation: the format stage survived, so its fact is kept.
    expect(meta, isNotNull);
    expect(meta!.container, 'matroska,webm');
    expect(meta.videoCodec, isNull);
    expect(meta.audioCodec, isNull);
    expect(meta.width, isNull);
    expect(meta.height, isNull);

    final reloaded = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: stubPath);
    addTearDown(reloaded.dispose);
    expect(reloaded.metaFor(mediaPath), meta);
  });

  test('unstatablePathsAnswerNullWithoutProbing', () async {
    if (!shellAvailable) {
      return;
    }
    final stubPath = await writeStub();
    final cache = MediaMetaCache(filePath: metaFilePath(), ffprobeBinary: stubPath);
    addTearDown(cache.dispose);
    await cache.probe();

    // A missing file and a directory have no cache key at all; the
    // empty path is the clean no-op. None of them may spawn a stage child
    // (the invocation log keeps exactly the one -version probe line the
    // setup above produced).
    expect(await cache.requestMeta('/nonexistent-dir-for-tests/gone.mkv'), isNull);
    expect(await cache.requestMeta(tempDir.path), isNull);
    expect(await cache.requestMeta(''), isNull);
    expect(cache.metaFor('/nonexistent-dir-for-tests/gone.mkv'), isNull);
    expect(readInvocations(), <String>['-version']);
  });
}
