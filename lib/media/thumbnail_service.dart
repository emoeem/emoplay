import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

// Kill hung ffmpeg children after this long (network sources, corrupt files).
const Duration _kJobTimeout = Duration(seconds: 30);

// The stderr line ffmpeg prints per input: "Duration: HH:MM:SS.mmm".
final RegExp _durationRegex =
    RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)');

// Pure queue-scheduling logic for ThumbnailService: the set of media paths
// waiting for thumbnail generation, FIFO ordered. Membership is a Set so
// duplicate requests are cheap to detect; the parallel list keeps the arrival
// order (a Set alone has no stable iteration order).
//
// No I/O, no processes — directly unit-testable headless (see
// test/thumbnail_service_test.dart). ThumbnailService drives it: enqueue on
// request, takeNext() when the serial generation chain is idle.
class ThumbnailQueue {
  final List<String> _order = <String>[];
  final Set<String> _membership = <String>{};

  // Queue |path| unless it is already queued. Returns true when newly
  // queued, false for duplicates.
  bool enqueue(String path) {
    if (path.isEmpty || _membership.contains(path)) {
      return false;
    }
    _membership.add(path);
    _order.add(path);
    return true;
  }

  // Pop the next path in FIFO order; empty string when drained.
  String takeNext() {
    if (_order.isEmpty) {
      return '';
    }
    final next = _order.removeAt(0);
    _membership.remove(next);
    return next;
  }

  bool contains(String path) => _membership.contains(path);
  bool get isEmpty => _order.isEmpty;
  int get size => _order.length;

  void clear() {
    _order.clear();
    _membership.clear();
  }
}

enum _JobStage { durationProbe, generate }

// One ready thumbnail: the library path and the cache file it maps to.
@immutable
class ThumbnailReady {
  const ThumbnailReady(this.path, this.cacheFile);

  final String path;
  final String cacheFile;
}

// On-demand thumbnail service for the P6 media library (P6 v2).
//
// Probes ffmpeg once (`ffmpeg -version` via Process, async). When ffmpeg is
// available, requested library entries get a JPEG thumbnail generated in the
// background, one process chain at a time (serial):
//
//   1. duration probe:   ffmpeg -i <file>            (parses the stderr
//      "Duration: HH:MM:SS.mmm" line; real ffmpeg exits 1 here because no
//      output file is given — that exit code is *not* a failure)
//   2. frame grab:       ffmpeg -ss <10% duration> -i <file> -frames:v 1
//                        -vf scale=320:-2 -y <out.jpg>
//
// The frame is cached at AppData/thumbnails/<sha1(path+mtime)>.jpg so a file
// with unchanged mtime is only ever generated once, and an edited file gets
// a fresh key automatically (stale files are kept, v1 has no cache GC).
//
// Graceful degradation is central: with ffmpeg missing, probe() reports
// available=false, nothing is ever queued or generated, cachedThumbnailPath()
// stays empty and the UI keeps its type icons. Cached files are still
// served when ffmpeg is gone (only generation needs the binary).
//
// 1.x wrote the frame with -vf scale=320:-1 and documented the odd-height
// rejection of chroma-subsampled sources as a known limitation ("scale=320:-2
// would avoid it"). The 2.0 invariant (docs/SPEC.md §4.7) adopts -2, so the
// degradation no longer triggers on odd-height sources.
//
// Process handling stays event-driven (no synchronous waits) on the owner's
// event loop; a 30 s kill timer reaps hung children. requestThumbnail() does
// the cache-lookup bookkeeping, _pump() drives the serial queue
// (ThumbnailQueue holds the pure scheduling logic and is unit-tested
// directly).
class ThumbnailService extends ChangeNotifier {
  // |cacheDir| receives the generated JPEGs; |ffmpegBinary| is injectable
  // so tests can point at a stub script or a nonexistent path.
  ThumbnailService(this.cacheDir, {String? ffmpegBinary})
      : _ffmpegBinary = (ffmpegBinary == null || ffmpegBinary.isEmpty)
            ? 'ffmpeg'
            : ffmpegBinary {
    // Best effort: if this fails (read-only app data), generation will fail
    // per-file and degrade to the placeholder.
    try {
      Directory(cacheDir).createSync(recursive: true);
    } catch (_) {}
  }

  final String cacheDir;
  final String _ffmpegBinary;

  // True after the ffmpeg probe succeeded; drives graceful degradation.
  bool get isAvailable => _available;
  bool _available = false;

  // Pure cache-key function: |cacheDir|/<sha1(|path|+mtimeMs)>.jpg. The
  // mtime enters the hash so editing a file invalidates its thumbnail
  // (QByteArray::number(mtimeMs) is the decimal string form).
  static String cachePathFor(String cacheDir, String path, int mtimeMs) {
    final digest = sha1.convert(utf8.encode(path) + utf8.encode('$mtimeMs'));
    return '$cacheDir/$digest.jpg';
  }

