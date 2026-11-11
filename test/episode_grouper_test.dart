import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/episode_grouper.dart';
import 'package:emoplay/media/library_store.dart';

/// M4-T6 guard tests (user addition 2026-11-12): the file-name SxxEyy
/// season/episode parser (纯逻辑) and the show → season → episode
/// three-level grouping service.
void main() {
  // ---- SxxEyy parsing (≥6 required by the round's contract) -------------

  test('parsesCanonicalSxxEyyCaseInsensitively', () {
    expect(parseEpisodeMarker('S01E02.mkv'),
        EpisodeFacts(show: '', season: 1, episode: 2));
    expect(parseEpisodeMarker('s01e02.mkv'),
        EpisodeFacts(show: '', season: 1, episode: 2));
    expect(parseEpisodeMarker('Show.Name.S12E034.720p.mkv'),
        EpisodeFacts(show: 'Show Name', season: 12, episode: 34));
  });

  test('paddingIsOptional', () {
    expect(parseEpisodeMarker('S1E1.mkv')!.season, 1);
    expect(parseEpisodeMarker('S1E1.mkv')!.episode, 1);
    expect(parseEpisodeMarker('s3e12.mkv')!.season, 3);
    expect(parseEpisodeMarker('s3e12.mkv')!.episode, 12);
  });

  test('showNameIsCleanedFromSeparators', () {
    expect(parseEpisodeMarker('Breaking.Bad.S01E05.mkv')!.show,
        'Breaking Bad');
    expect(parseEpisodeMarker('show_name_here_S02E10.mkv')!.show,
        'show name here');
    expect(
        parseEpisodeMarker('Show - S01E02.mkv')!.show, 'Show',
        reason: 'trailing separators are trimmed');
    expect(parseEpisodeMarker('[Group] Show.S01E02.mkv')!.show,
        'Group] Show',
        reason: 'the cleaner trims boundary punctuation, not mid-name '
            'brackets — release-group prefixes stay readable');
  });

  test('parsesTheAlternativeDxddConvention', () {
    expect(parseEpisodeMarker('Series.1x05.mkv'),
        EpisodeFacts(show: 'Series', season: 1, episode: 5));
    expect(parseEpisodeMarker('21x02.mkv'),
        EpisodeFacts(show: '', season: 21, episode: 2));
  });

  test('multiEpisodeNamesTakeTheFirstEpisode', () {
    expect(parseEpisodeMarker('Show.S01E02E03.mkv')!.episode, 2);
    expect(parseEpisodeMarker('Show.S01E02-E03.mkv')!.episode, 2);
  });

  test('seasonZeroIsSpecials', () {
    final facts = parseEpisodeMarker('Show.S00E01.Webinar.mkv')!;
    expect(facts.season, 0);
    expect(facts.episode, 1);
  });

  test('nonEpisodeNamesDoNotMatch', () {
    // No marker at all.
    expect(parseEpisodeMarker('Blade.Runner.2049.1080p.mkv'), isNull);
    // Marker glued into a word (no boundary before the S / the digits).
    expect(parseEpisodeMarker('M4S01E02.mkv'), isNull);
    expect(parseEpisodeMarker('CAS01E02.mkv'), isNull);
    // Overlong digit runs are rejected rather than mis-parsed.
    expect(parseEpisodeMarker('S012E05.mkv'), isNull);
    expect(parseEpisodeMarker('S01E1234.mkv'), isNull);
  });

  // ---- grouping service (≥4 required by the round's contract) -----------

  LibraryEntry video(String path, {String? title}) => LibraryEntry(
        path: path,
        title: title ?? path.split('/').last,
        type: 'video',
      );

  test('groupsIntoShowSeasonEpisodeHierarchy', () {
    final partition = partitionEpisodes([
      video('/tv/Dexter/S01/Show.S01E02.mkv'),
      video('/tv/Dexter/S01/Show.S01E01.mkv'),
      video('/tv/Dexter/S02/Show.S02E01.mkv'),
      video('/tv/Dexter/S02/Show.S02E03.mkv'),
    ]);

    expect(partition.ungrouped, isEmpty);
    expect(partition.shows, hasLength(1));
    final show = partition.shows.single;
    expect(show.show, 'Show');
    // Seasons ascending.
    expect(show.seasons.map((s) => s.season).toList(), [1, 2]);
    // Episodes ascending by number (input order was reversed for S01E01/E02).
    expect(show.seasons[0].episodes.map((e) => e.path).toList(),
        ['/tv/Dexter/S01/Show.S01E01.mkv', '/tv/Dexter/S01/Show.S01E02.mkv']);
    expect(show.seasons[1].episodes.map((e) => e.path).toList(),
        ['/tv/Dexter/S02/Show.S02E01.mkv', '/tv/Dexter/S02/Show.S02E03.mkv']);
  });

  test('showKeysAreCaseInsensitiveAndSpecialsSortFirst', () {
    final partition = partitionEpisodes([
      video('/tv/Show/S01/Show.S01E01.mkv'),
      video('/tv/Show/S00/SHOW.S00E01.mkv'),
      video('/tv/Show/S01/show.s01e02.mkv'),
    ]);

    final show = partition.shows.single;
    expect(show.show, 'Show', reason: 'the first member gives the display '
        'name; "SHOW.S00E01" and "show.s01e02" join the same bucket');
    expect(show.seasons.map((s) => s.season).toList(), [0, 1],
        reason: 'season 0 (特别篇) sorts before season 1');
  });

  test('ungroupedEntriesComeBackUntouchedInOrder', () {
    final partition = partitionEpisodes([
      video('/media/Movies/movie.mkv'),
      video('/tv/Show.S01E01.mkv'),
      video('/media/song.flac'),
    ]);

    expect(partition.shows, hasLength(1));
    expect(
        partition.ungrouped.map((entry) => entry.path).toList(),
        [
          '/media/Movies/movie.mkv',
          '/media/song.flac',
        ],
        reason: 'entries without a marker (movies, audio) stay ungrouped, '
            'in input order');
  });

  test('episodeTiesBreakByTitleCaseInsensitively', () {
    final partition = partitionEpisodes([
      video('/tv/a/Show.S01E02.mkv', title: 'zzz'),
      video('/tv/b/Show.S01E02.mkv', title: 'aaa'),
      video('/tv/c/Show.S01E02.mkv', title: 'mmm'),
    ]);
    expect(partition.shows.single.seasons.single.episodes
        .map((e) => e.title)
        .toList(), ['aaa', 'mmm', 'zzz']);
  });

  test('emptyInputGivesAnEmptyPartition', () {
    final partition = partitionEpisodes(const []);
    expect(partition.shows, isEmpty);
    expect(partition.ungrouped, isEmpty);
  });

  test('markerFirstNamesFallIntoOneUnnamedShowBucket', () {
    // "S01E02.mkv" style files carry no show name; they still group by
    // season/episode under one unnamed bucket (the page labels it from the
    // directory).
    final partition = partitionEpisodes([
      video('/tv/A/S01E02.mkv'),
      video('/tv/A/S01E01.mkv'),
    ]);
    final show = partition.shows.single;
    expect(show.show, '');
    expect(show.seasons.single.episodes.map((e) => e.path).toList(),
        ['/tv/A/S01E01.mkv', '/tv/A/S01E02.mkv']);
  });
}
