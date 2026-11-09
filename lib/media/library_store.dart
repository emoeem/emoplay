import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// One discovered media file in the library. This is the P6 v1 "entry model":
// no metadata lookup, no thumbnails — just what a directory walk can tell us
// (plus an optional last-played timestamp kept across re-scans).
//
// JSON contract (docs/SPEC.md §7, identical field-for-field with 1.x
// library.json): {"version":1,"directories":[],"entries":[{path,title,type,
// "video"|"audio",size,lastPlayed}]}. `lastPlayed` is written as "" when the
// entry was never played inside the library (1.x behaviour); a JSON null from
// foreign writers loads back as "".
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.path,
    this.title = '',
    this.type = '',
    this.size = 0,
    this.lastPlayed = '',
  });

  factory LibraryEntry.fromJson(Map<Object?, Object?> json) => LibraryEntry(
        path: json['path'] is String ? json['path'] as String : '',
        title: json['title'] is String ? json['title'] as String : '',
        type: json['type'] is String ? json['type'] as String : '',
        size: json['size'] is int ? json['size'] as int : 0,
        lastPlayed:
            json['lastPlayed'] is String ? json['lastPlayed'] as String : '',
      );

  // Absolute local path.
  final String path;

  // Display name (file name without extensions).
  final String title;

  // "video" or "audio".
  final String type;

  // Bytes.
  final int size;

  // ISO 8601, empty when never played in the library.
  final String lastPlayed;

  bool get hasLastPlayed => lastPlayed.isNotEmpty;

  LibraryEntry copyWith({
    String? path,
    String? title,
    String? type,
    int? size,
    String? lastPlayed,
  }) =>
      LibraryEntry(
        path: path ?? this.path,
        title: title ?? this.title,
        type: type ?? this.type,
        size: size ?? this.size,
        lastPlayed: lastPlayed ?? this.lastPlayed,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'title': title,
        'type': type,
        'size': size,
        'lastPlayed': lastPlayed,
      };

  @override
  bool operator ==(Object other) =>
      other is LibraryEntry &&
      other.path == path &&
      other.title == title &&
      other.type == type &&
      other.size == size &&
      other.lastPlayed == lastPlayed;

  @override
  int get hashCode => Object.hash(path, title, type, size, lastPlayed);

  @override
  String toString() =>
      'LibraryEntry($path, $title, $type, $size, $lastPlayed)';
}

// Scan tuning (1.x LibraryStore::ScanOptions): [maxDepth] counts the
// subdirectory levels below a root folder; <= 0 = unlimited. [skipHidden]
// hides dot entries (and keeps the walk out of hidden directories).
@immutable
class ScanOptions {
  const ScanOptions({this.maxDepth = 2, this.skipHidden = true});

  final int maxDepth;
  final bool skipHidden;
}

// Messages exchanged with the scan worker isolate. Plain data classes only:
// everything crossing the port must be sendable.
class _ScanCommand {
  const _ScanCommand({
    required this.dirs,
    required this.maxDepth,
    required this.skipHidden,
    required this.cancelledAtStart,
  });

  final List<String> dirs;
  final int maxDepth;
  final bool skipHidden;

  // A cancel that arrived on the store side before the command was posted
  // (the isolate handshake is asynchronous); 1.x covered this with a shared
  // atomic, here the flag travels with the command instead.
  final bool cancelledAtStart;
}

class _CancelCommand {
  const _CancelCommand();
}

class _ProgressReply {
  const _ProgressReply(this.fileCount);

  final int fileCount;
}

class _FinishedReply {
  const _FinishedReply(this.entries);

  final List<LibraryEntry> entries;
}

