import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

// Kodi NFO parsing (user-added roadmap item M4-T6, 2026-11-12: "Kodi NFO
// 解析：movie.nfo / tvshow.nfo / 剧集 nfo（XML：title/plot/season/episode/
// thumb 等），容错解析（损坏 XML 跳过字段不崩溃），纯逻辑服务可测").
//
// Pure logic — no filesystem, no network. The scanner is deliberately
// hand-rolled instead of a strict XML package: real-world .nfo files are
// hostile (scraped-page garbage before the root element, BOM, comments,
// CDATA-wrapped plots, truncated downloads, entity-escaped titles), and the
// contract here is degradation, never a crash: [parseNfoContent] returns
// whatever fields survived. A field whose element is malformed is skipped;
// the record stays usable.
//
// Kodi conventions covered:
//  - root elements <movie> (movie.nfo), <tvshow> (tvshow.nfo) and
//    <episodedetails> (per-episode sidecar .nfo) — the kind comes from the
//    ROOT ELEMENT, not the file name (Kodi accepts any file name; the file
//    name only decides where to look — see [nfoCandidatesFor]);
//  - Kodi's own reader skips everything before the first root element, so
//    leading junk ("1http://forum.xbmc.org/", HTML error pages) is tolerated
//    the same way;
//  - a file MAY contain several roots (stacked episodes); the first block
//    wins, matching Kodi's first-episode behaviour;
//  - <thumb> appears with attributes (<thumb aspect="poster" …>URL</thumb>)
//    and several times per file — all values are collected verbatim. Per the
//    local-first contract these URLs are RECORDED ONLY, never fetched (no
//    http import exists in this file by construction).

/// What kind of NFO document was recognized — from the root element name.
enum NfoKind { movie, tvshow, episode, unknown }

/// One parsed NFO document. Every field is nullable/empty when the source
/// did not provide it (or was malformed — the tolerant-parse contract).
@immutable
class NfoDocument {
  const NfoDocument({
    this.kind = NfoKind.unknown,
    this.title = '',
    this.plot = '',
    this.outline = '',
    this.tagline = '',
    this.year,
    this.rating,
    this.genres = const <String>[],
    this.premiered = '',
    this.aired = '',
    this.season,
    this.episode,
    this.thumbs = const <String>[],
    this.uniqueId = '',
    this.trailer = '',
    this.studio = '',
  });

  final NfoKind kind;

  // <title>, <plot>, <outline>, <tagline>, <studio>, <trailer>,
  // <uniqueid> (first value), <premiered> (tvshow date) / <aired> (episode
  // date) — all trimmed strings.
  final String title;
  final String plot;
  final String outline;
  final String tagline;
  final String studio;
  final String trailer;
  final String uniqueId;
  final String premiered;
  final String aired;

  // <year> (4-digit), <rating> (decimal), <season> / <episode> — parsed
  // leniently (first integer/decimal run in the element text); null when
  // absent or unparseable.
  final int? year;
  final double? rating;
  final int? season;
  final int? episode;

  // Every <genre> value, and every <thumb> value (URL or path — recorded,
  // never downloaded).
  final List<String> genres;
  final List<String> thumbs;

  bool get isEmpty =>
      kind == NfoKind.unknown &&
      title.isEmpty &&
      plot.isEmpty &&
      outline.isEmpty &&
      tagline.isEmpty &&
      year == null &&
      rating == null &&
      genres.isEmpty &&
      premiered.isEmpty &&
      aired.isEmpty &&
      season == null &&
      episode == null &&
      thumbs.isEmpty &&
      uniqueId.isEmpty &&
      trailer.isEmpty &&
      studio.isEmpty;

  factory NfoDocument.fromJson(Map<Object?, Object?> json) {
    final kindText = json['kind'];
    final list = <String>[];
    void collect(Object? field, List<String> into) {
      if (field is List) {
        for (final value in field) {
          if (value is String && value.isNotEmpty) {
            into.add(value);
          }
        }
      }
    }

    collect(json['genres'], list);
    final genres = List<String>.of(list);
    list.clear();
    collect(json['thumbs'], list);

    return NfoDocument(
      kind: switch (kindText) {
        'movie' => NfoKind.movie,
        'tvshow' => NfoKind.tvshow,
        'episode' => NfoKind.episode,
        _ => NfoKind.unknown,
      },
      title: json['title'] is String ? json['title'] as String : '',
      plot: json['plot'] is String ? json['plot'] as String : '',
      outline: json['outline'] is String ? json['outline'] as String : '',
      tagline: json['tagline'] is String ? json['tagline'] as String : '',
      year: _intFrom(json['year']),
      rating: _doubleFrom(json['rating']),
      genres: genres,
      premiered: json['premiered'] is String ? json['premiered'] as String : '',
      aired: json['aired'] is String ? json['aired'] as String : '',
      season: _intFrom(json['season']),
      episode: _intFrom(json['episode']),
      thumbs: list,
      uniqueId: json['uniqueId'] is String ? json['uniqueId'] as String : '',
      trailer: json['trailer'] is String ? json['trailer'] as String : '',
      studio: json['studio'] is String ? json['studio'] as String : '',
    );
  }

