import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:emoplay/media/online/metadata_provider.dart';
import 'package:emoplay/media/online/tmdb_provider.dart';

/// M4-T7 adapter tests: the TmdbProvider request shaping (injected api
/// key / query / language / movie-year narrowing) and its degrade contract
/// against documented TMDB response shapes — parsed hits, skipped person
/// rows, definitive misses (null), and every transport/protocol failure
/// thrown as one typed exception (the same shapes the R11 live probe
/// saw: HTTP 401 {"status_code":7,...} for an invalid key).
///
/// Everything runs on package:http MockClient — no test touches the
/// network.
void main() {
  /// Builds the provider over a capturing mock and returns the captured
  /// request alongside it.
  ({TmdbProvider provider, List<http.Request> requests}) build({
    required Future<http.Response> Function(http.Request request) handler,
    String apiKey = 'test-key',
    Duration timeout = const Duration(seconds: 2),
  }) {
    final requests = <http.Request>[];
    final provider = TmdbProvider(
      client: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
      apiKey: apiKey,
      requestTimeout: timeout,
    );
    return (provider: provider, requests: requests);
  }

  http.Response okJson(Object? body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json;charset=utf-8'},
      );

  const movieHit = <String, Object?>{
    'page': 1,
    'results': [
      <String, Object?>{
        'adult': false,
        'id': 27205,
        'title': '盗梦空间',
        'original_title': 'Inception',
        'overview': '一名造梦师潜入他人梦境窃取机密。',
        'release_date': '2010-07-16',
        'poster_path': '/qJ2tW6WMUDux9XrTGlnmkinvKC.jpg',
        'media_type': 'movie',
        'vote_average': 8.4,
        'genre_ids': [28, 878],
      },
    ],
  };

  const tvHit = <String, Object?>{
    'page': 1,
    'results': [
      <String, Object?>{
        'id': 1396,
        'name': '绝命毒师',
        'original_name': 'Breaking Bad',
        'overview': '一名化学老师转行制毒。',
        'first_air_date': '2008-01-20',
        'poster_path': '/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
        'media_type': 'tv',
        'vote_average': 8.9,
        'genre_ids': [18],
      },
    ],
  };

  test('requestCarriesKeyQueryLanguageAndMovieYear', () async {
    final (:provider, :requests) = build(
      handler: (request) async => okJson(const {
        'results': <Object?>[],
      }),
    );

    await provider.search(const MetadataQuery(text: '盗梦空间', year: 2010));
    expect(requests, hasLength(1));
    final params = requests.single.url.queryParameters;
    expect(params['api_key'], 'test-key');
    expect(params['query'], '盗梦空间');
    expect(params['language'], 'zh-CN');
    expect(params['page'], '1');
    expect(params['year'], '2010');
    expect(requests.single.url.host, 'api.themoviedb.org');
    expect(requests.single.url.path, '/3/search/multi');

    // Episode hints drop the movie-year narrowing (the year belongs to a
    // TV first-air, not the file's season marker).
    await provider
        .search(const MetadataQuery(text: '绝命毒师', year: 2008, episodeHint: true));
    expect(requests.last.url.queryParameters.containsKey('year'), isFalse);
  });

  test('parsesMovieHit', () async {
    final (:provider, :requests) =
        build(handler: (request) async => okJson(movieHit));

    final hit = await provider.search(const MetadataQuery(text: '盗梦空间'));
    expect(hit, isNotNull);
    expect(hit!.provider, 'tmdb');
    expect(hit.providerId, 27205);
    expect(hit.mediaType, 'movie');
    expect(hit.title, '盗梦空间');
    expect(hit.originalTitle, 'Inception');
    expect(hit.year, 2010);
    expect(hit.rating, 8.4);
    expect(hit.plot, contains('造梦师'));
    // The poster URL is absolute and derived from the poster_path.
    expect(hit.posterUrl,
        'https://image.tmdb.org/t/p/w500/qJ2tW6WMUDux9XrTGlnmkinvKC.jpg');
    expect(hit.genres, isEmpty,
        reason: 'multi search carries genre_ids only — name mapping is '
            'the pending-with-real-key step');
    expect(requests, hasLength(1));
  });

  test('parsesTvHit', () async {
    final (:provider, :requests) =
        build(handler: (request) async => okJson(tvHit));

    final hit = await provider.search(const MetadataQuery(text: '绝命毒师'));
    expect(hit!.mediaType, 'tv');
    expect(hit.title, '绝命毒师');
    expect(hit.originalTitle, 'Breaking Bad');
    expect(hit.year, 2008);
    expect(hit.rating, 8.9);
    expect(requests, hasLength(1));
  });

  test('skipsPersonRowsAndTitlelessRows', () async {
    final (:provider, :requests) = build(
      handler: (request) async => okJson(const {
        'results': [
          {
            'id': 240,
            'media_type': 'person',
            'name': 'Leonardo DiCaprio',
          },
          {'id': 999, 'media_type': 'movie'}, // no title -> unusable
          {
            'id': 27205,
            'title': 'Inception',
            'media_type': 'movie',
            'release_date': '2010-07-16',
          },
        ],
      }),
    );

    final hit = await provider.search(const MetadataQuery(text: 'inception'));
    expect(hit!.title, 'Inception');
    expect(requests, hasLength(1));
  });

  test('emptyResultsIsDefinitiveMiss', () async {
    final (:provider, :requests) = build(
      handler: (request) async =>
          okJson(const {'results': <Object?>[], 'total_results': 0}),
    );

    final hit = await provider.search(const MetadataQuery(text: 'zz-no-such'));
    expect(hit, isNull);
    expect(requests, hasLength(1));
  });

  test('invalidKey401ThrowsTyped', () async {
    // The exact shape the R11 reachability probe saw live (2026-11-12):
    // HTTP 401 {"status_code":7,...}.
    final (:provider, :requests) = build(
      handler: (request) async => http.Response(
        '{"status_code":7,"status_message":"Invalid API key: You must be '
        'granted a valid key.","success":false}',
        401,
      ),
    );

    await expectLater(
      provider.search(const MetadataQuery(text: 'inception')),
      throwsA(isA<MetadataProviderException>()
          .having((e) => e.message, 'message', contains('401'))),
    );
    expect(requests, hasLength(1));
  });

  test('corruptBodyThrowsTyped', () async {
    final (:provider, :requests) = build(
      handler: (request) async => http.Response('<<not json>>', 200),
    );

    await expectLater(
      provider.search(const MetadataQuery(text: 'inception')),
      throwsA(isA<MetadataProviderException>()),
    );
    expect(requests, hasLength(1));
  });

  test('missingResultsListThrowsTyped', () async {
    final (:provider, :requests) = build(
      handler: (request) async => okJson(const {'status_code': 5}),
    );

    await expectLater(
      provider.search(const MetadataQuery(text: 'inception')),
      throwsA(isA<MetadataProviderException>()
          .having((e) => e.message, 'message', contains('results'))),
    );
    expect(requests, hasLength(1));
  });

  test('emptyQueryIsDefinitiveMissWithoutRequest', () async {
    final (:provider, :requests) = build(
      handler: (request) async => okJson(movieHit),
    );

    final hit = await provider.search(const MetadataQuery(text: '   '));
    expect(hit, isNull);
    expect(requests, isEmpty);
  });

  test('providerNameIsTmdb', () {
    final provider = TmdbProvider(
      client: MockClient((request) async => http.Response('{}', 200)),
      apiKey: 'k',
    );
    expect(provider.name, 'tmdb');
  });
}