// Media library state: the user's media folders and the media files found in
// them, persisted to a JSON file (application support directory/library.json
// by default, atomic write = temp file + rename — same pattern as
// HistoryStore / EmoPlaySettings).
//
// Semantics (P6 v1, native simplification of the file-browser script family,
// see docs/nativeization-plan.md §2.2):
//  - Directory list: addDirectory() / removeDirectory(), deduped by
//    normalized absolute path, persisted.
//  - Scanning: QDirIterator walk per directory; files classified video/audio
//    by (lower-cased) extension; unknown extensions, hidden entries and
//    directories deeper than ScanOptions::maxDepth are skipped. QDirIterator
//    (Qt 6.4) already skips hidden files during filtering and does not even
//    descend into hidden directories unless QDir::Hidden/AllDirs is set
//    (qtbase src/corelib/io/qdiriterator.cpp matchesFilters /
//    checkAndPushDirectory), and symlinked directories are not followed
//    unless FollowSymlinks is set — so plain QDir::Files + Subdirectories
//    gives the wanted behavior for free. The Dart walk reproduces this
//    exactly: hidden entries skipped, directory symlinks never descended
//    (Link entities are ignored for recursion), files reached through a
//    symlink still count (QFileInfo resolves symlinks).
//  - Entries are deduped by absolute path (nested folders would otherwise
//    report the same file once per covering directory) and sorted by title.
//  - Re-scans replace the entry list but preserve the lastPlayed timestamp of
//    files that are still present.
//
// The scan itself is pure logic and re-entrant (scanDirectories is static).
// requestScan() moves it to a worker isolate so the UI never blocks, with
// periodic progress and a cancellation flag checked per file. The store only
// applies worker results on its own event loop.
//
// 1.x note: the worker QThread was created in the constructor. Dart
// constructors cannot await, so the isolate is spawned lazily on the first
// scan — observationally equivalent (a scan cannot start before
// requestScan() anyway).
//
// The store never touches mpv; callers may notePlayed() when a file starts
// playing. Tests inject a storage path and drive the synchronous scan
// directly or the async requestScan() through a polling helper.
class LibraryStore extends ChangeNotifier {
  // |filePath| is the storage JSON; injected so tests can use a temporary
  // location.
  LibraryStore(this.filePath) {
    _load();
  }

