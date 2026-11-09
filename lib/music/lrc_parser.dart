// Dart port of mpv-emo src/music/LrcParser.{h,cpp} (A-class pure logic,
// PORT-MAP §1; docs/SPEC.md §4 P7 music mode).
//
// Parses .lrc lyric files (P7 music mode). Pure logic: no mpv, no GUI; the
// only I/O is the file reader in parseFile(). Unit-testable like the other
// config parsers (docs/architecture.md decision 6).
//
// Supported syntax (verified against common .lrc usage):
//   - "[mm:ss]" / "[mm:ss.xx]" / "[mm:ss.xxx]" timestamps (1-3 fraction
//     digits; centiseconds and milliseconds both map to seconds)
//   - multiple timestamps per line ("[00:12.00][00:45.50] text"), each
//     becoming one entry with the same text
//   - metadata tags [ti:...] (title), [ar:...] (artist), [al:...] (album)
//   - multiple timestamps per line ("[00:12.00][00:45.50] text"), each
//     becoming one entry with the same text
//   - metadata tags [ti:...] (title), [ar:...] (artist), [al:...] (album)
//   - UTF-8 BOM, CRLF and LF line endings
// Unknown bracketed tags ([by:], [offset:], ...) are skipped: they are not
// shown as lyric text. Lines without any timestamp are ignored.
library;

import 'dart:io';

/// One timed lyric line ("[mm:ss.xx] text" in .lrc terms). Multi-timestamp
/// lines expand into one entry per timestamp.
class LrcLine {
  const LrcLine({required this.time, required this.text});

  // Seconds from the start of playback.
  final double time;
  final String text;
}

/// Parsed .lrc content: the [ti]/[ar]/[al] tags plus the timed lines sorted
/// by time.
class LrcData {
  const LrcData({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.lines = const <LrcLine>[],
  });

  final String title;
  final String artist;
  final String album;
  final List<LrcLine> lines; // sorted by time
}

class LrcParser {
  LrcParser._();

  // One [mm:ss(.fraction)] timestamp. The fraction is optional and 1-3
  // digits; both [mm:ss.xx] (centiseconds) and [mm:ss.xxx] (milliseconds)
  // occur in the wild, and some writers even emit [mm:ss.x].
  static final RegExp _timeTagPattern =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  // [ti:]/[ar:]/[al:] metadata tags (case-insensitive, like the rest of
  // .lrc).
  static final RegExp _metadataTagPattern =
      RegExp(r'^\[(ti|ar|al):(.*)\]$', caseSensitive: false);

  static double _timestampToSeconds(RegExpMatch match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    var secondsTotal = minutes * 60.0 + seconds;
    final fraction = match.group(3) ?? '';
    if (fraction.isNotEmpty) {
      // "5" -> 0.5 s, "25" -> 0.25 s, "250" -> 0.25 s (position digits).
      var scale = 1.0;
      for (var i = 0; i < fraction.length; ++i) {
        scale *= 10.0;
      }
      secondsTotal += int.parse(fraction) / scale;
    }
    return secondsTotal;
  }

  /// Parses raw .lrc text; see the module doc for the grammar.
  static LrcData parse(String content) {
    // fromUtf8 keeps a leading BOM as U+FEFF; drop it so it never lands in
    // the first tag/line. (Some files also carry a UTF-16 BOM decoded to
    // U+FEFF+garbage — that garbage fails every pattern and is skipped like
    // any other unparseable line.)
    var text = content;
    while (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final data = LrcDataMutable();
    final lines = text.split('\n');
    for (var line in lines) {
      // CRLF (and stray CR) endings: trim before matching.
      while (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) {
        continue;
      }

      // Metadata tags are the only lines that parse to nothing after the
      // tag check, so try them first.
      final meta = _metadataTagPattern.firstMatch(line);
      if (meta != null) {
        final key = meta.group(1)!.toLowerCase();
        final value = meta.group(2)!.trim();
        if (key == 'ti') {
          data.title = value;
        } else if (key == 'ar') {
          data.artist = value;
        } else if (key == 'al') {
          data.album = value;
        }
        continue;
      }

      // Leading timestamps: every match becomes one lyric entry.
      final timestamps = <double>[];
      var scanFrom = 0;
      for (;;) {
        final match = _timeTagPattern.matchAsPrefix(line, scanFrom);
        // matchAsPrefix: same constraint as the C++ loop
        // (match.capturedStart() != scanFrom -> break). A timestamp must
        // start exactly where the previous one ended.
        if (match == null) {
          break;
        }
        timestamps.add(_timestampToSeconds(match as RegExpMatch));
        scanFrom = match.end;
      }
      if (timestamps.isEmpty) {
        continue; // plain text, unknown tag or garbage: not a lyric line
      }

      final lyric = line.substring(scanFrom).trim();
      for (final time in timestamps) {
        data.lines.add(LrcLine(time: time, text: lyric));
      }
    }

    // Files are not required to list lines in playback order.
    data.lines.sort((a, b) => a.time.compareTo(b.time));
    return LrcData(
      title: data.title,
      artist: data.artist,
      album: data.album,
      lines: List<LrcLine>.unmodifiable(data.lines),
    );
  }

  /// Reads [path] as UTF-8 and parses it. Missing/unreadable files return an
  /// empty LrcData (lyrics are optional decoration, never an error).
  static LrcData parseFile(String path) {
    String text;
    try {
      text = File(path).readAsStringSync();
    } catch (_) {
      return const LrcData();
    }
    return parse(text);
  }

  /// "Same name next to the audio file" matching rule: audio at
  /// `<dir>/<stem>.<ext>` pairs with `<dir>/<stem>.lrc` (and `.LRC`).
  /// Returns the candidates in probe order; the caller picks the first that
  /// exists.
  static List<String> lrcCandidates(String audioPath) {
    if (audioPath.isEmpty) {
      return const [];
    }
    final slash = audioPath.lastIndexOf('/');
    final backslash = audioPath.lastIndexOf('\\');
    final dirEnd = slash > backslash ? slash : backslash;
    final fileName = dirEnd < 0 ? audioPath : audioPath.substring(dirEnd + 1);
    final dot = fileName.lastIndexOf('.');
    // QFileInfo::completeBaseName(): only the LAST extension is replaced, so
    // "/m/a.b.flac" pairs with "/m/a.b.lrc".
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final dir = dirEnd < 0 ? '' : audioPath.substring(0, dirEnd);
    final joiner = dir.isEmpty ? '' : '/';
    return <String>[
      '$dir$joiner$stem.lrc',
      '$dir$joiner$stem.LRC',
    ];
  }
}

class LrcDataMutable {
  String title = '';
  String artist = '';
  String album = '';
  final List<LrcLine> lines = <LrcLine>[];
}
