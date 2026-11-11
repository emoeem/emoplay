import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/media/library_store.dart';

// Grid grouping for the library page (EmoPlay 3.0 roadmap M4-T2:
// "SliverGrid + pinned 分组头（目录/年月分组，Kazumi popular_page 范式）").
//
// Pure logic, no widgets: the page feeds in the model's already filtered +
// sorted visible list and gets the groups to render as
// SliverMainAxisGroup(SliverPinnedHeader, SliverGrid) triplets. Grouping
// never re-orders INSIDE a group, so the page's search / typeFilter /
// sortMode semantics survive untouched — the sort decides the order of rows
// within each group and grouping only partitions it.

// What the grid groups by. [directory] = the file's parent folder (derived
// from the entry path — no extra scan); [yearMonth] = the last-played
// month, mirroring the "recent" sort's data source, with never-played
// entries in a trailing "未播放" group.
enum LibraryGroupMode { directory, yearMonth }

// One group: the pinned header text plus the rows under it. |key| is the
// stable identity (sort/ordering key), |label| the display text.
@immutable
class LibraryGridGroup {
  const LibraryGridGroup({
    required this.key,
    required this.label,
    required this.entries,
  });

  final String key;
  final String label;
  final List<LibraryEntry> entries;
}

// Partitions |entries| (the model's filtered+sorted visible list) into
// display groups. Stable: rows keep their input order inside a group; the
// group order itself follows the mode's own key order (directories
// case-insensitive ascending like the "path" sort; year-months newest
// first with "未播放" last, like the "recent" sort).
List<LibraryGridGroup> groupLibraryEntries(
  List<LibraryEntry> entries, {
  required LibraryGroupMode mode,
}) {
  if (entries.isEmpty) {
    return const <LibraryGridGroup>[];
  }

  // Key + bucket per row, preserving input order.
  final keys = <String>[];
  final buckets = <String, List<LibraryEntry>>{};
  for (final entry in entries) {
    final key = switch (mode) {
      LibraryGroupMode.directory => p.dirname(entry.path),
      LibraryGroupMode.yearMonth => _yearMonthKey(entry.lastPlayed),
    };
    if (key.isEmpty && mode == LibraryGroupMode.directory) {
      // A path without a parent directory cannot happen for indexed files
      // (the scanner only stores absolute paths); guard the degenerate case
      // by falling back to the path itself so nothing is dropped.
      keys.add(entry.path);
      (buckets[entry.path] ??= <LibraryEntry>[]).add(entry);
      continue;
    }
    keys.add(key);
    (buckets[key] ??= <LibraryEntry>[]).add(entry);
  }

  final groupKeys = buckets.keys.toList();
  switch (mode) {
    case LibraryGroupMode.directory:
      groupKeys.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      break;
    case LibraryGroupMode.yearMonth:
      // Newest month first; the never-played bucket ("") sorts last — the
      // "recent" sort's never-played-last semantics at group granularity.
      groupKeys.sort((a, b) {
        if (a.isEmpty != b.isEmpty) {
          return a.isEmpty ? 1 : -1;
        }
        return b.compareTo(a);
      });
      break;
  }

  return [
    for (final key in groupKeys)
      LibraryGridGroup(
        key: key,
        label: mode == LibraryGroupMode.directory
            ? _directoryLabel(key)
            : _yearMonthLabel(key),
        entries: List.unmodifiable(buckets[key]!),
      ),
  ];
}

// "2026-11-15T20:03:00.000" → "2026-11"; anything unparseable (empty,
// foreign-writer garbage) → "" (the never-played bucket).
String _yearMonthKey(String isoOrEmpty) {
  final instant = DateTime.tryParse(isoOrEmpty);
  if (instant == null) {
    return '';
  }
  return '${instant.year.toString().padLeft(4, '0')}-'
      '${instant.month.toString().padLeft(2, '0')}';
}

// Directory group label: the folder's own name (what a file manager shows);
// a filesystem-root parent falls back to the full path.
String _directoryLabel(String directoryPath) {
  final name = p.basename(directoryPath);
  return name.isEmpty ? directoryPath : name;
}

// "2026-11" → "2026年11月"; "" → "未播放".
String _yearMonthLabel(String key) {
  if (key.isEmpty) {
    return '未播放';
  }
  final parts = key.split('-');
  if (parts.length != 2) {
    return key;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) {
    return key;
  }
  return '$year年$month月';
}