  // Default storage location; the application support directory needs
  // path_provider's platform channel, so this is async (1.x
  // QStandardPaths::AppDataLocation, application name set in main()).
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/library.json';
  }

  final String filePath;

  // Normalized absolute paths of the user's media folders.
  List<String> get directories => List.unmodifiable(_directories);
  final List<String> _directories = <String>[];

  // Full entry list (the LibraryModel wraps this for the pages).
  List<LibraryEntry> get entryList => List.unmodifiable(_entries);
  final List<LibraryEntry> _entries = <LibraryEntry>[];

  ScanOptions _scanOptions = const ScanOptions();
  void setScanOptions(ScanOptions options) => _scanOptions = options;

  // True while a scan runs in the worker isolate.
  bool get isScanning => _scanning;
  bool _scanning = false;
  bool _scanPending = false;
  bool _cancelRequested = false;

  // Media files found so far by the running scan (progress hint).
  int get scanFileCount => _scanFileCount;
  int _scanFileCount = 0;

  // 1.x emitted scanCancelled() after the partial result landed and the page
  // kept its own lastScanCancelled from the signals. A ChangeNotifier
  // carries no event identity, so the flag lives here and pages read it on
  // notification (cleared when the next scan starts).
  bool get lastScanCancelled => _lastScanCancelled;
  bool _lastScanCancelled = false;

  // Worker plumbing: one persistent worker isolate for the store's lifetime
  // (spawned lazily on the first scan, killed in dispose()). All contact is
  // via SendPorts, so no locking is needed.
  Isolate? _workerIsolate;
  ReceivePort? _workerReplies;
  SendPort? _workerCommands;
  Future<void> _workerReady = Future<void>.value();
  bool _disposed = false;

  // Add |pathOrUrl| (local path or file:// URL, matching the picker dialog
  // convention used by the player) to the folder list. Returns false when
  // the path is not an existing directory or is already in the list.
  // Persisting aside, this kicks off a scan so the UI reflects the new
  // folder without a second click (requests arriving mid-scan are chained,
  // see requestScan).
  bool addDirectory(String pathOrUrl) {
    final path = toLocalPath(pathOrUrl);
    if (path.isEmpty ||
        FileSystemEntity.typeSync(path) != FileSystemEntityType.directory) {
      return false;
    }
    if (_directories.contains(path)) {
      return false;
    }

    _directories.add(path);
    notifyListeners();
    _save();

    // Reflect the new folder immediately; mid-scan requests are chained.
    requestScan();
    return true;
  }

  // Remove the folder and every entry under it. Unknown folders are a no-op.
  void removeDirectory(String pathOrUrl) {
    final path = toLocalPath(pathOrUrl);
    if (!_directories.remove(path)) {
      return;
    }

    // Drop the entries that lived under the removed folder (prefix match on
    // the normalized paths; adding '/' keeps "/a/b" from matching "/a/bc").
    final prefix = '$path/';
    _entries.removeWhere(
        (entry) => entry.path == path || entry.path.startsWith(prefix));

    notifyListeners();
    _save();
  }

  // Scan the folder list in the worker isolate. While a scan runs the
  // request is remembered and chained after it (adding several folders in a
  // row must not lose scans). Results arrive through notifyListeners().
  void requestScan() {
    if (_scanning) {
      // A scan is in flight; chain this request instead of dropping it, so
      // adding several folders in a row scans them all.
      _scanPending = true;
      return;
    }
    unawaited(_startScan());
  }

  // Ask the running scan to stop. The worker polls the cancel flag per
  // file, so this returns immediately; the files found so far are still
  // applied (cancelling must not throw away progress) and lastScanCancelled
  // flips true once the partial result has landed.
  void cancelScan() {
    if (!_scanning) {
      _scanPending = false;
      return;
    }
    // Chained requests are dropped: the user asked to stop, not to start the
    // next folder right away.
    _scanPending = false;
    _cancelRequested = true;
    _workerCommands?.send(const _CancelCommand());
  }

  // Stamp the entry for |path| as played now and persist. Unknown paths are
  // ignored (v1 does not add arbitrary files to the library).
  void notePlayed(String path) {
    if (path.isEmpty) {
      return;
    }

    final index = _entries.indexWhere((entry) => entry.path == path);
    if (index < 0) {
      return;
    }
    _entries[index] =
        _entries[index].copyWith(lastPlayed: DateTime.now().toIso8601String());
    notifyListeners();
    _save();
  }

  // "video" / "audio" / empty (not media) for a lower-cased extension.
  static String mediaTypeForSuffix(String suffix) {
    if (videoSuffixes.contains(suffix)) {
      return 'video';
    }
    if (audioSuffixes.contains(suffix)) {
      return 'audio';
    }
    return '';
  }

  // Pure scan logic: walk every directory in |dirs|, classify media files
  // by extension, dedupe by absolute path, sort by (case-insensitive)
  // title. |progress| receives the number of files found so far (called
  // every few dozen files and once at the end); |cancelled| is polled per
  // file and stops the walk when it returns true. Both may be null.
  //
  // A cancel in the middle of a directory returns the walk's partial result
  // immediately, in walk order and without the final progress call — 1.x
  // returned from inside the per-file loop the same way (the store applies
  // whatever was collected). A cancel between directories falls through to
  // the normal sort + final progress, matching the 1.x `break`.
  //
  // The walk yields to the event loop between files so a cancel command can
  // land while the scan is inside the worker isolate (1.x polled a shared
  // atomic per file; the yield is the cooperative equivalent).
  static Future<List<LibraryEntry>> scanDirectories(
    List<String> dirs,
    ScanOptions options, {
    void Function(int found)? progress,
    bool Function()? cancelled,
  }) async {
    final entries = <LibraryEntry>[];
    final seen = <String>{};
    var found = 0;

    bool stop() => cancelled != null && cancelled();

    // QDir::Files semantics resolved per entry: directories are never
    // reported but still traversed (checkAndPushDirectory runs before
    // matchesFilters in qdiriterator.cpp); a symlink pointing at a regular
    // file is reported (QFileInfo resolves links), a symlink pointing at a
    // directory is never descended into (FollowSymlinks unset — no cycles).
    Future<bool> walk(String current, int level) async {
      List<FileSystemEntity> children;
      try {
        // followLinks: false mirrors the raw iterator listing; resolution
        // happens per entry below.
        children = Directory(current).listSync(followLinks: false);
      } catch (_) {
        // Unreadable directory: nothing collectable at this level.
        return false;
      }
      for (final entity in children) {
        if (stop()) {
          return true;
        }
        // One turn per file keeps cancel latency at file granularity.
        await Future<void>.delayed(Duration.zero);

        final name = _fileNameOf(entity.path);
        if (options.skipHidden && name.startsWith('.')) {
          continue;
        }

        final raw = FileSystemEntity.typeSync(entity.path,
            followLinks: false);
        var isFile = raw == FileSystemEntityType.file;
        var isDirectory = raw == FileSystemEntityType.directory;
        if (raw == FileSystemEntityType.link) {
          // Resolve the link the way QFileInfo does; a dangling link
          // matches neither Files nor Dirs.
          FileSystemEntityType resolved;
          try {
            resolved = FileSystemEntity.typeSync(entity.path);
          } catch (_) {
            continue;
          }
          isFile = resolved == FileSystemEntityType.file;
          isDirectory = false; // directory links are not followed
        }

        if (isFile) {
          // Depth of the file relative to this root: number of directories
          // between the root and the file ("file.mkv" = 0, "a/b.mkv" = 1).
          if (options.maxDepth > 0 && level > options.maxDepth) {
            continue;
          }
          final type = mediaTypeForSuffix(_suffixOf(name));
          if (type.isEmpty) {
            continue;
          }
          final path = entity.path;
          if (seen.contains(path)) {
            continue; // nested folders can cover the same file twice
          }
          seen.add(path);

          var size = 0;
          try {
            size = File(path).lengthSync();
          } catch (_) {
            size = 0;
          }
          entries.add(LibraryEntry(
            path: path,
            title: _completeBaseName(name),
            type: type,
            size: size,
          ));
          found++;

          // Throttled progress: per-file signals would flood the GUI for
          // big libraries.
          if (progress != null && (found % 32) == 0) {
            progress(found);
          }
          continue;
        }
        if (isDirectory && await walk(entity.path, level + 1)) {
          return true;
        }
      }
      return false;
    }

    for (final dirPath in dirs) {
      if (stop()) {
        break;
      }

      final root = Directory(dirPath);
      if (!root.existsSync()) {
        continue;
      }

      if (await walk(root.path, 0)) {
        return entries;
      }
    }

    if (progress != null && found > 0) {
      progress(found);
    }

    entries.sort((a, b) {
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (byTitle != 0) {
        return byTitle;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return entries;
  }

  // QDir::cleanPath(QFileInfo(local).absoluteFilePath()) semantics: resolve a
  // path or file:// URL (what the picker dialogs hand over) to a cleaned
  // absolute local path.
  static String toLocalPath(String pathOrUrl) {
    if (pathOrUrl.isEmpty) {
      return '';
    }
    var local = pathOrUrl;
    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null && uri.isScheme('file')) {
      try {
        local = uri.toFilePath();
      } on FormatException {
        local = pathOrUrl;
      }
    }
    if (local.isEmpty) {
      return '';
    }
    return p.normalize(p.absolute(local));
  }

  // Fixed classification table for P6 v1 (no content sniffing, no MIME
  // lookup): a file is media when its lower-cased extension is listed here.
  // The list is the 1.x FileDialog filter set plus a few common extras.
  // (Deliberately NOT MediaClassifier's tables — 1.x kept the two lists
  // separate and each is pinned by its own tests.)
  static const List<String> videoSuffixes = [
    'mkv', 'mp4', 'm4v', 'avi', 'mov', 'webm',
    'ts', 'm2ts', 'mpg', 'mpeg', 'wmv', 'ogv',
    'flv', 'vob',
  ];

  static const List<String> audioSuffixes = [
    'mp3', 'flac', 'm4a', 'ogg', 'opus', 'wav',
    'aac', 'mka', 'ape', 'wma', 'aiff',
  ];

  // QFileInfo::fileName() semantics ('/' everywhere, '\' also honoured).
  static String _fileNameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final cut = slash > backslash ? slash : backslash;
    return cut < 0 ? path : path.substring(cut + 1);
  }

  // QFileInfo::suffix() semantics: everything after the last '.', lowercased,
  // except a dot that starts the file name (".bashrc" has no suffix).
  static String _suffixOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  // QFileInfo::completeBaseName() semantics: the name with only the last
  // suffix stripped (".hidden.mkv" -> ".hidden", "a.b.mkv" -> "a.b").
  static String _completeBaseName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) {
      return fileName;
    }
    return fileName.substring(0, dot);
  }

  // ---------------------------------------------------------------- worker

  Future<void> _startScan() async {
    if (_disposed) {
      return;
    }
    _cancelRequested = false;
    _scanning = true;
    _lastScanCancelled = false;
    notifyListeners();

    _scanFileCount = 0;
    notifyListeners();

    try {
      await _ensureWorker();
      if (_disposed) {
        return; // disposed while the handshake was in flight
      }
      // Hand the request to the worker through its port. A new request can
      // only be posted once _scanning cleared again in _applyScanResults (or
      // chained there), so the worker processes at most one scan at a time.
      // The cancel flag is sampled at send time: a cancel that raced the
      // handshake still reaches the worker (1.x used a shared atomic).
      _workerCommands!.send(_ScanCommand(
        dirs: List<String>.of(_directories),
        maxDepth: _scanOptions.maxDepth,
        skipHidden: _scanOptions.skipHidden,
        cancelledAtStart: _cancelRequested,
      ));
    } catch (error) {
      // Isolate spawn failure has no 1.x counterpart (thread creation);
      // degrade to a finished empty scan so the UI cannot hang on
      // isScanning.
      debugPrint('LibraryStore: scan worker failed: $error');
      _applyScanResults(const <LibraryEntry>[]);
    }
  }

  Future<void> _ensureWorker() async {
    if (_workerCommands != null) {
      return;
    }
    // Serialize concurrent handshakes (chained requestScan calls overlap).
    await _workerReady;
    if (_workerCommands != null) {
      return;
    }
    final handshake = Completer<void>();
    _workerReady = handshake.future;
    final replies = ReceivePort();
    try {
      final isolate = await Isolate.spawn(
        _scanWorkerMain,
        replies.sendPort,
        debugName: 'library-scan',
      );
      _workerIsolate = isolate;
      _workerReplies = replies;
      replies.listen(
        (message) {
          if (message is SendPort) {
            _workerCommands = message;
            if (!handshake.isCompleted) {
              handshake.complete();
            }
            return;
          }
          _onWorkerMessage(message);
        },
        onDone: () {
          // The worker died (post-handshake). 1.x had no equivalent (a
          // crashed QThread took the process down); here the store resets
          // its scan state so the UI cannot hang on isScanning.
          _workerCommands = null;
          if (!handshake.isCompleted) {
            handshake.completeError(StateError('library scan worker died'));
            return;
          }
          if (_scanning && !_scanPending) {
            _scanning = false;
            notifyListeners();
          }
        },
      );
      await handshake.future;
    } catch (error) {
      replies.close();
      _workerReady = Future<void>.value();
      rethrow;
    }
  }

  // The worker lives in its own isolate; every command is processed from its
  // event loop, so no locking is needed. Results travel back through the
  // replies port.
  static void _scanWorkerMain(SendPort replies) {
    final inbox = ReceivePort();
    replies.send(inbox.sendPort);
    var cancelled = false;
    inbox.listen((message) async {
      if (message is _CancelCommand) {
        cancelled = true;
        return;
      }
      if (message is _ScanCommand) {
        cancelled = message.cancelledAtStart;
        final entries = await scanDirectories(
          message.dirs,
          ScanOptions(
            maxDepth: message.maxDepth,
            skipHidden: message.skipHidden,
          ),
          progress: (fileCount) => replies.send(_ProgressReply(fileCount)),
          cancelled: () => cancelled,
        );
        replies.send(_FinishedReply(entries));
      }
    });
  }

  void _onWorkerMessage(Object? message) {
    // A reply can race dispose() (the worker finishes while the port is
    // being torn down, like the killed-child stragglers the 1.x destructor
    // disconnected); a disposed store must not notify or persist.
    if (_disposed) {
      return;
    }
    if (message is _ProgressReply) {
      _scanFileCount = message.fileCount;
      notifyListeners();
      return;
    }
    if (message is _FinishedReply) {
      _applyScanResults(message.entries);
    }
  }

  // Queued receiver of the worker's finished reply; also used to apply a
  // scan's results.
  void _applyScanResults(List<LibraryEntry> entries) {
    // A re-scan is the authority on what exists, but a file that survived
    // keeps its last-played stamp (the walk cannot know it).
    final lastPlayed = <String, String>{
      for (final entry in _entries) entry.path: entry.lastPlayed,
    };

    _entries
      ..clear()
      ..addAll([
        for (final entry in entries)
          lastPlayed[entry.path]?.isNotEmpty == true
              ? entry.copyWith(lastPlayed: lastPlayed[entry.path])
              : entry,
      ]);
    notifyListeners();
    _save();

    // A request that arrived mid-scan runs right after this one (the worker
    // is idle again once the finished reply was delivered); scanning stays
    // true until the chained scan completes.
    if (_scanPending) {
      _scanPending = false;
      unawaited(_startScan());
      return;
    }

    _scanning = false;
    notifyListeners();

    if (_cancelRequested) {
      _cancelRequested = false;
      _lastScanCancelled = true;
      notifyListeners();
    }
  }

  // --------------------------------------------------------- persistence

  void _load() {
    _directories.clear();
    _entries.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return; // no library yet
    }

    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return; // corrupt file: start with an empty library
    }
    if (document is! Map) {
      return;
    }
    final root = document;

    final dirs = root['directories'];
    if (dirs is List) {
      for (final value in dirs) {
        final path = value is String ? value : '';
        if (path.isNotEmpty && !_directories.contains(path)) {
          _directories.add(path);
        }
      }
    }

    final array = root['entries'];
    if (array is List) {
      for (final value in array) {
        if (value is! Map) {
          continue;
        }
        final entry = LibraryEntry.fromJson(value);
        if (entry.path.isEmpty) {
          continue;
        }
        _entries.add(entry);
      }
    }
  }

  // QSaveFile semantics: write to a sibling temp file, then rename over the
  // target — a crash mid-write keeps the old file.
  void _save() {
    final dir = File(filePath).parent;
    try {
      dir.createSync(recursive: true);
      final temp = File('${dir.path}/${_fileNameOf(filePath)}.tmp');
      temp.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'directories': _directories,
            'entries': [for (final entry in _entries) entry.toJson()],
          }),
          flush: true);
      temp.renameSync(filePath);
    } catch (_) {
      // Same contract as QSaveFile::commit(): silent failure, the in-memory
      // state stays authoritative.
    }
  }

  // Stop the worker and make a running scan finish early via the cancel
  // command (checked per file). 1.x did this in the destructor; Dart has no
  // finalizers, so callers own the lifetime.
  @override
  void dispose() {
    _disposed = true;
    _workerCommands?.send(const _CancelCommand());
    _workerReplies?.close();
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerReplies = null;
    _workerIsolate = null;
    _workerCommands = null;
    super.dispose();
  }
}
