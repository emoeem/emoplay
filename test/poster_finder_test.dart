import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/poster_finder.dart';

/// M4-T6 guard tests (user addition 2026-11-12): local poster discovery —
/// the poster.jpg / folder.jpg / fanart.jpg / <文件名>-poster.jpg same-
/// directory conventions, most specific first.
///
/// The candidate math is pure; [findExistingPoster] is exercised against a
/// real temporary directory (the house QTemporaryDir pattern).
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-poster-');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('candidatesListTheFourConventionsMostSpecificFirst', () {
    expect(posterCandidatesFor('/media/Movies/Blade Runner.mkv'), [
      '/media/Movies/Blade Runner-poster.jpg',
      '/media/Movies/poster.jpg',
      '/media/Movies/folder.jpg',
      '/media/Movies/fanart.jpg',
    ]);
  });

  test('sidecarUsesCompleteBaseName', () {
    // Only the last extension is stripped — matching the scanner's title
    // convention (QFileInfo::completeBaseName).
    expect(posterCandidatesFor('/media/tv/a.b.mkv').first,
        '/media/tv/a.b-poster.jpg');
    expect(posterCandidatesFor('/media/tv/.hidden.mkv').first,
        '/media/tv/.hidden-poster.jpg');
  });

  test('existingPosterPicksTheMostSpecificCandidate', () {
    final dir = tempDir.path;
    File('$dir/poster.jpg').writeAsStringSync('poster');
    File('$dir/ep1-poster.jpg').writeAsStringSync('sidecar');
    expect(findExistingPoster('$dir/ep1.mkv'), '$dir/ep1-poster.jpg',
        reason: 'the video-named sidecar beats the folder posters');
  });

  test('existingPosterFallsBackThroughTheChain', () {
    final dir = tempDir.path;
    File('$dir/fanart.jpg').writeAsStringSync('fanart');
    expect(findExistingPoster('$dir/ep1.mkv'), '$dir/fanart.jpg',
        reason: 'fanart is the last resort of the fixed list');
    // A video whose directory holds none of the conventions.
    final bare = Directory('${tempDir.path}/bare')..createSync();
    expect(findExistingPoster('${bare.path}/none.mkv'), '',
        reason: 'nothing on disk: no poster');
  });

  test('directoryNamedLikeAPosterIsSkipped', () {
    final dir = tempDir.path;
    Directory('$dir/poster.jpg').createSync();
    File('$dir/folder.jpg').writeAsStringSync('folder');
    expect(findExistingPoster('$dir/ep1.mkv'), '$dir/folder.jpg',
        reason: 'a poster is a file, not a directory');
  });

  test('firstExistingPosterNameMatchesListingNamesPurely', () {
    final candidates =
        posterCandidateNamesFor('/media/tv/S01E02.mkv');
    expect(candidates.sidecar, 'S01E02-poster.jpg');
    expect(candidates.fixed, ['poster.jpg', 'folder.jpg', 'fanart.jpg']);

    // The listing-based matcher (the NFO cache scan path): exact names, a
    // directory-named poster skipped by the injected type resolver.
    final listing = <String>{'poster.jpg', 'folder.jpg'};
    expect(
        firstExistingPosterName(
          candidates,
          listing,
          (name) => name != 'poster.jpg', // poster.jpg is a directory here
        ),
        'folder.jpg');
    expect(
        firstExistingPosterName(
          candidates,
          <String>{'fanart.jpg'},
          (name) => true,
        ),
        'fanart.jpg');
    expect(
        firstExistingPosterName(candidates, <String>{'other.txt'}, (n) => true),
        '');
  });
}
