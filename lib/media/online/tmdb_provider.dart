// The TMDB adapter skeleton (roadmap M4-T7, framework round). Speaks the
// v3 /search/multi endpoint over an INJECTED package:http client — the app
// wires a plain http.Client(), the tests inject package:http's MockClient,
// so no test ever touches the network.
//
// Endpoint facts (verified against the live host in the R11 reachability
// probe, 2026-11-12: `curl --max-time 10
// 'https://api.themoviedb.org/3/search/multi?query=inception&api_key=probe-only'`
// -> HTTP 401 body
// `{"status_code":7,"status_message":"Invalid API key: ...","success":false}`
// in 0.83 s; a Dart HttpClient probe with the same stack the adapter uses
// answered identically in 1.04 s. So: the host is reachable from this
// environment (the 2026-11-11 GitHub API TLS ECONNRESET does NOT apply
// here), TLS works, and an invalid key degrades to 401 — the adapter maps
// every non-200 to [MetadataProviderException], which the cache service
// turns into its `unavailable` status). The DATA path (valid key -> real
// results) stays pending the user's key and is asserted only against mock
// payloads shaped exactly like the documented TMDB response.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:emoplay/media/online/metadata_provider.dart';

/// The TMDB (themoviedb.org) v3 adapter.
///
/// Degrade contract: every failure mode — socket error, HTTP != 200 (401
/// invalid key included), malformed JSON, response shape mismatch, and the
/// request timeout — is thrown as [MetadataProviderException] (never a
/// crash, never a hang); a well-formed empty `results` list returns null
/// (definitive miss, cacheable as a negative).
class TmdbProvider implements MetadataProvider {
  TmdbProvider({
    required http.Client client,
    required String apiKey,
    this.language = 'zh-CN',
    this.requestTimeout = const Duration(seconds: 12),
    Uri? baseUrl,
  })  : _client = client,
        _apiKey = apiKey,
        _baseUrl = baseUrl ?? Uri.parse('https://api.themoviedb.org/3');

  final http.Client _client;
  final String _apiKey;

  /// ISO language code passed through as `language=` (localized titles /
  /// overviews). zh-CN matches the app's UI language default.
  final String language;

  /// Per-request bail-out. The default 12 s is generous enough for a cold
  /// TLS handshake; tests inject a much shorter one.
  final Duration requestTimeout;

  /// Overridable for tests (and for the documented alternative mirrors).
  final Uri _baseUrl;

  @override
  String get name => 'tmdb';

  @override
  Future<OnlineMetadata?> search(MetadataQuery query) async {
    if (query.text.trim().isEmpty) {
      return null; // nothing to ask — a definitive miss, not a failure
    }
    final uri = _baseUrl.replace(
      path: '${_baseUrl.path}/search/multi',
      queryParameters: <String, String>{
        'api_key': _apiKey,
        'query': query.text,
        'language': language,
        'page': '1',
        if (query.year != null && !query.episodeHint)
          'year': query.year.toString(),
      },
    );

    http.Response response;
    try {
      response = await _client.get(uri).timeout(requestTimeout);
    } on TimeoutException {
      throw MetadataProviderException('tmdb: request timed out');
    } catch (e) {
      // SocketException / http.ClientException / HandshakeException …:
      // offline and broken TLS are the same degrade path.
      throw MetadataProviderException('tmdb: network error ($e)');
    }

    if (response.statusCode != 200) {
      throw MetadataProviderException(
          'tmdb: http ${response.statusCode} (invalid API key when 401)');
    }

    Object? document;
    try {
      document = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw MetadataProviderException('tmdb: response is not valid JSON');
    }
    if (document is! Map) {
      throw MetadataProviderException('tmdb: response is not a JSON object');
    }
    final results = document['results'];
    if (results is! List) {
      throw MetadataProviderException('tmdb: response has no results list');
    }

    // First usable hit (the endpoint orders by relevance). Malformed
    // ENTRIES are skipped, not fatal — one weird row must not poison the
    // whole response.
    for (final result in results) {
      if (result is! Map) {
        continue;
      }
      final metadata = _mapResult(result, query.text);
      if (metadata != null) {
        return metadata;
      }
    }
    return null; // well-formed, definitively empty
  }

  /// Maps one TMDB search result object to [OnlineMetadata]; null when the
  /// row carries no usable title (skipped by the caller).
  OnlineMetadata? _mapResult(Map<Object?, Object?> result, String query) {
    final mediaType = result['media_type'] is String
        ? result['media_type'] as String
        : '';
    if (mediaType != 'movie' && mediaType != 'tv') {
      return null; // multi also yields 'person' rows — not media, skip
    }
    final title =
        (mediaType == 'movie' ? result['title'] : result['name']) is String
            ? (mediaType == 'movie'
                    ? result['title']
                    : result['name']) as String
            : '';
    if (title.isEmpty) {
      return null;
    }
    final originalTitle = (mediaType == 'movie'
            ? result['original_title']
            : result['original_name']) is String
        ? (mediaType == 'movie'
                ? result['original_title']
                : result['original_name']) as String
        : '';
    final dateString = (mediaType == 'movie'
            ? result['release_date']
            : result['first_air_date']) is String
        ? (mediaType == 'movie'
                ? result['release_date']
                : result['first_air_date']) as String
        : '';
    final year = _yearFrom(dateString);
    final rating =
        result['vote_average'] is num ? (result['vote_average'] as num) : null;
    final posterPath =
        result['poster_path'] is String ? result['poster_path'] as String : '';

    return OnlineMetadata(
      provider: name,
      providerId: result['id'] is int
          ? result['id'] as int
          : (result['id'] is num ? (result['id'] as num).toInt() : 0),
      mediaType: mediaType,
      title: title,
      originalTitle: originalTitle,
      year: year,
      rating: rating?.toDouble(),
      plot: result['overview'] is String ? result['overview'] as String : '',
      // /search/multi carries numeric genre_ids only; the id->name table is
      // a pending-with-real-key step (metadata_provider.dart field note).
      genres: const <String>[],
      posterUrl: posterPath.isEmpty
          ? ''
          : 'https://image.tmdb.org/t/p/w500$posterPath',
      query: query,
    );
  }

  /// '2020-08-26' -> 2020; anything else -> null.
  static int? _yearFrom(String dateString) {
    if (dateString.length < 4) {
      return null;
    }
    return int.tryParse(dateString.substring(0, 4));
  }
}