  static int? _intFrom(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static double? _doubleFrom(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': switch (kind) {
          NfoKind.movie => 'movie',
          NfoKind.tvshow => 'tvshow',
          NfoKind.episode => 'episode',
          NfoKind.unknown => 'unknown',
        },
        'title': title,
        'plot': plot,
        'outline': outline,
        'tagline': tagline,
        'year': year,
        'rating': rating,
        'genres': genres,
        'premiered': premiered,
        'aired': aired,
        'season': season,
        'episode': episode,
        'thumbs': thumbs,
        'uniqueId': uniqueId,
        'trailer': trailer,
        'studio': studio,
      };

  @override
  bool operator ==(Object other) =>
      other is NfoDocument &&
      other.kind == kind &&
      other.title == title &&
      other.plot == plot &&
      other.outline == outline &&
      other.tagline == tagline &&
      other.year == year &&
      other.rating == rating &&
      other.premiered == premiered &&
      other.aired == aired &&
      other.season == season &&
      other.episode == episode &&
      other.uniqueId == uniqueId &&
      other.trailer == trailer &&
      other.studio == studio &&
      _listEquals(other.genres, genres) &&
      _listEquals(other.thumbs, thumbs);

  @override
  int get hashCode => Object.hash(kind, title, plot, outline, tagline, year,
      rating, premiered, aired, season, episode, uniqueId, trailer, studio);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Parses NFO file contents into a [NfoDocument]. NEVER throws — malformed,
/// truncated or even non-XML input degrades to whatever fields survived (a
/// completely unrecognizable input yields `NfoKind.unknown` with empty
/// fields; check [NfoDocument.isEmpty]).
NfoDocument parseNfoContent(String contents) {
  try {
    return _parseNfo(contents);
  } catch (_) {
    // The scanner is written to be total, but the contract outranks the
    // implementation: any surprise degrades to an empty record.
    return const NfoDocument();
  }
}

/// The sidecar NFO candidates for a video, in Kodi's precedence order (the
/// first EXISTING one is the video's own NFO):
///  1. `<videoBaseName>.nfo` — the per-file sidecar (movies and episodes);
///  2. `movie.nfo` — the Kodi movie-folder convention.
///
/// Pure path arithmetic (no IO). The show-level metadata file is NOT part of
/// this list — `tvshow.nfo` ([tvshowNfoFileName]) is a directory fact looked
/// up separately by the cache, not a per-video candidate.
const String tvshowNfoFileName = 'tvshow.nfo';

List<String> nfoCandidatesFor(String videoPath) {
  final dir = p.dirname(videoPath);
  return <String>[
    '$dir/${p.basenameWithoutExtension(videoPath)}.nfo',
    '$dir/movie.nfo',
  ];
}

// ------------------------------------------------------------- the scanner

NfoDocument _parseNfo(String contents) {
  // BOM (scrapers and Windows editors love it) — strip before scanning.
  var text = contents.startsWith('\uFEFF') ? contents.substring(1) : contents;
  // Comments are removed up front: they can wrap whole fields (Kodi users
  // comment out stale tags) and must never be parsed as data.
  text = _stripComments(text);

  // Root element: prefer the known Kodi kinds, anywhere in the text (leading
  // junk tolerated), first occurrence wins (stacked blocks: first episode).
  final rootMatch =
      RegExp(r'<\s*(movie|tvshow|episodedetails)(?=[\s/>])', caseSensitive: false)
          .firstMatch(text);
  String rootName;
  NfoKind kind;
  int rootStart;
  if (rootMatch != null) {
    rootName = rootMatch.group(1)!.toLowerCase();
    kind = switch (rootName) {
      'movie' => NfoKind.movie,
      'tvshow' => NfoKind.tvshow,
      _ => NfoKind.episode,
    };
    rootStart = rootMatch.start;
  } else {
    // Unknown root: still collect its children (tolerant, foreign dialects)
    // — or bail out on a document with no elements at all (plain-text URL
    // .nfo files, HTML error pages).
    final anyElement =
        RegExp(r'<\s*([A-Za-z][A-Za-z0-9:._-]*)(?=[\s/>])').firstMatch(text);
    if (anyElement == null) {
      return const NfoDocument();
    }
    rootName = anyElement.group(1)!.toLowerCase();
    kind = NfoKind.unknown;
    rootStart = anyElement.start;
  }

  final root = _elementAt(text, rootStart, rootName);
  if (root == null) {
    return NfoDocument(kind: kind);
  }

  // Direct children of the root, name -> values in document order.
  final children = <String, List<String>>{};
  _scanChildren(root.inner, children);

  return NfoDocument(
    kind: kind,
    title: _first(children, 'title'),
    plot: _first(children, 'plot'),
    outline: _first(children, 'outline'),
    tagline: _first(children, 'tagline'),
    year: _firstInt(children, 'year'),
    rating: _firstDouble(children, 'rating'),
    genres: _all(children, 'genre'),
    premiered: _first(children, 'premiered'),
    aired: _first(children, 'aired'),
    season: _firstInt(children, 'season'),
    episode: _firstInt(children, 'episode'),
    thumbs: _all(children, 'thumb'),
    uniqueId: _first(children, 'uniqueid'),
    trailer: _first(children, 'trailer'),
    studio: _first(children, 'studio'),
  );
}

// Removes <!-- … --> spans (unterminated comments eat the rest of the file —
// the fields after it are "skipped", the crash contract never engages).
String _stripComments(String text) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final start = text.indexOf('<!--', index);
    if (start < 0) {
      buffer.write(text.substring(index));
      break;
    }
    buffer.write(text.substring(index, start));
    var end = text.indexOf('-->', start + 4);
    end = end < 0 ? text.length : end + 3;
    index = end;
  }
  return buffer.toString();
}

