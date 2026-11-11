import 'dart:convert';

/// One entry of mpv's `chapter-list` property (M3-T2 章节导航).
///
/// mpv exposes chapter start times only; the end of a chapter is the start of
/// the following one, so [endTime] is filled during parsing and stays `null`
/// for the last chapter ("plays until the media ends").
class MediaChapter {
  const MediaChapter({
    required this.title,
    required this.startTime,
    this.endTime,
  });

  /// Chapter title as stored in the container; mpv substitutes the empty
  /// string when the container carries no title for a chapter.
  final String title;

  final Duration startTime;

  /// Start of the next chapter, or `null` for the last one.
  final Duration? endTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaChapter &&
          other.title == title &&
          other.startTime == startTime &&
          other.endTime == endTime;

  @override
  int get hashCode => Object.hash(title, startTime, endTime);

  @override
  String toString() =>
      'MediaChapter($title, $startTime..${endTime?.toString() ?? "end"})';
}

/// Parses the string serialization mpv delivers for the `chapter-list`
/// property.
///
/// The Predidit media-kit fork (83b7ca6, consulted read-only in the pub
/// cache) observes properties with MPV_FORMAT_NONE and hands the listener the
/// value read back as MPV_FORMAT_STRING (real.dart `_handler` ->
/// `readNativeString`). Probed 2026-11-11 against the shipped libmpv
/// ("mpv v0.41.0-11-gf011d73d5-dirty"): `chapter-list` stringifies as JSON,
/// e.g. `[{"title":"第一章 开场","time":0.000000},...]`, with `[]` for a file
/// without chapters and `title` always present (empty string when untitled).
/// Anything that is not that JSON shape — older mpv builds printed node lists
/// in the option `%len%` escaping, and unavailable values never reach the
/// listener at all — degrades to an empty chapter list instead of crashing.
List<MediaChapter> parseMpvChapterList(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) {
    return const [];
  }
  final entries = <({String title, double start})>[];
  for (final entry in decoded) {
    if (entry is! Map) {
      continue;
    }
    final time = entry['time'];
    if (time is! num) {
      continue;
    }
    final title = entry['title'];
    entries.add((
      title: title is String ? title : '',
      start: time.toDouble(),
    ));
  }
  if (entries.isEmpty) {
    return const [];
  }
  return [
    for (var i = 0; i < entries.length; i++)
      MediaChapter(
        title: entries[i].title,
        startTime: _durationFromSeconds(entries[i].start),
        endTime: i + 1 < entries.length
            ? _durationFromSeconds(entries[i + 1].start)
            : null,
      ),
  ];
}

Duration _durationFromSeconds(double seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

/// Index of the chapter covering [position]: the upper-bound binary search
/// over the (ascending) chapter start times the roadmap pins for M3-T2
/// (`titleAtPosition 上界二分`). Returns the greatest index whose
/// [MediaChapter.startTime] is <= [position], or -1 when the position is
/// before the first chapter (only possible when the first chapter does not
/// start at zero) or the list is empty.
int chapterIndexAt(List<MediaChapter> chapters, Duration position) {
  var low = 0;
  var high = chapters.length - 1;
  var result = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (chapters[mid].startTime <= position) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

/// Resolves the chapter that a next/previous step ([delta] = +1/-1) should
/// jump to, or `null` when the step is a no-op: without chapters, or clamped
/// past either end of the table.
///
/// While mpv's `chapter` property has not reported a valid index
/// ([currentIndex] == -1 — never available or not yet fired), the active
/// chapter is located from the playback position via [chapterIndexAt].
int? resolveChapterTarget({
  required List<MediaChapter> chapters,
  required int currentIndex,
  required Duration position,
  required int delta,
}) {
  if (chapters.isEmpty) {
    return null;
  }
  var index = currentIndex;
  if (index < 0) {
    index = chapterIndexAt(chapters, position);
  }
  final target = index + delta;
  if (target < 0 || target >= chapters.length) {
    return null;
  }
  return target;
}
