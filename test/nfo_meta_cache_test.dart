import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/nfo_meta_cache.dart';
import 'package:emoplay/media/nfo_parser.dart';

/// M4-T6 guard tests (user addition 2026-11-12): the NfoMetaCache —
/// media_nfo.json persistence, the one-listing scan (NFO + poster + show
/// title discovery), the mtime-pair invalidation, and the performance
/// contract (infoFor never does IO; a fresh requestInfo hit re-parses
/// nothing).
///
/// Real temporary directories with real (tiny) NFO/poster files; no network
/// exists on this path by construction — `<thumb>` URLs are recorded
/// verbatim, never fetched.
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-nfo-');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String cachePath() => '${tempDir.path}/media_nfo.json';

  /// Creates a video dir with a movie NFO + poster + fanart.
  Directory seedMovie({String nfoName = 'movie.nfo', String? nfoBody}) {
    final dir = Directory('${tempDir.path}/Movies')..createSync();
    File('${dir.path}/film.mkv').writeAsStringSync('video');
    File('${dir.path}/$nfoName').writeAsStringSync(nfoBody ??
        '<movie><title>Cached Movie</title><year>2020</year>'
        '<plot>A cached plot.</plot>'
        '<thumb>https://example.com/poster.jpg</thumb></movie>');
    File('${dir.path}/poster.jpg').writeAsStringSync('poster');
    File('${dir.path}/fanart.jpg').writeAsStringSync('fanart');
    return dir;
  }

  test('scanDiscoversNfoPosterAndThumbs', () async {
    final dir = seedMovie();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final info = await cache.requestInfo('${dir.path}/film.mkv');
    expect(info, isNotNull);
    expect(info!.hasNfo, isTrue);
    expect(info.nfo.kind, NfoKind.movie);
    expect(info.nfo.title, 'Cached Movie');
    expect(info.nfo.year, 2020);
    // Local-first: the same-directory poster wins over the recorded URL.
    expect(info.poster, '${dir.path}/poster.jpg');
    expect(info.nfo.thumbs, ['https://example.com/poster.jpg']);
    // The record is served from the pure map lookup afterwards.
    expect(cache.infoFor('${dir.path}/film.mkv'), same(info));
  });

  test('videoNamedNfoBeatsMovieNfo', () async {
    final dir = seedMovie(
      nfoName: 'movie.nfo',
      nfoBody: '<movie><title>Folder NFO</title></movie>',
    );
    File('${dir.path}/film.nfo')
        .writeAsStringSync('<movie><title>Sidecar NFO</title></movie>');
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final info = await cache.requestInfo('${dir.path}/film.mkv');
    expect(info!.nfo.title, 'Sidecar NFO',
        reason: 'Kodi precedence: <video>.nfo before movie.nfo');
  });

  test('showTitleComesFromTvshowNfo', () async {
    final dir = seedMovie(nfoName: 'episode.nfo');
    // Overwrite the video with an episode NFO name so the sidecar lookup
    // picks it; tvshow.nfo carries the show title.
    File('${dir.path}/episode.nfo').writeAsStringSync(
        '<episodedetails><title>Ep Title</title><season>1</season>'
        '<episode>2</episode></episodedetails>');
    File('${dir.path}/tvshow.nfo')
        .writeAsStringSync('<tvshow><title>Cached Show</title></tvshow>');
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final info = await cache.requestInfo('${dir.path}/episode.nfo');
    expect(info, isNotNull,
        reason: 'any regular file is requestable; the cache is '
            'type-agnostic (the model filters videos)');
    expect(info!.nfo.kind, NfoKind.episode);
    expect(info.showTitle, 'Cached Show');
    expect(cache.infoFor('${dir.path}/episode.nfo')!.showTitle, 'Cached Show');
  });

  test('posterOnlyVideoStillRecordsAFullEntry', () async {
    final dir = seedMovie(nfoName: 'unrelated.nfo');
    File('${dir.path}/unrelated.nfo').deleteSync();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final info = await cache.requestInfo('${dir.path}/film.mkv');
    expect(info!.hasNfo, isFalse);
    expect(info.nfo.isEmpty, isTrue);
    expect(info.poster, '${dir.path}/poster.jpg',
        reason: 'artwork discovery works without any NFO');
  });

  test('mtimePairInvalidationRescansTheDirectory', () async {
    final dir = seedMovie();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final first = await cache.requestInfo('${dir.path}/film.mkv');
    expect(first!.nfo.title, 'Cached Movie');

    // The NFO is replaced (its edit touches the DIRECTORY); the video is
    // rewritten too (touching the other half of the invalidation pair).
    // The delay guarantees the new mtimes land in a LATER millisecond than
    // the first scan's stats (mtime truncation would otherwise flake).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    File('${dir.path}/movie.nfo')
        .writeAsStringSync('<movie><title>Updated Movie</title></movie>');
    File('${dir.path}/film.mkv').writeAsStringSync('video v2');
    final second = await cache.requestInfo('${dir.path}/film.mkv');
    expect(second!.nfo.title, 'Updated Movie',
        reason: 'a changed mtime pair is a fresh state — rescan');
  });

  test('corruptCacheFileDegradesToEmptyAndRoundTrips', () async {
    final dir = seedMovie();
    File(cachePath()).writeAsStringSync('{not json at all');
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);
    expect(cache.infoFor('${dir.path}/film.mkv'), isNull);

    final info = await cache.requestInfo('${dir.path}/film.mkv');
    expect(info, isNotNull);

    // A fresh cache instance on the same file loads the persisted record.
    final reloaded = NfoMetaCache(cachePath());
    addTearDown(reloaded.dispose);
    final loadedInfo = reloaded.infoFor('${dir.path}/film.mkv');
    expect(loadedInfo, isNotNull);
    expect(loadedInfo!.nfo.title, info!.nfo.title);
    expect(loadedInfo, equals(info),
        reason: 'JSON round trip preserves the record field-for-field');
  });

  test('hitPathDoesNoReparseAndMissingVideoCompletesNull', () async {
    final dir = seedMovie();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final first = await cache.requestInfo('${dir.path}/film.mkv');
    // No filesystem change: the same record INSTANCE comes back — proof no
    // re-parse ran (the performance guard, media_meta_cache precedent).
    final second = await cache.requestInfo('${dir.path}/film.mkv');
    expect(second, same(first));

    expect(await cache.requestInfo('${tempDir.path}/missing.mkv'), isNull,
        reason: 'a stale library entry completes null without a scan');
  });

  test('concurrentRequestsJoinOneScan', () async {
    final dir = seedMovie();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final results = await Future.wait([
      cache.requestInfo('${dir.path}/film.mkv'),
      cache.requestInfo('${dir.path}/film.mkv'),
    ]);
    expect(results[0], isNotNull);
    expect(identical(results[0], results[1]), isTrue,
        reason: 'the second request joined the in-flight scan, so both '
            'settled with the one record');
  });

  test('thumbUrlsAreRecordedNeverDownloaded', () async {
    final dir = Directory('${tempDir.path}/OnlyNfo')..createSync();
    File('${dir.path}/a.mkv').writeAsStringSync('video');
    File('${dir.path}/a.nfo').writeAsStringSync(
        '<movie><title>URLs</title>'
        '<thumb>https://images.example.com/x.jpg</thumb>'
        '<thumb spoof="https://ref.example">https://images.example.com/y.jpg</thumb>'
        '</movie>');
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);

    final info = await cache.requestInfo('${dir.path}/a.mkv');
    expect(info!.nfo.thumbs,
        ['https://images.example.com/x.jpg', 'https://images.example.com/y.jpg']);
    expect(info.poster, '',
        reason: 'no local art exists and none is fetched — the URLs are '
            'data, not downloads');
  });

  test('documentShapeIsTheVersionedEntriesMap', () async {
    final dir = seedMovie();
    final cache = NfoMetaCache(cachePath());
    addTearDown(cache.dispose);
    await cache.requestInfo('${dir.path}/film.mkv');

    final document =
        jsonDecode(File(cachePath()).readAsStringSync()) as Map;
    expect(document['version'], 1);
    final entries = document['entries'] as Map;
    final record = entries['${dir.path}/film.mkv'] as Map;
    expect(record['hasNfo'], isTrue);
    expect((record['nfo'] as Map)['title'], 'Cached Movie');
    expect(record['poster'], '${dir.path}/poster.jpg');
    expect(record.keys, containsAll(['videoMtime', 'dirMtime']));
  });
}