// The inner content of the element whose '<' sits at |start|, plus the
// position just after its close tag. A self-closing element yields ('',
// afterOpen). A truncated document (close tag never arrives) yields the rest
// of the text — completed fields still parse, the contract is degradation.
class _ElementSlice {
  const _ElementSlice(this.inner, this.end);
  final String inner;
  final int end;
}

_ElementSlice? _elementAt(String text, int start, String name) {
  final openEnd = _tagEnd(text, start);
  if (openEnd == null) {
    return null; // truncated open tag: no usable element
  }
  if (_isSelfClosing(text, start, openEnd)) {
    return _ElementSlice('', openEnd);
  }
  final contentStart = openEnd + 1;

  // Depth count of same-name tags (the element may nest — <fileinfo> nests
  // streams, and a stacked <episodedetails> follows the first one; the depth
  // count below only tracks OUR name).
  final openPattern = RegExp('<$name(?=[\\s/>])', caseSensitive: false);
  final closePattern = RegExp('</$name\\s*>', caseSensitive: false);
  var depth = 1;
  var position = contentStart;
  while (position < text.length) {
    final close = closePattern.firstMatch(text.substring(position));
    if (close == null) {
      // Truncated document: everything left is the element's content.
      return _ElementSlice(text.substring(contentStart), text.length);
    }
    final closeStart = position + close.start;
    final nextOpen = openPattern.firstMatch(text.substring(position));
    final openStart =
        nextOpen == null ? -1 : position + nextOpen.start;
    if (openStart >= 0 && openStart < closeStart) {
      depth++;
      position = position + nextOpen!.end;
      continue;
    }
    depth--;
    if (depth == 0) {
      return _ElementSlice(
          text.substring(contentStart, closeStart), close.end + position);
    }
    position = position + close.end;
  }
  return _ElementSlice(text.substring(contentStart), text.length);
}

bool _isSelfClosing(String text, int start, int tagEnd) {
  for (var i = tagEnd - 1; i > start; i--) {
    final ch = text[i];
    if (ch == '/') {
      return true;
    }
    if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') {
      return false;
    }
  }
  return false;
}

// Position just after the '>' closing the tag that opens at |start| ('<'
// included), honouring quoted attributes (> inside quotes is data). Null
// when the tag never closes.
int? _tagEnd(String text, int start) {
  String? quote;
  for (var i = start + 1; i < text.length; i++) {
    final ch = text[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == '>') {
      return i;
    }
  }
  return null;
}