  // Pure seek computation: 10% of |durationSeconds| formatted for ffmpeg
  // ("-ss" value), clamped at 0 (unknown/invalid durations seek to 0).
  static String seekPositionFor(double durationSeconds) {
    if (!(durationSeconds > 0.0)) {
      // also covers NaN
      return '0.000';
    }
    return (durationSeconds * 0.1).toStringAsFixed(3);
  }

  // Pure parser for ffmpeg's stderr "Duration: HH:MM:SS.mmm" line; returns
  // seconds, or -1 when the line is absent/unparseable (e.g. "Duration: N/A").
  static double durationFromFfmpegStderr(String stderrText) {
    final match = _durationRegex.firstMatch(stderrText);
    if (match == null) {
      return -1.0;
    }
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = double.parse(match.group(3)!);
    return hours * 3600.0 + minutes * 60.0 + seconds;
  }

  // Pure scheduling queue (FIFO + dedupe), unit-tested directly.
  final ThumbnailQueue _queue = ThumbnailQueue();

  final Set<String> _failed = <String>{}; // failed this session, no retries
  final Map<String, String> _ready = <String, String>{}; // path -> cache file

  bool _probing = false;
  bool _jobRunning = false;
  _JobStage _jobStage = _JobStage.durationProbe;
  String _jobPath = '';
  String _jobCacheFile = '';
  Process? _jobProcess; // current serial-chain child
  Timer? _jobTimeout;

  // Monotonic id of the active process; callbacks from a replaced/killed
  // child carry a stale generation and are dropped (1.x compared
  // sender() == m_jobProcess for the same guarantee).
  int _jobGeneration = 0;
  bool _disposed = false;

  /// Fired whenever a cache file becomes known-ready (generation finished or
  /// cache hit); |cacheFile| is the generated file. ChangeNotifier
  /// notifications cover availabilityChanged (probe settled) and the
  /// per-item readiness; the model rebuilds its thumbnail role from
  /// cachedThumbnailPath().
  final StreamController<ThumbnailReady> _readyController =
      StreamController<ThumbnailReady>.broadcast();

  Stream<ThumbnailReady> get onThumbnailReady => _readyController.stream;

  // Known cache file for |path| (empty when none was generated/registered
  // yet — the model exposes this as the "thumbnail" role).
  String cachedThumbnailPath(String path) => _ready[path] ?? '';

