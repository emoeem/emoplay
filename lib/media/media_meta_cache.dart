import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

// Kill hung ffprobe children after this long — the same budget the
// thumbnail chain uses (lib/media/thumbnail_service.dart _kJobTimeout; the
// SPEC §4.7 "30s 超时强杀" contract applied to both probe families alike).
const Duration kMediaMetaJobTimeout = Duration(seconds: 30);

/// One metadata record: what ffprobe can tell about a file beyond the
/// directory walk (roadmap §四 M4-T4: container/codecs/width/height).
///
/// All fields are nullable: an audio file has no video stream (width and
/// height stay null), and a streams-stage failure leaves a container-only
/// entry (graceful degradation — partial information is still cached).
@immutable
class MediaMeta {
  const MediaMeta({
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
  });

  /// Container format — ffprobe's format_name ("matroska,webm", "mov,mp4,
  /// m4a,3gp,3g2,mj2"…). Absent when the format stage failed or the
  /// document carried no usable format block.
  final String? container;

  /// Primary video stream codec_name ("h264", "hevc"…); null for audio
  /// files. Cover-art streams (disposition.attached_pic) never satisfy
  /// this — see [streamsMetaFromFfprobeJson].
  final String? videoCodec;

  /// Primary audio stream codec_name ("aac", "flac"…).
  final String? audioCodec;

  /// Primary video stream dimensions in pixels.
  final int? width;
  final int? height;

  factory MediaMeta.fromJson(Map<Object?, Object?> json) => MediaMeta(
        container:
            json['container'] is String ? json['container'] as String : null,
        videoCodec:
            json['videoCodec'] is String ? json['videoCodec'] as String : null,
        audioCodec:
            json['audioCodec'] is String ? json['audioCodec'] as String : null,
        width: json['width'] is int ? json['width'] as int : null,
        height: json['height'] is int ? json['height'] as int : null,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'container': container,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'width': width,
        'height': height,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaMeta &&
      other.container == container &&
      other.videoCodec == videoCodec &&
      other.audioCodec == audioCodec &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode =>
      Object.hash(container, videoCodec, audioCodec, width, height);

  @override
  String toString() =>
      'MediaMeta($container, $videoCodec/$audioCodec, ${width}x$height)';
}

/// Pure parser for the `-show_format` stage stdout: the container name out
/// of ffprobe's JSON, or null when the document has no usable format block
/// (real ffprobe emits `{"format": {"format_name": "…", …}}`; verified
/// against ffprobe 8.0 on 2026-11-12).
String? containerFromFfprobeJson(String stdoutText) {
  Object? document;
  try {
    document = jsonDecode(stdoutText);
  } on FormatException {
    return null;
  }
  if (document is! Map) {
    return null;
  }
  final format = document['format'];
  if (format is! Map) {
    return null;
  }
  final name = format['format_name'];
  return name is String && name.isNotEmpty ? name : null;
}

/// Pure parser for the `-show_streams` stage stdout: the primary video
/// stream (first non-cover-art one — mp3/m4a embed their cover as an
/// attached-pic video stream, which must not report width/height) and the
/// first audio stream. Returns a possibly all-null [MediaMeta]; never
/// throws on malformed input (degradation, not a crash).
MediaMeta streamsMetaFromFfprobeJson(String stdoutText) {
  Object? document;
  try {
    document = jsonDecode(stdoutText);
  } on FormatException {
    return const MediaMeta();
  }
  if (document is! Map) {
    return const MediaMeta();
  }
  final streams = document['streams'];
  if (streams is! List) {
    return const MediaMeta();
  }

  String? videoCodec;
  int? width;
  int? height;
  String? audioCodec;
  for (final stream in streams) {
    if (stream is! Map) {
      continue;
    }
    final type = stream['codec_type'];
    if (type == 'video' && videoCodec == null && !_isAttachedPic(stream)) {
      videoCodec = stream['codec_name'] is String
          ? stream['codec_name'] as String
          : null;
      width = stream['width'] is int ? stream['width'] as int : null;
      height = stream['height'] is int ? stream['height'] as int : null;
    } else if (type == 'audio' && audioCodec == null) {
      audioCodec = stream['codec_name'] is String
          ? stream['codec_name'] as String
          : null;
    }
  }
  return MediaMeta(
    videoCodec: videoCodec,
    audioCodec: audioCodec,
    width: width,
    height: height,
  );
}

bool _isAttachedPic(Map<Object?, Object?> stream) {
  final disposition = stream['disposition'];
  return disposition is Map && disposition['attached_pic'] == 1;
}

// One serial-chain job: the file to probe and the cache key its current
// mtime hashes to (the queue holds both so a mid-probe mtime bump cannot
// mix keys — the entry is written under the key computed at request time).
class _PendingJob {
  const _PendingJob({required this.path, required this.key});

