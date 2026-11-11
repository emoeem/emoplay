import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/media/nfo_parser.dart';

/// M4-T6 guard tests (user addition 2026-11-12): the Kodi NFO parser —
/// movie.nfo / tvshow.nfo / 剧集 nfo roots, tolerant of hostile real-world
/// files ("损坏 XML 跳过字段不崩溃").
///
/// Pure logic: everything here runs on string fixtures shaped after the
/// Kodi NFO conventions (kodi.wiki/view/NFO_files), including the hostile
/// cases Kodi users actually hit — scraped-page garbage before the root,
/// BOM, commented-out fields, CDATA plots, truncated downloads, stacked
/// episode blocks.
void main() {
  test('parsesMovieFields', () {
    const nfo = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<movie>
  <title>Blade Runner 2049</title>
  <outline>A young blade runner's discovery leads him to Rick Deckard.</outline>
  <plot>Thirty years after the events of the first film, a new blade
runner, LAPD Officer K, unearths a long-buried secret.</plot>
  <tagline>There is an order to things.</tagline>
  <year>2017</year>
  <rating>8.100000</rating>
  <genre>Sci-Fi</genre>
  <genre>Thriller</genre>
  <studio>Warner Bros.</studio>
  <trailer>https://www.youtube.com/watch?v=gCcx85zbxz4</trailer>
  <uniqueid type="imdb">tt1856101</uniqueid>
  <thumb aspect="poster" preview="https://img/poster.preview.jpg">https://img/poster.jpg</thumb>
  <thumb aspect="fanart">https://img/fanart.jpg</thumb>
</movie>''';

    final doc = parseNfoContent(nfo);
    expect(doc.kind, NfoKind.movie);
    expect(doc.title, 'Blade Runner 2049');
    expect(doc.outline, "A young blade runner's discovery leads him to Rick Deckard.");
    expect(doc.plot, startsWith('Thirty years after'));
    expect(doc.tagline, 'There is an order to things.');
    expect(doc.year, 2017);
    expect(doc.rating, 8.1);
    expect(doc.genres, ['Sci-Fi', 'Thriller']);
    expect(doc.studio, 'Warner Bros.');
    expect(doc.trailer, 'https://www.youtube.com/watch?v=gCcx85zbxz4');
    expect(doc.uniqueId, 'tt1856101');
    // <thumb> values collected verbatim — recorded, never downloaded.
    expect(doc.thumbs,
        ['https://img/poster.jpg', 'https://img/fanart.jpg']);
  });

  test('parsesTvshowAndEpisodeRoots', () {
    const tvshow = '''
<tvshow>
  <title>Breaking Bad</title>
  <plot>A chemistry teacher with cancer cooks meth.</plot>
  <premiered>2008-01-20</premiered>
  <genre>Crime</genre>
  <studio>AMC</studio>
</tvshow>''';
    final show = parseNfoContent(tvshow);
    expect(show.kind, NfoKind.tvshow);
    expect(show.title, 'Breaking Bad');
    expect(show.premiered, '2008-01-20');

    const episode = '''
<episodedetails>
  <title>Cat's in the Bag...</title>
  <plot>Walt and Jesse try to tie up loose ends.</plot>
  <season>1</season>
  <episode>2</episode>
  <aired>2008-01-27</aired>
  <thumb>https://img/ep1x02.jpg</thumb>
</episodedetails>''';
    final ep = parseNfoContent(episode);
    expect(ep.kind, NfoKind.episode);
    expect(ep.season, 1);
    expect(ep.episode, 2);
    expect(ep.aired, '2008-01-27');
    expect(ep.title, "Cat's in the Bag...");
    expect(ep.thumbs, ['https://img/ep1x02.jpg']);
  });

  test('corruptedTruncatedXmlSkipsFieldsWithoutCrashing', () {
    // Truncated mid-plot: the complete elements before the cut survive, the
    // incomplete one degrades — and nothing throws.
    const truncated = '''
<movie>
  <title>Truncated</title>
  <year>1999</year>
  <plot>a plot that never ends because the file was cut''';
    final doc = parseNfoContent(truncated);
    expect(doc.kind, NfoKind.movie);
    expect(doc.title, 'Truncated');
    expect(doc.year, 1999);
    expect(doc.plot, isNotEmpty, reason: 'the rest of the file is the '
        'element content; the salvageable text is kept');

    // Mangled nesting: a stray close tag and a wrong close name.
    const mangled = '<movie><title>X</tilte><plot>ok</plot></mov>';
    final doc2 = parseNfoContent(mangled);
    expect(doc2.title, 'X</tilte><plot>ok</plot></mov>',
        reason: 'tolerant: the title element never closes (</tilte> is not '
            'its close tag), so it runs to end-of-file — the salvageable '
            'text is kept, nothing crashes');
    expect(doc2.kind, NfoKind.movie);
  });

  test('garbageInputNeverThrowsAndYieldsEmptyRecord', () {
    // Kodi's "URL as NFO" legacy, HTML error pages, random bytes-as-text.
    for (final garbage in <String>[
      '',
      '   \n\t  ',
      'https://www.themoviedb.org/movie/335984',
      '<html><body><h1>502 Bad Gateway</h1></body></html>',
      '1http://forum.xbmc.org/showthread.php?t=666',
      '<<<>>>',
    ]) {
      final doc = parseNfoContent(garbage);
      expect(doc.kind, NfoKind.unknown, reason: 'input: "$garbage"');
      expect(doc.isEmpty, isTrue, reason: 'input: "$garbage"');
    }
  });

  test('leadingJunkBomCommentsAndDeclarationAreStripped', () {
    const nfo = '''
\uFEFF1http://thetvdb.com/?id=79501
<!-- scraped from thetvdb, keep the note -->
<?xml version="1.0" encoding="utf-8"?>
<tvshow>
  <!-- <title>Old Title</title> commented fields are skipped -->
  <title>Firefly</title>
  <plot><![CDATA[A crew of smugglers & <runners> fly the Serenity.]]></plot>
</tvshow>''';
    final doc = parseNfoContent(nfo);
    expect(doc.kind, NfoKind.tvshow);
    expect(doc.title, 'Firefly',
        reason: 'the commented-out field is skipped, the real one wins');
    expect(doc.plot, 'A crew of smugglers & <runners> fly the Serenity.',
        reason: 'CDATA content is raw text: & and < are NOT decoded there');
  });

  test('entitiesAreDecodedInElementText', () {
    const nfo = '''
<movie>
  <title>One &amp; Two &lt;Three&gt; &#65;&#x42;</title>
  <plot>A &quot;quote&quot; and an &apos;apostrophe&apos; and &unknown; stays.</plot>
</movie>''';
    final doc = parseNfoContent(nfo);
    expect(doc.title, 'One & Two <Three> AB');
    expect(doc.plot, 'A "quote" and an \'apostrophe\' and &unknown; stays.');
  });

  test('unknownRootElementStillCollectsChildren', () {
    // A foreign dialect keeps its usable fields (kind degrades to unknown).
    const nfo = '''
<musicvideo>
  <title>Neon Rivers</title>
  <studio>Studio X</studio>
</musicvideo>''';
    final doc = parseNfoContent(nfo);
    expect(doc.kind, NfoKind.unknown);
    expect(doc.title, 'Neon Rivers');
    expect(doc.studio, 'Studio X');
  });

  test('stackedEpisodeBlocksTakeTheFirst', () {
    const nfo = '''
<episodedetails>
  <title>First Episode</title>
  <season>2</season>
  <episode>5</episode>
</episodedetails>
<episodedetails>
  <title>Second Episode</title>
  <season>2</season>
  <episode>6</episode>
</episodedetails>''';
    final doc = parseNfoContent(nfo);
    expect(doc.title, 'First Episode');
    expect(doc.episode, 5);
  });

  test('nestedElementsAndAttributesAreTolerated', () {
    // fileinfo nests streams (real Kodi export shape); the rating carries
    // attributes and the season value has padding whitespace.
    const nfo = '''
<movie>
  <title>Nested</title>
  <fileinfo><stream details="v"><codec>h264</codec></stream></fileinfo>
  <rating name="imdb" max="10">7.50</rating>
  <season>
    3
  </season>
  <uniqueid type="tmdb" default="true">123</uniqueid>
</movie>''';
    final doc = parseNfoContent(nfo);
    expect(doc.title, 'Nested');
    expect(doc.rating, 7.5);
    expect(doc.season, 3);
    expect(doc.uniqueId, '123');
  });

  test('nfoCandidatesFollowKodiPrecedence', () {
    expect(
        nfoCandidatesFor('/media/Movies/Blade Runner 2049.mkv'),
        [
          '/media/Movies/Blade Runner 2049.nfo',
          '/media/Movies/movie.nfo',
        ]);
    // completeBaseName semantics: only the LAST extension is stripped.
    expect(
        nfoCandidatesFor('/media/tv/a.b.mkv').first, '/media/tv/a.b.nfo');
    expect(nfoCandidatesFor('/media/tv/.hidden.mkv').first,
        '/media/tv/.hidden.nfo');
  });
}
