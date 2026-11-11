import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:emoplay/media/library_store.dart' show LibraryStore;
import 'package:emoplay/media/nfo_parser.dart';
import 'package:emoplay/media/poster_finder.dart';

// NFO/poster metadata for the media library (user-added roadmap item M4-T6,
// 2026-11-12: "数据落盘：新缓存文件（如 media_nfo.json）…；三份 JSON schema
// 一个字段不改"). The companion of media_meta.json (M4-T4) for the facts
// neither the directory walk nor ffprobe can see: what the Kodi NFO files
// next to a video say, and which local poster artwork was found.
//
// Persistence: ONE new AppData file, `media_nfo.json` — the precedent the
// M4-T3 favorites and M4-T4 meta cache set (adding files ≠ modifying the
// three §7 schemas; history.json / library.json / settings.json stay
// byte-compatible, guarded by test/data_compat_spec7_test.dart). Document
// shape `{"version":1,"entries":{"<videoPath>":{…}}}`, keyed by the video's
// absolute path (favorites keys by path too; the entries are per-video
// facts, so the natural key is the video). House atomic write (sibling temp
// file + rename, the QSaveFile pattern); a missing or corrupt file degrades
// to an empty in-memory cache the next scan rebuilds.
//
// Invalidation: an entry is fresh while BOTH the video's mtime and its
// directory's mtime are unchanged. The directory is the trick — adding or
// editing poster.jpg / <video>.nfo / tvshow.nfo touches the DIRECTORY, not
// the video, so keying on the video alone would serve stale art forever.
// Both mtimes travel in the entry ([NfoInfo.videoMtimeMs]/[dirMtimeMs]).
//
// Scanning: one directory listing per video (listSync) — NFO presence, NFO
// parsing (lib/media/nfo_parser.dart, tolerant) and poster matching
// (lib/media/poster_finder.dart conventions) all derive from it. No child
// processes are ever spawned, and NFO <thumb> URLs are recorded verbatim
// without any fetch (local-first contract). Requests run through a serial
// chain (one scan at a time, event-driven, waiters join the in-flight path)
// so a library-wide request storm cannot interleave scans; a scan that
// fails (video or directory gone) is failed-guarded by its mtime pair — a
// later mtime change is a fresh state and may retry, same-state rebuilds
// never loop.
//
// Performance contract (test/nfo_meta_cache_test.dart): [infoFor] is a pure
// map read (NO stat, NO IO), and a fresh [requestInfo] hit does only the
// two mtime stats — no re-parse (the same record instance comes back).
class NfoMetaCache extends ChangeNotifier {
  /// |filePath| is the media_nfo.json location (AppData); injected so tests
  /// use a temporary directory.
  NfoMetaCache(this.filePath) {
    _load();
  }

