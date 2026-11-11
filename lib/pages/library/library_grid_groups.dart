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
// entries in a trailing "未播放" group; [movies] = the M4-T6 movie view —
// videos WITHOUT an episode marker (the caller partitions first via
// episode_grouper.dart), keyed by their movie title (the NFO title when the
// caller resolves one, else the file name); [episodes] is NOT a
// groupLibraryEntries mode — the show-season-episode hierarchy is three
// levels deep and the page renders it with its own sliver builder
// (partitionEpisodes), so asking this function for it yields nothing.
enum LibraryGroupMode { directory, yearMonth, movies, episodes }

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
// first with "未播放" last, like the "recent" sort; movie titles
// case-insensitive ascending).
//
// |movieTitleOf| resolves the movie display title for the [movies] mode —
// the page injects the NFO-title override (nfo_meta_cache.dart); when null
// the file's own title (completeBaseName) is used. It is ignored by the
// other single-level modes.
List<LibraryGridGroup> groupLibraryEntries(
  List<LibraryEntry> entries, {
  required LibraryGroupMode mode,
  String Function(LibraryEntry entry)? movieTitleOf,
}) {
  if (entries.isEmpty || mode == LibraryGroupMode.episodes) {
    // Empty input, or the three-level [episodes] mode that never routes
    // through here (see the enum's contract).
    return const <LibraryGridGroup>[];
  }

  // Key + bucket per row, preserving input order. The movies mode keeps a
  // display label per key (first non-empty resolved title in input order —
  // the caller's sort decides which member represents the movie).
  final buckets = <String, List<LibraryEntry>>{};
  final labels = <String, String>{};
  for (final entry in entries) {
    final key = switch (mode) {
      LibraryGroupMode.directory => p.dirname(entry.path),
      LibraryGroupMode.yearMonth => _yearMonthKey(entry.lastPlayed),
      LibraryGroupMode.movies =>
        _movieKey(entry, movieTitleOf).toLowerCase(),
      LibraryGroupMode.episodes => '',
    };
    if (key.isEmpty && mode == LibraryGroupMode.directory) {
      // A path without a parent directory cannot happen for indexed files
      // (the scanner only stores absolute paths); guard the degenerate case
      // by falling back to the path itself so nothing is dropped.
      buckets
          .putIfAbsent(entry.path, () => <LibraryEntry>[])
          .add(entry);
      continue;
    }
    buckets.putIfAbsent(key, () => <LibraryEntry>[]).add(entry);
    if (mode == LibraryGroupMode.movies && !labels.containsKey(key)) {
      final label = _movieKey(entry, movieTitleOf);
      if (label.isNotEmpty) {
        labels[key] = label;
      }
    }
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
    case LibraryGroupMode.movies:
      groupKeys.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      break;
    case LibraryGroupMode.episodes:
      break; // unreachable: early-returned above
  }

  return [
    for (final key in groupKeys)
      LibraryGridGroup(
        key: key,
        label: mode == LibraryGroupMode.directory
            ? _directoryLabel(key)
            : mode == LibraryGroupMode.movies
                ? (labels[key] ?? key)
                : _yearMonthLabel(key),
        entries: List.unmodifiable(buckets[key]!),
      ),
  ];
}

// The movie display title for one entry: the injected NFO-title resolver,
// falling back to the entry's own title (the scanner's completeBaseName)
// and finally the path so a degenerate row is never dropped.
String _movieKey(
    LibraryEntry entry, String Function(LibraryEntry)? movieTitleOf) {
  final resolved = movieTitleOf?.call(entry) ?? entry.title;
  if (resolved.isNotEmpty) {
    return resolved;
  }
  return entry.title.isNotEmpty ? entry.title : entry.path;
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
