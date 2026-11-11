import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:emoplay/media/library_store.dart';

// Episode parsing and the show-season-episode grouping service (user-added
// roadmap item M4-T6, 2026-11-12: "剧集分组：文件名 SxxEyy 季集解析（纯逻辑）
// → 剧-季-集三级分组服务").
//
// Pure logic, no IO. Two layers:
//
//  1. [parseEpisodeMarker] reads season/episode facts out of a FILE NAME —
//     the classic release conventions "S01E02" (case-insensitive, padding
//     optional) and "1x02". A marker only counts at a word boundary (the
//     character before it must not be alphanumeric), so "M4S01E02" is a
//     file name, not an episode of show "M4".
//  2. [partitionEpisodes] groups library entries into the three levels:
//     shows (key = the parsed show name, case-insensitive) → seasons
//     (ascending, season 0 = specials first) → episodes (ascending episode
//     number, ties keep the caller's order). Entries without a parseable
//     marker are returned untouched in [EpisodePartition.ungrouped] so no
//     row is ever lost — the caller decides what to show them as.
//
// Ordering inside a group is deterministic (episode number, then the
// caller's order); the caller's input order is otherwise never re-sorted —
// the same contract library_grid_groups.dart states for the M4-T2 modes.

/// Season/episode facts parsed from a file name. [show] is the cleaned part
/// before the marker (separators as spaces); '' when the marker starts the
/// name.
@immutable
class EpisodeFacts {
  const EpisodeFacts({
    required this.show,
    required this.season,
    required this.episode,
  });

  final String show;
  final int season;
  final int episode;

  @override
  bool operator ==(Object other) =>
      other is EpisodeFacts &&
      other.show == show &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(show, season, episode);

  @override
  String toString() => 'EpisodeFacts($show, S${season}E$episode)';
}

/// Parses "Show.Name.S01E02.1080p.mkv" / "show s3e12.mkv" /
/// "Series.1x05.mkv" into its facts, or null when the name carries no
/// season/episode marker (a movie, a season pack root, garbage). |fileName|
/// is the file name WITH extension — the scan ignores it naturally because a
/// marker must sit before the extension and the digit-run guards reject
/// padding longer than the convention allows.
EpisodeFacts? parseEpisodeMarker(String fileName) {
  // SxxEyy first (the dominant convention); the digit runs are bounded
  // (season ≤2 digits, episode ≤3) and the trailing lookahead plus
  // backtracking rejects longer runs ("S012E05", "S01E1234" match nothing
  // rather than mis-parsing). Multi-episode files ("S01E02E03") parse as
  // their FIRST episode.
  final sxxEyy = _sxxEyyPattern.firstMatch(fileName);
  if (sxxEyy != null) {
    return EpisodeFacts(
      show: _cleanShowName(fileName.substring(0, sxxEyy.start)),
      season: int.parse(sxxEyy.group(2)!),
      episode: int.parse(sxxEyy.group(3)!),
    );
  }
  final dxdd = _dxddPattern.firstMatch(fileName);
  if (dxdd != null) {
    return EpisodeFacts(
      show: _cleanShowName(fileName.substring(0, dxdd.start)),
      season: int.parse(dxdd.group(2)!),
      episode: int.parse(dxdd.group(3)!),
    );
  }
  return null;
}

// The boundary before the marker is captured so the show-name prefix ends
// where the marker really starts (the boundary char itself is separator
// noise the cleaner trims).
final RegExp _sxxEyyPattern = RegExp(
    r'(^|[^A-Za-z0-9])S(\d{1,2})E(\d{1,3})(?![0-9])',
    caseSensitive: false);
final RegExp _dxddPattern = RegExp(
    r'(^|[^A-Za-z0-9])(\d{1,2})x(\d{1,3})(?![0-9])',
    caseSensitive: false);

/// "Breaking.Bad." → "Breaking Bad"; "Show_-_S01E02" prefix → "Show"; a
/// prefix of pure separators → ''.
String _cleanShowName(String raw) {
  var cleaned =
      raw.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
  const strip = <String>{
    ' ', '-', '~', '[', ']', '(', ')', '.', ',', '!', '?', ';', ':',
  };
  while (cleaned.isNotEmpty && strip.contains(cleaned[0])) {
    cleaned = cleaned.substring(1);
  }
  while (cleaned.isNotEmpty && strip.contains(cleaned[cleaned.length - 1])) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  return cleaned;
}

// ------------------------------------------------------ grouping service

/// One season of one show: its number (0 = specials) and its episodes in
/// ascending episode order (ties keep the caller's order).
@immutable
class SeasonGroup {
  const SeasonGroup({required this.season, required this.episodes});

  final int season;
  final List<LibraryEntry> episodes;
}

/// One show: the parsed name (display text, may be '' — the caller decides
/// the fallback label) and its seasons ascending.
@immutable
class ShowGroup {
  const ShowGroup({required this.show, required this.seasons});

  final String show;
  final List<SeasonGroup> seasons;
}

/// The result of partitioning library entries: shows in case-insensitive
/// name order, and everything that parsed as NO episode (movies, audio, odd
/// names) in [ungrouped], untouched, in input order.
@immutable
class EpisodePartition {
  const EpisodePartition({required this.shows, required this.ungrouped});

  final List<ShowGroup> shows;
  final List<LibraryEntry> ungrouped;
}

/// Groups |entries| into the show → season → episode hierarchy from the
/// file-name markers. Callers pre-filter what belongs here (the library
/// page feeds video entries only); the service itself is type-agnostic.
EpisodePartition partitionEpisodes(List<LibraryEntry> entries) {
  final showOrder = <String>[];
  final shows = <String, Map<int, List<LibraryEntry>>>{};
  // Bucket key -> the display name of its FIRST member (input order — the
  // caller's sort decides; the key itself is only the lowercased form).
  final showDisplay = <String, String>{};
  final ungrouped = <LibraryEntry>[];

  for (final entry in entries) {
    final facts = parseEpisodeMarker(p.basename(entry.path));
    if (facts == null) {
      ungrouped.add(entry);
      continue;
    }
    // Group key: case-insensitive show name ("" for marker-first names —
    // those shows collapse into one unnamed group, the page labels it).
    final key = facts.show.toLowerCase();
    if (!shows.containsKey(key)) {
      shows[key] = <int, List<LibraryEntry>>{};
      showOrder.add(key);
      showDisplay[key] = facts.show;
    }
    shows[key]!.putIfAbsent(facts.season, () => <LibraryEntry>[]).add(entry);
  }

  // Per show: seasons ascending with 0 (specials) first, and inside each
  // season episodes ascending by parsed episode number, ties in input
  // order.
  final result = <ShowGroup>[];
  for (final key in showOrder) {
    final seasonsByKey = shows[key]!;
    final seasonNumbers = seasonsByKey.keys.toList()..sort();
    final displayShow = showDisplay[key] ?? key;
    final seasonGroups = <SeasonGroup>[];
    for (final season in seasonNumbers) {
      final members = seasonsByKey[season]!;
      final sorted = List<LibraryEntry>.of(members);
      final numbers = <LibraryEntry, int>{
        for (final entry in members)
          entry: parseEpisodeMarker(p.basename(entry.path))!.episode,
      };
      sorted.sort((a, b) {
        final byNumber = numbers[a]!.compareTo(numbers[b]!);
        if (byNumber != 0) {
          return byNumber;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      seasonGroups.add(SeasonGroup(season: season, episodes: sorted));
    }
    result.add(ShowGroup(show: displayShow, seasons: seasonGroups));
  }

  return EpisodePartition(shows: result, ungrouped: ungrouped);
}