  /// AppData/media_nfo.json path this cache persists to (the application
  /// support directory needs path_provider's platform channel, hence async).
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/media_nfo.json';
  }

  final String filePath;

  // Video path -> record. Key: absolute local path (normalized at request
  // time via LibraryStore.toLocalPath, the picker-URL convention).
  final Map<String, NfoInfo> _entries = <String, NfoInfo>{};

  // Paths whose scan failed for a given mtime state ("video:dir" suffix) —
  // dropped until that state changes, so per-rebuild re-requests never
  // become a scan loop.
  final Set<String> _failedStates = <String>{};

  bool _disposed = false;
  bool _scanning = false;
  final List<String> _queue = <String>[];
  final Map<String, List<Completer<NfoInfo?>>> _waiters =
      <String, List<Completer<NfoInfo?>>>{};

  /// Synchronous lookup: pure map read, never touches the filesystem. Works
  /// without any prior request (what the page's grouping/cells read on
  /// rebuild); missing/stale facts surface as the next [requestInfo] wave
  /// fills them.
  NfoInfo? infoFor(String path) => _entries[LibraryStore.toLocalPath(path)];

  /// Requests NFO/poster facts for |path| (a video's absolute path or a
  /// file:// URL — normalized like every store's path input).
  ///
  ///  - video or parent directory missing: completes null, no scan;
  ///  - fresh cached record (both mtimes unchanged): returned immediately —
  ///    the only IO is the two mtime stats (the hit-path guard);
  ///  - otherwise: queued into the serial chain; a request joining a path
  ///    already in flight shares its scan. The future settles with the
  ///    record, or null when the scan failed (including dispose — futures
  ///    never hang).
  Future<NfoInfo?> requestInfo(String pathOrUrl) {
    final path = LibraryStore.toLocalPath(pathOrUrl);
    if (path.isEmpty || _disposed) {
      return Future<NfoInfo?>.value(null);
    }
    final mtimes = _mtimesFor(path);
    if (mtimes == null) {
      return Future<NfoInfo?>.value(null);
    }
    final cached = _entries[path];
    if (cached != null &&
        cached.videoMtimeMs == mtimes.video &&
        cached.dirMtimeMs == mtimes.dir) {
      return Future<NfoInfo?>.value(cached);
    }
    if (_failedStates.contains(_stateKey(path, mtimes))) {
      return Future<NfoInfo?>.value(null);
    }
    final joined = _waiters[path];
    if (joined != null) {
      final completer = Completer<NfoInfo?>();
      joined.add(completer);
      return completer.future;
    }
    final completer = Completer<NfoInfo?>();
    _waiters[path] = <Completer<NfoInfo?>>[completer];
    _queue.add(path);
    unawaited(_pump());
    return completer.future;
  }

  // Video mtime + directory mtime; null when the video is not a readable
  // regular file or its directory is gone (a stale library entry).
  _Mtimes? _mtimesFor(String path) {
    final video = _mtimeMsOf(path, FileSystemEntityType.file);
    if (video == null) {
      return null;
    }
    final dir = _mtimeMsOf(p.dirname(path), FileSystemEntityType.directory);
    if (dir == null) {
      return null;
    }
    return _Mtimes(video: video, dir: dir);
  }

  int? _mtimeMsOf(String path, FileSystemEntityType expected) {
    try {
      final stat = FileStat.statSync(path);
      if (stat.type != expected) {
        return null;
      }
      return stat.modified.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  String _stateKey(String path, _Mtimes mtimes) =>
      '$path:${mtimes.video}:${mtimes.dir}';

  Future<void> _pump() async {
    if (_scanning || _disposed || _queue.isEmpty) {
      return;
    }
    final path = _queue.removeAt(0);
    _scanning = true;
    NfoInfo? info;
    try {
      info = await _scan(path);
    } catch (_) {
      info = null; // the scan is written to be total; the contract outranks it
    } finally {
      _scanning = false;
      if (!_disposed && info != null) {
        _entries[path] = info;
        _failedStates.remove(path);
        _saveIfDue();
        // Success notifies (the model refills its rows); failures stay
        // silent so a stateless rebuild-request cycle cannot spin.
        notifyListeners();
      }
      _settleWaiters(path, info);
    }
    if (!_disposed) {
      unawaited(_pump());
    }
  }

  // One video's facts from one directory listing. Never throws (callers'
  // catch is a belt-and-braces guard).
  Future<NfoInfo?> _scan(String path) async {
    final mtimes = _mtimesFor(path);
    if (mtimes == null) {
      return null;
    }
    final dir = p.dirname(path);

    // One listing is the scan's whole IO budget: every existence question
    // below is answered from these names.
    List<String> names;
    try {
      names = [
        for (final entity in Directory(dir).listSync(followLinks: false))
          p.basename(entity.path),
      ];
    } catch (_) {
      return null; // unreadable directory: nothing discoverable
    }
    final nameSet = Set<String>.of(names);
    bool isFile(String name) {
      try {
        return FileSystemEntity.typeSync('$dir/$name', followLinks: false) ==
            FileSystemEntityType.file;
      } catch (_) {
        return false;
      }
    }

    // The video's own NFO: first existing sidecar candidate
    // (<base>.nfo, then movie.nfo — Kodi precedence, nfo_parser.dart).
    var nfo = const NfoDocument();
    var hasNfo = false;
    for (final candidate in nfoCandidatesFor(path)) {
      final name = p.basename(candidate);
      if (!nameSet.contains(name) || !isFile(name)) {
        continue;
      }
      nfo = _parseNfoFile('$dir/$name');
      hasNfo = true;
      break;
    }

    // Show-level metadata: tvshow.nfo in the episode's directory (its
    // <title> names the show for the episode grouping view).
    var showTitle = '';
    if (nameSet.contains(tvshowNfoFileName) && isFile(tvshowNfoFileName)) {
      final showDoc = _parseNfoFile('$dir/$tvshowNfoFileName');
      showTitle = showDoc.title;
    }

    // Local poster: the fixed conventions, most specific first
    // (poster_finder.dart); <thumb> URLs stay recorded-only.
    final posterName = firstExistingPosterName(
      posterCandidateNamesFor(path),
      nameSet,
      isFile,
    );

    return NfoInfo(
      videoMtimeMs: mtimes.video,
      dirMtimeMs: mtimes.dir,
      hasNfo: hasNfo,
      nfo: nfo,
      poster: posterName.isEmpty ? '' : '$dir/$posterName',
      showTitle: showTitle,
    );
  }

  // Read + parse one NFO file. Unreadable files degrade to an empty
  // document (hasNfo stays true upstream — the file exists, its content
  // just says nothing usable), matching the skip-fields-not-crash contract.
  NfoDocument _parseNfoFile(String path) {
    String contents;
    try {
      contents = File(path).readAsStringSync();
    } catch (_) {
      return const NfoDocument();
    }
    return parseNfoContent(contents);
  }

  void _settleWaiters(String path, NfoInfo? info) {
    final waiters = _waiters.remove(path);
    if (waiters == null) {
      return;
    }
    for (final completer in waiters) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    }
  }

  // --------------------------------------------------------- persistence

  // QSaveFile semantics with the scanner's every-32-progress convention:
  // one atomic write per 32 completed scans and once when the queue drains,
  // so a 2000-file first pass costs ~63 writes, not 2000 growing rewrites.
  void _saveIfDue() {
    _sinceSave++;
    if (_sinceSave < 32 && _queue.isNotEmpty) {
      return;
    }
    _sinceSave = 0;
    _save();
  }

  int _sinceSave = 0;

  void _save() {
    final file = File(filePath);
    final dir = file.parent;
    try {
      dir.createSync(recursive: true);
      final temp = File('${dir.path}/${filePath.split('/').last}.tmp');
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

  // Flushes everything pending (test determinism / shutdown helpers).
  void flushForTest() => _save();

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
      return; // corrupt file: start empty, the next scan wave rebuilds it
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
        _entries[key] = NfoInfo.fromJson(value);
      }
    }
  }

  // Quiesce like the other media services: settle every waiter with null,
  // drop queued work — a disposed cache never notifies or persists.
  @override
  void dispose() {
    _disposed = true;
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

@immutable
class _Mtimes {
  const _Mtimes({required this.video, required this.dir});

  final int video;
  final int dir;
}

/// One video's NFO/poster facts. All facts are nullable/empty: a video
/// without any NFO or artwork still gets a record ([hasNfo] false, empty
/// poster) — the negative result is cached just as hard as the positive one
/// (it is what stops the scan queue from re-visiting the file).
@immutable
class NfoInfo {
  const NfoInfo({
    this.videoMtimeMs = 0,
    this.dirMtimeMs = 0,
    this.hasNfo = false,
    this.nfo = const NfoDocument(),
    this.poster = '',
    this.showTitle = '',
  });

  /// Video file mtime the scan ran against (invalidation half 1).
  final int videoMtimeMs;

  /// Directory mtime the scan ran against (invalidation half 2 — art and
  /// NFO edits touch the directory, not the video).
  final int dirMtimeMs;

  /// Whether a sidecar/movie NFO file existed for the video (its content
  /// may still be empty — a corrupt file parses to an empty document).
  final bool hasNfo;

  /// The parsed NFO ([NfoKind.unknown]/empty when none or unparseable).
  final NfoDocument nfo;

  /// Absolute path of the discovered local poster, '' when none of the
  /// conventions exists. Local file only — never a URL.
  final String poster;

  /// <title> of the directory's tvshow.nfo, '' when absent — the episode
  /// grouping view's show-name override.
  final String showTitle;

  factory NfoInfo.fromJson(Map<Object?, Object?> json) {
    return NfoInfo(
      videoMtimeMs: json['videoMtime'] is int
          ? json['videoMtime'] as int
          : (json['videoMtime'] is num
              ? (json['videoMtime'] as num).toInt()
              : 0),
      dirMtimeMs: json['dirMtime'] is int
          ? json['dirMtime'] as int
          : (json['dirMtime'] is num ? (json['dirMtime'] as num).toInt() : 0),
      hasNfo: json['hasNfo'] == true,
      nfo: json['nfo'] is Map
          ? NfoDocument.fromJson(json['nfo'] as Map<Object?, Object?>)
          : const NfoDocument(),
      poster: json['poster'] is String ? json['poster'] as String : '',
      showTitle:
          json['showTitle'] is String ? json['showTitle'] as String : '',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'videoMtime': videoMtimeMs,
        'dirMtime': dirMtimeMs,
        'hasNfo': hasNfo,
        'nfo': nfo.toJson(),
        'poster': poster,
        'showTitle': showTitle,
      };

  @override
  bool operator ==(Object other) =>
      other is NfoInfo &&
      other.videoMtimeMs == videoMtimeMs &&
      other.dirMtimeMs == dirMtimeMs &&
      other.hasNfo == hasNfo &&
      other.nfo == nfo &&
      other.poster == poster &&
      other.showTitle == showTitle;

  @override
  int get hashCode =>
      Object.hash(videoMtimeMs, dirMtimeMs, hasNfo, nfo, poster, showTitle);

  @override
  String toString() =>
      'NfoInfo($hasNfo, ${nfo.kind}, title=${nfo.title}, poster=$poster, '
      'showTitle=$showTitle)';
}
