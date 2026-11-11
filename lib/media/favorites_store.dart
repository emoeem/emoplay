import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// The favorites collection (EmoPlay 3.0 roadmap docs/EMOPLAY-3.0-ROADMAP.md
// M4-T3): a user-curated, manually ordered subset of the media library,
// persisted to `favorites.json` in the application support directory.
//
// The file is a NEW AppData file — the same precedent media_meta.json set
// (M4-T4): adding files is not modifying the three §7 schemas
// (history.json / library.json / settings.json stay byte-compatible, guarded
// by test/data_compat_spec7_test.dart). The document shape is
// `{"version":1,"entries":[{"path":…,"addedAt":…}, …]}` — the persisted
// record is exactly the roadmap's "条目 = MediaItem path + addedAt": the
// MediaItem identity (its absolute-path unique key) plus the favorite-only
// timestamp. Nothing else is copied: title/type/size/lastPlayed keep living
// in the §7 stores and the UI joins favorites against the library index at
// render time, so a favorite never duplicates (or rewrites) §7 data and a
// library re-scan or a notePlayed() stamp can never touch this file — and
// vice versa (test/favorites_store_test.dart pins the isolation).
//
// Order IS data: the list order is the user's favorite order, maintained by
// the ReorderableListView sheet (PiliPlus fav_folder_sort/view.dart:71
// paradigm). New favorites append at the end; reordering persists the drag
// result verbatim.
//
// Storage is the house atomic write (sibling temp file + rename, the
// QSaveFile pattern, same as EmoPlaySettings/LibraryStore): a crash
// mid-write keeps the old file. A missing or corrupt file degrades to an
// empty in-memory collection (the corrupt-file contract of every store in
// this codebase); a parseable document with malformed rows keeps its usable
// rows and drops the rest, duplicates collapse onto the first occurrence.
class FavoritesStore extends ChangeNotifier {
  // |filePath| is the storage JSON; injected so tests use a temporary
  // location (the 1.x QTemporaryDir pattern every store test follows).
  FavoritesStore(this.filePath) {
    _load();
  }

  // Default storage location; the application support directory needs
  // path_provider's platform channel, so this is async.
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/favorites.json';
  }

  // Path of the backing JSON document.
  final String filePath;

  // The favorites in the user's order (oldest first, newest appended).
  List<FavoriteEntry> get entries => List.unmodifiable(_entries);
  final List<FavoriteEntry> _entries = <FavoriteEntry>[];

  int get count => _entries.length;

  bool contains(String path) => _indexOf(path) >= 0;

  // Adds |path| as a favorite appended at the end of the user's order.
  // Returns false (a no-op) for an empty path or a path that is already
  // favorited — the path is the unique key, so a duplicate can never insert
  // a second row (the 去重 contract; the first addedAt wins).
  bool add(String path) {
    if (path.isEmpty || contains(path)) {
      return false;
    }
    _entries.add(FavoriteEntry(path: path, addedAt: _nowIso()));
    _changed();
    return true;
  }

  // Removes |path| from the favorites. Unknown paths are a no-op (false).
  bool remove(String path) {
    final index = _indexOf(path);
    if (index < 0) {
      return false;
    }
    _entries.removeAt(index);
    _changed();
    return true;
  }

  // Toggles |path|: adds it when missing, removes it when present (the
  // badge's tap contract). Returns the new state (true = now favorited).
  bool toggle(String path) {
    if (contains(path)) {
      remove(path);
      return false;
    }
    return add(path);
  }

  // Applies a reorder result to the user's order.
  //
  // Indexes follow the ReorderableListView.onReorderItem contract (this
  // Flutter version's replacement for the deprecated onReorder — see
  // reorderable_list.dart, and the PiliPlus fav_folder_sort/view.dart:71
  // paradigm the roadmap cites): |newIndex| is the drop position AFTER the
  // item was removed, i.e. the widget already adjusted it. The store simply
  // moves the row. Out-of-range indexes and same-position moves are no-ops
  // that never notify or rewrite the file.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _entries.length) {
      return;
    }
    if (newIndex < 0 || newIndex > _entries.length - 1) {
      return;
    }
    if (newIndex == oldIndex) {
      return;
    }
    _entries.insert(newIndex, _entries.removeAt(oldIndex));
    _changed();
  }

  int _indexOf(String path) =>
      _entries.indexWhere((entry) => entry.path == path);

  void _changed() {
    notifyListeners();
    _save();
  }

  static String _nowIso() => DateTime.now().toIso8601String();

  // --------------------------------------------------------- persistence

  void _load() {
    _entries.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return; // no favorites yet
    }

    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return; // corrupt file: start with an empty collection
    }
    if (document is! Map) {
      return;
    }
    final root = document;

    final array = root['entries'];
    if (array is! List) {
      return;
    }
    for (final value in array) {
      if (value is! Map) {
        continue;
      }
      final entry = FavoriteEntry.fromJson(value);
      // Drop unusable rows and collapse duplicates (path = unique key,
      // first occurrence wins) — a hand-edited file cannot insert noise.
      if (entry.path.isEmpty || contains(entry.path)) {
        continue;
      }
      _entries.add(entry);
    }
  }

  // QSaveFile semantics: write to a sibling temp file, then rename over the
  // target — a crash mid-write keeps the old file.
  void _save() {
    final file = File(filePath);
    final dir = file.parent;
    try {
      dir.createSync(recursive: true);
      final temp = File('${dir.path}/${_fileNameOf(filePath)}.tmp');
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

  static String _fileNameOf(String path) => path.split('/').last;
}

// One persisted favorite. Field-for-field the roadmap contract: the
// favorited item's [path] (MediaItem's unique key) and [addedAt] (ISO 8601).
// The timestamp is the store's own fact — it is NOT a §7 field and never
// written into any other file.
@immutable
class FavoriteEntry {
  const FavoriteEntry({required this.path, this.addedAt = ''});

  factory FavoriteEntry.fromJson(Map<Object?, Object?> json) => FavoriteEntry(
        path: json['path'] is String ? json['path'] as String : '',
        addedAt: json['addedAt'] is String ? json['addedAt'] as String : '',
      );

  // Absolute local path (MediaItem.path key semantics).
  final String path;

  // ISO 8601 instant the favorite was created ("" from a foreign writer
  // that omitted it — the record stays usable).
  final String addedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'addedAt': addedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is FavoriteEntry &&
      other.path == path &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(path, addedAt);

  @override
  String toString() => 'FavoriteEntry($path, $addedAt)';
}
