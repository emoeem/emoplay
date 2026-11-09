import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// The playback facts HistoryStore reads from the engine, typed after the
// property queries of 1.x MpvEngine::getProperty ("path", "media-title",
// "duration", "time-pos", "idle-active"). Returning null means "property
// unavailable" (an invalid QVariant in 1.x). The media_kit adapter is wired
// by the PlaybackController port (docs/PORT-MAP.md §2); tests pass a stub.
abstract interface class HistoryEngine {
  // Live mpv property read; null when unavailable.
  Object? getProperty(String name);

  // MPV_EVENT_FILE_LOADED equivalent.
  Stream<void> get fileLoaded;

  // "idle-active" property changes.
  Stream<bool> get idleActiveChanged;
}

// One persisted "recently played" record. JSON contract (docs/SPEC.md §7,
// identical field-for-field with 1.x history.json): each entry has path,
// title, position, duration and lastPlayedAt (ISO 8601).
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.path,
    required this.title,
    required this.position,
    required this.duration,
    required this.lastPlayedAt,
  });

  factory HistoryEntry.fromJson(Map<Object?, Object?> json) => HistoryEntry(
        path: json['path'] is String ? json['path'] as String : '',
        title: json['title'] is String ? json['title'] as String : '',
        position: json['position'] is num ? (json['position'] as num).toDouble() : 0.0,
        duration: json['duration'] is num ? (json['duration'] as num).toDouble() : 0.0,
        lastPlayedAt:
            json['lastPlayedAt'] is String ? json['lastPlayedAt'] as String : '',
      );

  final String path;
  final String title;
  final double position;
  final double duration;
  final String lastPlayedAt;

  HistoryEntry copyWith({double? position}) => HistoryEntry(
        path: path,
        title: title,
        position: position ?? this.position,
        duration: duration,
        lastPlayedAt: lastPlayedAt,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'title': title,
        'position': position,
        'duration': duration,
        'lastPlayedAt': lastPlayedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.path == path &&
      other.title == title &&
      other.position == position &&
      other.duration == duration &&
      other.lastPlayedAt == lastPlayedAt;

  @override
  int get hashCode => Object.hash(path, title, position, duration, lastPlayedAt);

  @override
  String toString() =>
      'HistoryEntry($path, $title, $position/$duration, $lastPlayedAt)';
}