// Scans one element's inner content for its DIRECT children and collects
// name -> text values (document order). Prologue noise (<?…?>, <!…>, stray
// closes, stray '<') is skipped, never fatal.
void _scanChildren(String inner, Map<String, List<String>> out) {
  // No '^' anchor: matchAsPrefix already pins the match to |start|, and '^'
  // would additionally demand start == 0 (skipping every element that is
  // not the very first character of the content).
  final namePattern = RegExp(r'<([A-Za-z][A-Za-z0-9:._-]*)(?=[\s/>])');
  var index = 0;
  while (index < inner.length) {
    final lt = inner.indexOf('<', index);
    if (lt < 0) {
      break;
    }
    if (inner.startsWith('<!--', lt)) {
      var end = inner.indexOf('-->', lt + 4);
      index = end < 0 ? inner.length : end + 3;
      continue;
    }
    if (inner.startsWith('<![CDATA[', lt)) {
      var end = inner.indexOf(']]>', lt + 9);
      index = end < 0 ? inner.length : end + 3;
      continue;
    }
    if (inner.startsWith('<?', lt) || inner.startsWith('<!', lt)) {
      index = _skipPast(inner, lt, '>');
      continue;
    }
    if (inner.startsWith('</', lt)) {
      index = _skipPast(inner, lt, '>');
      continue;
    }
    final nameMatch = namePattern.matchAsPrefix(inner, lt);
    if (nameMatch == null) {
      index = lt + 1; // stray '<' in text: tolerate, keep scanning
      continue;
    }
    final name = nameMatch.group(1)!.toLowerCase();
    final tagEnd = _tagEnd(inner, lt);
    if (tagEnd == null) {
      index = inner.length; // truncated open tag: nothing more to scan
      continue;
    }
    if (_isSelfClosing(inner, lt, tagEnd)) {
      out.putIfAbsent(name, () => <String>[]).add('');
      index = tagEnd + 1;
      continue;
    }
    final element = _elementAt(inner, lt, name);
    if (element == null) {
      index = inner.length;
      continue;
    }
    out.putIfAbsent(name, () => <String>[]).add(_flattenText(element.inner));
    index = element.end;
  }
}

int _skipPast(String text, int from, String token) {
  final end = text.indexOf(token, from);
  return end < 0 ? text.length : end + token.length;
}

// Element text: splice CDATA sections as raw content, drop any nested
// comment, then entity-decode. Structure extraction already happened, so
// decoding cannot fabricate new tags.
String _flattenText(String inner) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < inner.length) {
    final cdata = inner.indexOf('<![CDATA[', index);
    if (cdata < 0) {
      buffer.write(inner.substring(index));
      break;
    }
    buffer.write(inner.substring(index, cdata));
    final end = inner.indexOf(']]>', cdata + 9);
    if (end < 0) {
      buffer.write(inner.substring(cdata + 9));
      index = inner.length;
      break;
    }
    buffer.write(inner.substring(cdata + 9, end));
    index = end + 3;
  }
  return _decodeEntities(buffer.toString().trim());
}

String _decodeEntities(String text) {
  if (!text.contains('&')) {
    return text;
  }
  return text.replaceAllMapped(
      RegExp(r'&(amp|lt|gt|quot|apos|#x[0-9A-Fa-f]+|#\d+);'), (match) {
    final token = match.group(1)!;
    return switch (token) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      _ when token.startsWith('#x') || token.startsWith('#X') =>
        _charFromRadix(token.substring(2), 16) ?? match.group(0)!,
      _ when token.startsWith('#') =>
        _charFromRadix(token.substring(1), 10) ?? match.group(0)!,
      _ => match.group(0)!, // unknown entity stays literal (tolerant)
    };
  });
}

String? _charFromRadix(String digits, int radix) {
  final code = int.tryParse(digits, radix: radix);
  return code == null ? null : String.fromCharCode(code);
}

String _first(Map<String, List<String>> children, String name) {
  for (final value in children[name] ?? const <String>[]) {
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

List<String> _all(Map<String, List<String>> children, String name) => [
      for (final value in children[name] ?? const <String>[])
        if (value.isNotEmpty) value,
    ];

int? _firstInt(Map<String, List<String>> children, String name) {
  final text = _first(children, name);
  if (text.isEmpty) {
    return null;
  }
  return int.tryParse(text) ??
      int.tryParse(RegExp(r'-?\d+').firstMatch(text)?.group(0) ?? '');
}

double? _firstDouble(Map<String, List<String>> children, String name) {
  final text = _first(children, name);
  if (text.isEmpty) {
    return null;
  }
  return double.tryParse(text) ??
      double.tryParse(
          RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text)?.group(0) ?? '');
}