  final String path;
  final String key;
}

/// On-disk metadata cache for the media library (EmoPlay 3.0 roadmap
/// docs/EMOPLAY-3.0-ROADMAP.md §四 step 3 / M4-T4), the companion of the
/// thumbnail cache (lib/media/thumbnail_service.dart) for the facts a
/// directory walk cannot see.
///
/// Same shape as the thumbnail service, per the roadmap ("ffprobe 两段式同
/// thumbnail 模式"):
///
///  - Cache key: `sha1(path + mtimeMs)` — byte-for-byte the same input
///    ThumbnailService.cachePathFor hashes ([cacheKeyFor]), so one edit of
///    a file invalidates both caches with the same mtime bump. Keys live
///    as entries of ONE JSON file, `media_meta.json` (a new AppData file —
///    adding files is not modifying the three §7 schemas), written with
///    the house atomic write (temp file + rename).
///  - Two-stage process chain per file, serial (one child at a time,
///    event-driven, no synchronous waits): stage 1 `-show_format`
///    (container), stage 2 `-show_streams` (codecs + dimensions). Each
///    stage gets a fresh child and the shared kill timer; a stage that
///    fails (nonzero exit, spawn failure, timeout kill) degrades to null
///    and whatever the other stage produced is still cached — a fully
///    failed chain marks the cache key failed for the session (no retry
///    loops, the thumbnail contract).
///  - Graceful degradation when ffprobe is missing: [probe] reports
///    available=false, requests are dropped without spawning anything, and
///    cached entries keep being served ([metaFor] / the [requestMeta] hit
///    path never need the binary — only generation does).
///
/// Process-list discipline mirrors thumbnail_service.dart: arguments travel
/// as a `List<String>` (never a shell string), a generation counter drops
/// straggler callbacks from replaced/killed children, and dispose() kills
/// the in-flight child and settles every waiter with null.
///
/// Performance contract (test/media_meta_cache_test.dart): a cache hit
/// spawns NO process — [metaFor] is a stat + map lookup, and a hit in
/// [requestMeta] returns before any queue work.
class MediaMetaCache extends ChangeNotifier {
  /// |filePath| is the media_meta.json location (AppData);
  /// |ffprobeBinary| is injectable so tests can point at a stub script or
  /// a nonexistent path; |jobTimeout| is the per-stage kill budget.
  MediaMetaCache({
    required this.filePath,
    String? ffprobeBinary,
    this.jobTimeout = kMediaMetaJobTimeout,
  }) : _ffprobeBinary = (ffprobeBinary == null || ffprobeBinary.isEmpty)
            ? 'ffprobe'
            : ffprobeBinary {
    // Best effort: a corrupt or missing file degrades to an empty in-memory
    // cache (rebuilt by probing); writes start over the old content.
    _load();
  }

  /// AppData/media_meta.json path this cache persists to.
  final String filePath;

  /// Per-stage kill budget (real ffprobe on a network source can hang).
  final Duration jobTimeout;

  final String _ffprobeBinary;

  // True after the `ffprobe -version` probe succeeded; drives the graceful
  // degradation. Callers probe() once on startup, like ThumbnailService.
  bool get isAvailable => _available;
  bool _available = false;
  bool _probing = false;
  bool _disposed = false;

  // sha1 hex key -> record.
  final Map<String, MediaMeta> _entries = <String, MediaMeta>{};

  // Keys whose chain failed this session: dropped instead of re-queued (no
  // retry loops). Keyed by cache key (not path, unlike the thumbnail
  // service's path-keyed set) so an edited file — a fresh key — may retry
  // immediately; the no-retry-loops goal only needs one key to fail once.
  final Set<String> _failedKeys = <String>{};

  // Serial chain state. One child at a time; waiters hang off the key so a
  // second request for an in-flight file joins the running chain instead of
  // re-spawning it.
  final List<_PendingJob> _queue = <_PendingJob>[];
  final Map<String, List<Completer<MediaMeta?>>> _waiters =
      <String, List<Completer<MediaMeta?>>>{};
  bool _jobRunning = false;
  int _jobGeneration = 0;
  Process? _jobProcess;
  Timer? _jobTimeout;