// Persistent "recently played" history, kept in a JSON file.
//
// Recording: when the engine reports MPV_EVENT_FILE_LOADED the current
// media (path / media-title / duration) is recorded at the top of the
// list. While playback runs, a 5-second timer refreshes the current
// entry's position from the engine's "time-pos" property, so the stored
// value survives an app crash or a forced quit.
//
// Persistence: entries are stored under
//   <application support directory>/history.json
// as {"version": 1, "entries": [...]}; each entry has path, title,
// position, duration and lastPlayedAt (ISO 8601). The list is deduped by
// path (re-play moves the entry to the top) and capped at 50 entries.
// Writes are atomic (temp file + rename, the QSaveFile pattern).
//
// Tests can pass an explicit file path and a null engine, which makes the
// whole store runnable headless; the engine-driven paths are guarded
// no-ops when no engine or no media is present.
class HistoryStore extends ChangeNotifier {
  // |engine| may be null (then nothing is recorded automatically);
  // |filePath| is injected so tests can use a temporary location.
  HistoryStore(this._engine, this.filePath) {
    _load();

    if (_engine != null) {
      final engine = _engine;
      _subscriptions.add(engine.fileLoaded.listen((_) => onFileLoaded()));
      _subscriptions.add(engine.idleActiveChanged.listen((idle) {
        _idle = idle;
      }));
      // Playback state authority is mpv; pick up where it stands right now
      // (the observed-property events for past changes are not replayed).
      final idle = engine.getProperty('idle-active');
      if (idle != null) {
        _idle = idle is bool ? idle : false;
      }
    }

    _refreshTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => onTimerTick());
  }

  // Default storage location; the application support directory needs
  // path_provider's platform channel, so this is async (1.x
  // QStandardPaths::AppDataLocation).
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/history.json';
  }

  final HistoryEngine? _engine;
  final String filePath;
  final List<StreamSubscription<void>> _subscriptions = <StreamSubscription<void>>[];
  late final Timer _refreshTimer;
  bool _idle = true;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);
  final List<HistoryEntry> _entries = <HistoryEntry>[];

  static const int _maxEntries = 50;

  // Insert (or move to the top) an entry for |path| and persist.
  // Empty paths are ignored.
  void recordPlayback(String path, String title, double position,
      double duration) {
    if (path.isEmpty) {
      return;
    }

    final entry = HistoryEntry(
      path: path,
      title: title,
      position: position,
      duration: duration,
      lastPlayedAt: DateTime.now().toIso8601String(),
    );

    // Dedupe by path: the fresh entry replaces the old one and moves to top.
    _entries.removeWhere((existing) => existing.path == path);
    _entries.insert(0, entry);
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }

    notifyListeners();
    _save();
  }

  // Update only the stored position of the entry for |path|, keeping its
  // order and lastPlayedAt untouched. No-op when the path is unknown.
  void updateEntryPosition(String path, double position) {
    if (path.isEmpty) {
      return;
    }

    final index = _entries.indexWhere((entry) => entry.path == path);
    if (index < 0) {
      return;
    }
    // Paused playback reports the same position every tick; skip the
    // disk write in that case.
    if (_entries[index].position == position) {
      return;
    }
    _entries[index] = _entries[index].copyWith(position: position);
    notifyListeners();
    _save();
  }

  // Drop one entry from the list (the Home "remove from history" action).
  // Only the history record is removed — never the media file itself.
  void removeEntry(String path) {
    if (path.isEmpty) {
      return;
    }

    final index = _entries.indexWhere((entry) => entry.path == path);
    if (index < 0) {
      return;
    }
    _entries.removeAt(index);
    notifyListeners();
    _save();
  }

  // Drop every history entry (the settings "clear history" action). Only
  // the records go away; the media files are untouched.
  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
    _save();
  }

  // 1.x connected this to MpvEngine::fileLoaded; exposed for direct
  // invocation from tests and for engine adapters that prefer calls over
  // streams.
  void onFileLoaded() {
    final engine = _engine;
    if (engine == null) {
      return;
    }

    final path = engine.getProperty('path');
    if (path is! String || path.isEmpty) {
      return; // no media behind the event; nothing to record
    }

    final title = engine.getProperty('media-title');
    final duration = engine.getProperty('duration');
    recordPlayback(
        path,
        title is String ? title : '',
        0.0,
        duration is num ? duration.toDouble() : 0.0);
  }

  // The 5 s tick; public for the same reason as onFileLoaded.
  void onTimerTick() {
    final engine = _engine;
    if (engine == null || _idle) {
      return;
    }

    // Resolve the current file live instead of caching it: when the playlist
    // advances, mpv's core can already expose the next file's time-pos while
    // our FILE_LOADED event is still queued, and a cached path would write
    // the new ~0 position into the previous file's entry (losing its resume
    // point). Path and time-pos are read back-to-back from the same core
    // state, and an empty path (loading gap) is a clean no-op.
    final path = engine.getProperty('path');
    if (path is! String || path.isEmpty) {
      return;
    }

    final position = engine.getProperty('time-pos');
    if (position is! num) {
      return; // property unavailable (e.g. between files)
    }
    updateEntryPosition(path, position.toDouble());
  }

  // --------------------------------------------------------- persistence

  void _load() {
    _entries.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return; // no history yet
    }

    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return; // corrupt file: start with an empty history
    }

    List<Object?>? array;
    if (document is List) {
      // Legacy shape accepted by 1.x as well: a bare top-level array.
      array = document;
    } else if (document is Map) {
      final entries = document['entries'];
      array = entries is List ? entries : null;
    }
    if (array == null) {
      return;
    }

    for (final value in array) {
      if (value is! Map) {
        continue;
      }
      final entry = HistoryEntry.fromJson(value);
      if (entry.path.isEmpty) {
        continue;
      }
      _entries.add(entry);
    }
  }

  // QSaveFile semantics: write to a sibling temp file, then rename over the
  // target — a crash mid-write keeps the old file.
  void _save() {
    final dir = File(filePath).parent;
    try {
      dir.createSync(recursive: true);
      final name = filePath.split('/').last;
      final temp = File('${dir.path}/$name.tmp');
      temp.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': [for (final entry in _entries) entry.toJson()],
          }),
          flush: true);
      temp.renameSync(filePath);
    } catch (_) {
      // Same contract as QSaveFile::commit(): silent failure, the in-memory
      // state stays authoritative.
    }
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    super.dispose();
  }
}