  // Start the async `ffmpeg -version` probe. ChangeNotifier fires once, when
  // the probe settles (success or failure). Re-invoking while a probe runs
  // is a no-op; a settled probe may be re-run.
  Future<void> probe() async {
    if (_probing || _disposed) {
      return;
    }
    _probing = true;
    try {
      // Real ffmpeg prints e.g. "ffmpeg version 6.1.1 Copyright ..." on
      // stdout; exit 0. Anything else counts as "no usable ffmpeg".
      final process = await Process.start(_ffmpegBinary, const ['-version']);
      final stdout = await _readAll(process.stdout);
      final exitCode = await process.exitCode;
      _available = exitCode == 0 && stdout.contains('ffmpeg version');
    } catch (_) {
      // Spawn failure (missing binary): the graceful-degradation path.
      _available = false;
    } finally {
      _probing = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  // On-demand request for |path| (an absolute media file path, as stored
  // in the library). Behavior:
  //  - already known ready: no-op (the model already reflects it);
  //  - cache file exists on disk for the current mtime: registered and
  //    thumbnailReady emitted immediately (works without ffmpeg);
  //  - otherwise queued for serial generation; dropped silently when
  //    ffmpeg is unavailable or the file is missing on disk.
  void requestThumbnail(String path) {
    if (path.isEmpty || _ready.containsKey(path) || _disposed) {
      return;
    }

    // Existing cache for the file's current mtime: register and report it
    // without any ffmpeg involvement (thumbnails survive ffmpeg going away).
    FileStat stat;
    try {
      stat = FileStat.statSync(path);
    } catch (_) {
      return; // nothing to thumbnail (stale library entry)
    }
    if (stat.type != FileSystemEntityType.file) {
      return; // nothing to thumbnail (stale library entry)
    }
    final cacheFile =
        cachePathFor(cacheDir, path, stat.modified.millisecondsSinceEpoch);
    final cached = File(cacheFile);
    if (cached.existsSync() && cached.lengthSync() > 0) {
      _ready[path] = cacheFile;
      _emitReady(path, cacheFile);
      return;
    }

    // Generation needs ffmpeg; without it the request is dropped and the UI
    // keeps its type icons (graceful degradation). The active job's path is
    // deduped too: it left the queue when its chain started, so a repeat
    // request (the model re-requests the visible list on every rebuild)
    // would otherwise requeue and re-run the whole two-process chain for
    // the same cache key — wasted subprocess work and duplicate
    // thumbnailReady notifications.
    if (!_available ||
        path == _jobPath ||
        _queue.contains(path) ||
        _failed.contains(path)) {
      return;
    }
    _queue.enqueue(path);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (!_available || _jobRunning || _disposed || _queue.isEmpty) {
      return;
    }
    final path = _queue.takeNext();
    if (path.isEmpty) {
      return;
    }
    // _startJobProcess marks the job running synchronously (before its first
    // await), so no reentrant _pump can take a second path in between.
    await _startDurationProbe(path);
  }

  Future<void> _startDurationProbe(String path) async {
    _jobPath = path;
    _jobStage = _JobStage.durationProbe;
    _jobCacheFile = '';
    // Duration probe with no output file: real ffmpeg prints the input's
    // "Duration:" line to stderr and exits 1 ("At least one output file must
    // be specified") — that exit code is expected and not an error here.
    await _startJobProcess(['-i', path]);
  }

  Future<void> _startGeneration(String seekPosition) async {
    _jobStage = _JobStage.generate;
    var mtimeMs = 0;
    try {
      mtimeMs =
          FileStat.statSync(_jobPath).modified.millisecondsSinceEpoch;
    } catch (_) {
      mtimeMs = 0; // vanished mid-chain: a fresh key is as good as any
    }
    _jobCacheFile = cachePathFor(cacheDir, _jobPath, mtimeMs);

    // -y: the cache path is fresh for the current mtime, but a previous
    // failed run may have left a partial/empty file; never prompt for it
    // (a prompt would hang the headless process).
    //
    // scale=320:-2 per the 2.0 invariant (thumbnail width 320, aspect
    // preserved, even heights only). 1.x kept -1 and documented that
    // chroma-subsampled sources with odd heights could be rejected; the
    // invariant adopts the fix (see class docs).
    await _startJobProcess([
      '-ss', seekPosition,
      '-i', _jobPath,
      '-frames:v', '1',
      '-vf', 'scale=320:-2',
      '-y', _jobCacheFile,
    ]);
  }

  // One fresh child per stage. A new generation id per stage (instead of
  // reusing one) keeps callback identity unambiguous: callbacks verify their
  // generation, so a straggler exit from an already-replaced child cannot be
  // applied to the next job (an OS kill delivers exit code and stream
  // closure back-to-back; whichever acts first finishes the job, the other
  // must be a no-op).
  Future<void> _startJobProcess(List<String> arguments) async {
    _jobTimeout?.cancel();
    _jobTimeout = null;
    _jobRunning = true;
    final generation = ++_jobGeneration;
    Process? process;
    try {
      process = await Process.start(_ffmpegBinary, arguments);
    } catch (_) {
      // FailedToStart and friends: both identity guards matter — whichever
      // of exit/error/timeout acts first finishes the job, the others are
      // no-ops.
      if (generation == _jobGeneration && !_disposed) {
        _finishJob(false);
      }
      return;
    }
    _jobProcess = process;

    final timeout = Timer(_kJobTimeout, () {
      if (generation == _jobGeneration) {
        process?.kill(); // exit path -> finishJob(false)
      }
    });
    _jobTimeout = timeout;

    final stderrText = await _readAll(process.stderr);
    final exitCode = await process.exitCode;
    if (generation != _jobGeneration || _disposed) {
      return; // stale callback from an already-replaced child
    }
    timeout.cancel();
    _jobTimeout = null;
    _jobProcess = null;

    if (_jobStage == _JobStage.durationProbe) {
      await _startGeneration(
          seekPositionFor(durationFromFfmpegStderr(stderrText)));
      return;
    }

    // Generate stage: success needs exit 0 and a non-empty output file.
    var generated = false;
    try {
      final stat = FileStat.statSync(_jobCacheFile);
      generated = stat.type == FileSystemEntityType.file && stat.size > 0;
    } catch (_) {
      generated = false;
    }
    _finishJob(exitCode == 0 && generated);
  }

  // Shared teardown for the active job (guarded: the first of
  // exit/error/timeout wins, later callbacks are no-ops).
  void _finishJob(bool success) {
    final path = _jobPath;
    final cacheFile = _jobCacheFile;
    _jobPath = '';
    _jobCacheFile = '';
    _jobRunning = false;
    _jobProcess = null;
    _jobTimeout?.cancel();
    _jobTimeout = null;

    if (success) {
      _ready[path] = cacheFile;
      _emitReady(path, cacheFile);
    } else {
      _failed.add(path); // session-level: no retry loops
    }
    unawaited(_pump());
  }

  void _emitReady(String path, String cacheFile) {
    notifyListeners();
    _readyController.add(ThumbnailReady(path, cacheFile));
  }

  static Future<String> _readAll(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks, allowMalformed: true);
  }

  // Destructor quiesce, mapped from 1.x teardownProcess(): stop the timer,
  // kill the in-flight child and invalidate all callbacks (generation +
  // _disposed). No straggler completion may reach _finishJob()/_pump()
  // afterwards — the disposed service must never hatch children for queued
  // work. 1.x did this in the destructor; Dart callers own the lifetime.
  @override
  void dispose() {
    _disposed = true;
    _jobTimeout?.cancel();
    _jobTimeout = null;
    try {
      _jobProcess?.kill();
    } catch (_) {}
    _jobProcess = null;
    _readyController.close();
    super.dispose();
  }
}