  /// Pure cache-key function: sha1(path + mtimeMs) — the exact byte input
  /// ThumbnailService.cachePathFor hashes (lib/media/thumbnail_service.dart,
  /// "键沿用 thumbnail_service 的 sha1(path+mtimeMs)"). Decimal mtime string,
  /// matching QByteArray::number(mtimeMs) from 1.x.
  static String cacheKeyFor(String path, int mtimeMs) {
    final digest = sha1.convert(utf8.encode(path) + utf8.encode('$mtimeMs'));
    return digest.toString();
  }

  /// Start the async `ffprobe -version` probe. ChangeNotifier fires once,
  /// when the probe settles. Re-invoking while a probe runs is a no-op.
  Future<void> probe() async {
    if (_probing || _disposed) {
      return;
    }
    _probing = true;
    try {
      // Real ffprobe prints "ffprobe version 8.0.1 …" on stdout, exit 0.
      final process = await Process.start(_ffprobeBinary, const ['-version']);
      final stdout = await _readAll(process.stdout);
      final exitCode = await process.exitCode;
      _available = exitCode == 0 && stdout.contains('ffprobe version');
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

  /// Synchronous lookup: stat + map read. NEVER spawns a process, works
  /// without ffprobe, and returns null for missing/changed files (their
  /// key moved). The M4 UI reads this on rebuild; [requestMeta] fills the
  /// gaps in the background.
  MediaMeta? metaFor(String path) {
    final key = _keyFor(path);
    return key == null ? null : _entries[key];
  }

  /// Requests metadata for |path| (an absolute media file path). Behavior:
  ///
  ///  - cache hit for the file's current mtime: returned immediately, no
  ///    process (the performance guard);
  ///  - failed this session, unavailable ffprobe, or a path that does not
  ///    stat to a readable file: completes null without spawning anything;
  ///  - otherwise: queued into the serial two-stage chain; a repeated
  ///    request while in flight joins the running chain (one chain per
  ///    key). The returned future settles with the record, or null when
  ///    the chain failed (including a dispose mid-chain — futures never
  ///    hang).
  Future<MediaMeta?> requestMeta(String path) {
    final key = _keyFor(path);
    if (key == null) {
      return Future<MediaMeta?>.value(null);
    }
    final hit = _entries[key];
    if (hit != null) {
      return Future<MediaMeta?>.value(hit);
    }
    if (_failedKeys.contains(key) || !_available || _disposed) {
      return Future<MediaMeta?>.value(null);
    }
    final joined = _waiters[key];
    if (joined != null) {
      final completer = Completer<MediaMeta?>();
      joined.add(completer);
      return completer.future;
    }
    final completer = Completer<MediaMeta?>();
    _waiters[key] = <Completer<MediaMeta?>>[completer];
    _queue.add(_PendingJob(path: path, key: key));
    unawaited(_pump());
    return completer.future;
  }

  // Cache key for the file's CURRENT mtime; null when there is nothing to
  // key (missing file, directory, stat failure — a stale library entry).
  String? _keyFor(String path) {
    if (path.isEmpty) {
      return null;
    }
    try {
      final stat = FileStat.statSync(path);
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      return cacheKeyFor(path, stat.modified.millisecondsSinceEpoch);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pump() async {
    if (_jobRunning || _disposed || _queue.isEmpty) {
      return;
    }
    final job = _queue.removeAt(0);
    _jobRunning = true;
    // One generation per job: every child of this chain (both stages)
    // verifies against it, so a straggler exit from an already-replaced
    // child can never be applied to a later job (the thumbnail service's
    // guard, one level up since the chain owns two stages).
    final generation = ++_jobGeneration;
    MediaMeta? meta;
    try {
      meta = await _runChain(job.path, generation);
    } finally {
      _jobRunning = false;
      _jobProcess = null;
      _jobTimeout?.cancel();
      _jobTimeout = null;
      if (!_disposed) {
        if (meta != null) {
          _entries[job.key] = meta;
          _save();
          notifyListeners();
        } else {
          _failedKeys.add(job.key);
        }
      }
      _settleWaiters(job.key, meta);
    }
    if (!_disposed) {
      unawaited(_pump());
    }
  }

  // The two-stage chain: -show_format (container) then -show_streams
  // (codecs + dimensions). Each stage failure degrades to null; the entry
  // keeps whatever stages produced (container-only on a streams failure),
  // and a fully failed chain returns null (job marked failed upstream).
  Future<MediaMeta?> _runChain(String path, int generation) async {
    final formatOutput = await _runStage(
        <String>['-v', 'error', '-print_format', 'json', '-show_format', path],
        generation);
    if (generation != _jobGeneration || _disposed) {
      return null;
    }
    final container =
        formatOutput == null ? null : containerFromFfprobeJson(formatOutput);

    final streamsOutput = await _runStage(
        <String>['-v', 'error', '-print_format', 'json', '-show_streams', path],
        generation);
    if (generation != _jobGeneration || _disposed) {
      return null;
    }
    final streams = streamsOutput == null
        ? const MediaMeta()
        : streamsMetaFromFfprobeJson(streamsOutput);

    final hasContainer = container != null;
    final hasStreams =
        streams.videoCodec != null || streams.audioCodec != null;
    if (!hasContainer && !hasStreams) {
      return null; // both stages failed: nothing worth caching
    }
    return MediaMeta(
      container: container,
      videoCodec: streams.videoCodec,
      audioCodec: streams.audioCodec,
      width: streams.width,
      height: streams.height,
    );
  }

  // One fresh child per stage. Returns stdout when the child exited 0,
  // null on spawn failure / nonzero exit / stale generation (killed by a
  // later job or dispose). The timeout kill mirrors thumbnail_service:
  // the timer kills the child, the exit path reports the failure.
  Future<String?> _runStage(List<String> arguments, int generation) async {
    _jobTimeout?.cancel();
    _jobTimeout = null;
    Process? process;
    try {
      process = await Process.start(_ffprobeBinary, arguments);
    } catch (_) {
      // FailedToStart and friends: degrade this stage to null.
      return null;
    }
    _jobProcess = process;

    final timeout = Timer(jobTimeout, () {
      if (generation == _jobGeneration) {
        process?.kill(); // hung child: force kill, exit reports failure
      }
    });
    _jobTimeout = timeout;

    final stdoutText = await _readAll(process.stdout);
    // Drain stderr as well: -v error keeps it small, but an undrained pipe
    // can still block the child once the OS pipe buffer fills.
    await _readAll(process.stderr);
    final exitCode = await process.exitCode;
    if (generation != _jobGeneration || _disposed) {
      return null; // stale callback from an already-replaced child
    }
    timeout.cancel();
    if (identical(_jobTimeout, timeout)) {
      _jobTimeout = null;
    }
    return exitCode == 0 ? stdoutText : null;
  }

  void _settleWaiters(String key, MediaMeta? meta) {
    final waiters = _waiters.remove(key);
    if (waiters == null) {
      return;
    }
    for (final completer in waiters) {
      if (!completer.isCompleted) {
        completer.complete(meta);
      }
    }
  }

  static Future<String> _readAll(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks, allowMalformed: true);
  }

  // --------------------------------------------------------- persistence

  // Document shape: `{"version":1,"entries":{"<sha1hex>":{…}}}` — a NEW file
  // (adding files ≠ modifying the three §7 schemas), versioned and
  // atomically written like the other stores (QSaveFile pattern).
  void _load() {
    _entries.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return; // no cache yet
    }

    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return; // corrupt file: start empty, probing rebuilds it
    }

    if (document is! Map) {
      return;
    }
    final entries = document['entries'];
    if (entries is! Map) {
      return;
    }
    for (final entry in entries.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && key.isNotEmpty && value is Map) {
        _entries[key] = MediaMeta.fromJson(value);
      }
    }
  }

  void _save() {
    final dir = File(filePath).parent;
    try {
      dir.createSync(recursive: true);
      final name = filePath.split('/').last;
      final temp = File('${dir.path}/$name.tmp');
      temp.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': <String, Object?>{
              for (final entry in _entries.entries)
                entry.key: entry.value.toJson(),
            },
          }),
          flush: true);
      temp.renameSync(filePath);
    } catch (_) {
      // Same contract as QSaveFile::commit(): silent failure, the in-memory
      // state stays authoritative.
    }
  }

  // Destructor quiesce, mapped from thumbnail_service.dispose(): stop the
  // timer, kill the in-flight child, drop queued work and settle every
  // waiter with null — the disposed cache must never hatch children and no
  // caller may hang on a future.
  @override
  void dispose() {
    _disposed = true;
    _jobTimeout?.cancel();
    _jobTimeout = null;
    try {
      _jobProcess?.kill();
    } catch (_) {}
    _jobProcess = null;
    for (final waiters in _waiters.values) {
      for (final completer in waiters) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }
    _waiters.clear();
    _queue.clear();
    super.dispose();
  }
}
