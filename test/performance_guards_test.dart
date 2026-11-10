// Performance-invariant guards for the media pipeline — OVERNIGHT-LOOP §四
// backlog 7 ("性能") testable slice, R3 round. 1.x parity anchor: the scan
// ran on ONE worker QThread (mpv-emo src/library/LibraryStore.cpp:74) and
// thumbnails were generated "one process chain at a time (serial)"
// (mpv-emo src/library/ThumbnailService.h:16); 2.0 keeps both shapes
// (single worker isolate, serial generation chain), and these tests lock
// the responsiveness invariants that shape buys:
//
//   1. scanCancelLatency: a cancel that lands while the worker isolate's
//      walk is in flight stops the walk at file granularity — measured
//      wall-clock from cancelScan() to the partial result being applied.
//   2. scanProgressThrottled: the progress hint fires per ~32 files, never
//      per file (per-file signals would flood the GUI on big libraries —
//      lib/media/library_store.dart walk comment).
//   3. thumbnailGenerationIsSerial: with several files queued, at most ONE
//      stub ffmpeg child is ever in flight (verified with a flock(1)
//      marker; flock ships with util-linux — the test skips where the
//      binary is absent, mirroring the shellAvailable QSKIP-analog guard).
//
// Deliberately out of scope here: a hard scan-throughput wall-clock number
// and 首帧时间 (first frame) — the measured versions of those live in
// test/perf_scan_benchmark_test.dart (2026-11-11 性能定量实测 round,
// container Isolate timings, skip-if-fixture-missing); host-hardware
// numbers still belong to the GUI/manual acceptance round (SPEC §9);
// multi-isolate scan sharding is NOT adopted (1.x used a single worker
// thread; the cooperative per-file yield already bounds cancel latency,
// and a second isolate would break progress ordering for no measured need).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/library_store.dart';
import 'package:emoplay/media/thumbnail_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-perf-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('library scan responsiveness', () {
    // Enough files that the walk is provably still running by the time the
    // first progress reply lands, yet cheap to create (empty payload).
    const fileCount = 3000;

    Future<Directory> writeMediaFiles(String name) async {
      final media = Directory('${tempDir.path}/$name');
      await media.create();
      for (var i = 0; i < fileCount; i++) {
        await File('${media.path}/clip${i.toString().padLeft(5, '0')}.mkv')
            .writeAsString('x');
      }
      return media;
    }

    test('scanCancelLatencyIsBoundedAndPartialResultKept', () async {
      final media = await writeMediaFiles('cancel-latency');

      final store = LibraryStore('${tempDir.path}/library.json');
      addTearDown(store.dispose);

      expect(store.addDirectory(media.path), isTrue);
      // The first progress reply (32 files, the walk's throttle step) proves
      // the worker handshake is done and the walk is in flight; the cancel
      // sent right after must catch it mid-walk (the remaining walk is
      // thousands of event-loop turns — physically unable to drain before
      // the cancel message is processed between turns).
      await pumpUntil(() => store.scanFileCount >= 32);
      expect(store.isScanning, isTrue);

      final cancelSent = DateTime.now();
      store.cancelScan();
      await pumpUntil(() => !store.isScanning);
      final latency = DateTime.now().difference(cancelSent);

      // The worker polls the cancel flag per file and the walk yields one
      // turn per file (lib/media/library_store.dart walk loop), so the
      // partial result lands within a few turns — milliseconds, not the
      // 30 s job-shape timeouts elsewhere. 5 s is a ~100x headroom bound.
      expect(latency, lessThan(const Duration(seconds: 5)));

      // The cancel must not throw away progress: everything found before
      // the stop is applied, and the walk actually stopped early.
      expect(store.entryList.length, greaterThanOrEqualTo(32));
      expect(store.entryList.length, lessThan(fileCount));
      expect(store.lastScanCancelled, isTrue);

      // The store stays usable after the cancel (scan recovery is covered
      // in detail by library_store_test.dart; here only a fresh full scan
      // proving the walk drained everything).
      store.requestScan();
      await pumpUntil(
          () => !store.isScanning && store.entryList.length == fileCount);
      expect(store.lastScanCancelled, isFalse);
    });

    test('scanProgressIsThrottledNotPerFile', () async {
      final media = await writeMediaFiles('progress');

      final calls = <int>[];
      final entries = await LibraryStore.scanDirectories(
          [media.path], const ScanOptions(),
          progress: calls.add);

      expect(entries, hasLength(fileCount));
      // Intermediate steps land on the throttle boundary (every 32nd file),
      // the final call reports the total: 32/64/…/3000. What the invariant
      // forbids is per-file flooding — the bound, not the divisor, is the
      // contract (a tuned divisor must not break this test).
      expect(calls.last, fileCount);
      expect(calls.length, lessThanOrEqualTo(fileCount ~/ 32 + 1));
      expect(calls.length, greaterThanOrEqualTo(2));
      // Monotonic: each step reports the running total, never a regression.
      for (var i = 1; i < calls.length; i++) {
        expect(calls[i], greaterThan(calls[i - 1]));
      }
    });
  });

  group('thumbnail generation concurrency', () {
    final shellAvailable = Platform.isLinux || Platform.isMacOS;
    final flockAvailable =
        shellAvailable && Process.runSync('which', ['flock']).exitCode == 0;

    test('generationNeverRunsTwoFfmpegChildrenAtOnce', () async {
      if (!shellAvailable || !flockAvailable) {
        return; // flock(1) marker needs a POSIX shell + util-linux
      }
      const queuedFiles = 3;
      const probeSleepSeconds = 1;

      final paths = <String>[];
      for (var i = 0; i < queuedFiles; i++) {
        final path = '${tempDir.path}/movie$i.mkv';
        await File(path).writeAsString('not really a video\n');
        paths.add(path);
      }
      final jpegPath = '${tempDir.path}/stub-image.bin';
      await File(jpegPath).writeAsString('stub-thumbnail-payload\n');
      final logPath = '${tempDir.path}/invocations.log';
      final lockPath = '${tempDir.path}/serial.lock';
      final script = File('${tempDir.path}/ffmpeg-stub.sh');
      await script.writeAsString('''
#!/bin/sh
# ffmpeg stub with a cross-process in-flight marker: every invocation logs
# its argv, then tries a NON-blocking flock on a shared lock file. A second
# child starting while the first still holds the lock (the $probeSleepSeconds s
# duration-probe sleep) records a CONCURRENT line — the service contract
# (serial generation, ThumbnailService.h:16 in 1.x) forbids that.
LOG='$logPath'
LOCK='$lockPath'
JPEG='$jpegPath'
SLEEP='$probeSleepSeconds'

printf '%s\\n' "\$*" >> "\$LOG"
exec 9>"\$LOCK"
if ! flock -n 9; then
  echo "CONCURRENT:\$*" >> "\$LOG"
fi
flock 9

case " \$* " in
  *" -version "*)
    echo "ffmpeg version 6.1.1-stub Copyright (c) stub"
    exit 0
    ;;
esac
case " \$* " in
  *" -frames:v "*)
    out=""
    for a in "\$@"; do out="\$a"; done
    cat "\$JPEG" > "\$out"
    exit 0
    ;;
esac

# Duration probe: real ffmpeg exits 1 without an output file.
sleep "\$SLEEP"
echo "  Duration: 00:02:00.00, start: 0.000000" >&2
echo "At least one output file must be specified" >&2
exit 1
''');
      await Process.run('chmod', <String>['755', script.path]);

      final service =
          ThumbnailService('${tempDir.path}/thumbs', ffmpegBinary: script.path);
      addTearDown(service.dispose);
      await service.probe();
      expect(service.isAvailable, isTrue);

      for (final path in paths) {
        service.requestThumbnail(path);
      }

      // Serial: queuedFiles × (1 s probe + fast grab). The concurrency cap
      // is what is under test — give the serial shape a generous window.
      await pumpUntil(
          () => paths.every(
              (path) => service.cachedThumbnailPath(path).isNotEmpty),
          timeout: const Duration(seconds: 20));

      final log = File(logPath).readAsStringSync();
      final concurrent = log
          .split('\n')
          .where((line) => line.startsWith('CONCURRENT:'))
          .toList();
      expect(concurrent, isEmpty,
          reason: 'two stub children overlapped: $concurrent');

      // Every file was served through the full two-stage chain.
      final invocations = log
          .split('\n')
          .where((line) => line.isNotEmpty && !line.startsWith('CONCURRENT:'))
          .toList();
      expect(invocations, hasLength(1 + queuedFiles * 2));
      for (final path in paths) {
        expect(service.cachedThumbnailPath(path), isNotEmpty);
      }
    });
  });
}
