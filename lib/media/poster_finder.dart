import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

// Local poster discovery (user-added roadmap item M4-T6, 2026-11-12: "本地
// 海报发现：与视频同目录的 poster.jpg/folder.jpg/fanart.jpg/<文件名>-
// poster.jpg 约定；NFO 内 <thumb> URL 仅记录不下载（本地优先）").
//
// Pure path arithmetic here; the one filesystem helper ([findExistingPoster])
// only stats candidate paths. The <thumb> URLs of a parsed NFO are recorded
// by lib/media/nfo_parser.dart and never fetched — no http import exists on
// this path by construction.
//
// Priority is most-specific first: the video's own sidecar poster
// (<completeBaseName>-poster.jpg, e.g. "S01E02-poster.jpg" next to
// "S01E02.mkv") beats the folder-level posters; fanart.jpg (a backdrop by
// Kodi semantics) is the last resort of the fixed list — the ask enumerates
// exactly these four names, so no other conventions (png variants, parent
// directories, <name>-fanart.jpg) are probed.

/// The poster file conventions for |videoPath|, most specific first —
/// absolute candidate paths in the video's own directory.
List<String> posterCandidatesFor(String videoPath) {
  final dir = p.dirname(videoPath);
  return <String>[
    '$dir/${p.basenameWithoutExtension(videoPath)}-poster.jpg',
    '$dir/poster.jpg',
    '$dir/folder.jpg',
    '$dir/fanart.jpg',
  ];
}

/// First existing candidate of [posterCandidatesFor], or '' when none of
/// them is a readable regular file. Directories named like a poster are
/// skipped (a poster is a file).
String findExistingPoster(String videoPath) {
  for (final candidate in posterCandidatesFor(videoPath)) {
    if (_isRegularFile(candidate)) {
      return candidate;
    }
  }
  return '';
}

bool _isRegularFile(String path) {
  try {
    return FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.file;
  } catch (_) {
    return false;
  }
}

/// Poster candidate BASE NAMES for one directory — what a directory listing
/// (one listSync) is matched against by the NFO meta cache
/// (lib/media/nfo_meta_cache.dart) so a scan costs one listing, not a stat
/// per candidate. `completeBaseName` drives the sidecar name the same way
/// [posterCandidatesFor] derives it.
@immutable
class PosterCandidateNames {
  const PosterCandidateNames({required this.sidecar, required this.fixed});

  /// The sidecar name: `<videoBaseName>-poster.jpg`
  /// (`basenameWithoutExtension` + suffix).
  final String sidecar;

  /// The fixed folder-level names, priority order.
  final List<String> fixed;
}

PosterCandidateNames posterCandidateNamesFor(String videoPath) {
  return PosterCandidateNames(
    sidecar: '${p.basenameWithoutExtension(videoPath)}-poster.jpg',
    fixed: const <String>['poster.jpg', 'folder.jpg', 'fanart.jpg'],
  );
}

/// First candidate name present in |directoryFileNames| (a listSync result —
/// exact, case-sensitive names), or '' when none. |typeOf| resolves a name
/// to whether it is a regular file; directories named like a poster are
/// skipped. Pure apart from the injected resolver — the cache's scan calls
/// it with FileSystemEntity.typeSync.
String firstExistingPosterName(
  PosterCandidateNames candidates,
  Set<String> directoryFileNames,
  bool Function(String name) typeOf,
) {
  final ordered = <String>[candidates.sidecar, ...candidates.fixed];
  for (final name in ordered) {
    if (directoryFileNames.contains(name) && typeOf(name)) {
      return name;
    }
  }
  return '';
}
