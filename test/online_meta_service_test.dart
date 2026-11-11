import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:emoplay/media/nfo_meta_cache.dart';
import 'package:emoplay/media/online/metadata_provider.dart';
import 'package:emoplay/media/online/online_meta_service.dart';

/// M4-T7 guard tests (user redirection 2026-11-12): the OnlineMetaService
/// gate chain — 开关关闭不联网、无 key 降级、本地 NFO 覆盖不联网、缓存命中
/// 不发请求、损坏响应/HTTP 错误/超时全部降级 — plus the media_online.json
/// persistence (positives AND definitive negatives cached; transport
/// failures never cached).
///
/// Every request goes through a counting package:http MockClient: the
/// request count IS the assertion that the local-first discipline holds.
/// No test touches the network.
void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emoplay-online-');
  });
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String cachePath() => '${tempDir.path}/media_online.json';

  /// A TMDB-shaped search hit (documented /search/multi response).
  const tmdbHit = <String, Object?>{
    'page': 1,
    'results': [
      <String, Object?>{
        'adult': false,
        'backdrop_path': '/backdrop.jpg',
        'id': 27205,
        'title': 'Inception',
        'original_title': 'Inception',
        'overview': 'A thief who steals corporate secrets.',
        'release_date': '2010-07-16',
        'poster_path': '/poster.jpg',
        'media_type': 'movie',
        'vote_average': 8.4,
        'vote_count': 30000,
      },
    ],
    'total_pages': 1,
    'total_results': 1,
  };

  http.Response okJson(Object? body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json;charset=utf-8'},
      );

  /// A counting mock: |handler| answers, the counter records. The counter
  /// object is shared and inspectable after the await.
  ({http.Client client, List<http.Request> requests}) countingClient(
      Future<http.Response> Function(http.Request request) handler) {
    final requests = <http.Request>[];
    return (
      client: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
      requests: requests,
    );
  }

  /// The stable "hit" handler used by the positive-path tests.
  Future<http.Response> hitHandler(http.Request request) async =>
      okJson(tmdbHit);

  OnlineMetaService buildService({
    required http.Client client,
    bool enabled = true,
    String apiKey = 'test-key',
    NfoMetaCache? nfoMeta,
    Duration timeout = const Duration(milliseconds: 200),
  }) {
    return OnlineMetaService(
      cachePath(),
      enabled: () => enabled,
      apiKey: () => apiKey,
      nfoMeta: nfoMeta,
      providerFactory: () => _StaticUriProvider(client),
      requestTimeout: timeout,
    );
  }

  test('switchOffDoesNotRequest', () async {
    // 门禁 1：总开关关闭（默认态）——零请求。
    final (:client, :requests) =
        countingClient((request) async => okJson(tmdbHit));
    final service = buildService(client: client, enabled: false);

    final result = await service.lookup('/tmp/whatever.mkv',
        queryText: 'Whatever');
    expect(result.status, OnlineLookupStatus.disabled);
    expect(result.metadata, isNull);
    expect(requests, isEmpty);
    expect(File(cachePath()).existsSync(), isFalse,
        reason: 'nothing was looked up, nothing to persist');
  });

  test('noKeyDegradesWithoutRequest', () async {
    // 门禁 2：未配置 API key（用户尚未填写）——零请求、优雅降级。
    final (:client, :requests) =
        countingClient((request) async => okJson(tmdbHit));
    final service = buildService(client: client, apiKey: '');

    final result = await service.lookup('/tmp/whatever.mkv',
        queryText: 'Whatever');
    expect(result.status, OnlineLookupStatus.noKey);
    expect(requests, isEmpty);
  });

  test('localNfoPresenceSkipsNetwork', () async {
    // 门禁 3：本地 NFO 存在（M4-T6 数据）——本地优先，零请求。
    final dir = Directory('${tempDir.path}/Movies')..createSync();
    File('${dir.path}/film.mkv').writeAsStringSync('video');
    File('${dir.path}/movie.nfo').writeAsStringSync(
        '<movie><title>Local Movie</title><year>2020</year></movie>');

    final nfo = NfoMetaCache('${tempDir.path}/media_nfo.json');
    addTearDown(nfo.dispose);
    final info = await nfo.requestInfo('${dir.path}/film.mkv');
    expect(info!.hasNfo, isTrue, reason: 'precondition: the NFO was scanned');

    final (:client, :requests) =
        countingClient((request) async => okJson(tmdbHit));
    final service = buildService(client: client, nfoMeta: nfo);

    final result = await service.lookup('${dir.path}/film.mkv',
        queryText: 'Local Movie');
    expect(result.status, OnlineLookupStatus.localCovered);
    expect(requests, isEmpty);
  });

  test('cacheHitDoesNotRequest', () async {
    // 门禁 4：media_online.json 已有记录（含跨服务实例重启）——命中缓存
    // 不发请求。
    final (:client, :requests) = countingClient(hitHandler);
    final first = buildService(client: client);
    final videoPath = '${tempDir.path}/Movies/film.mkv';

    final found = await first.lookup(videoPath, queryText: 'Inception');
    expect(found.status, OnlineLookupStatus.found);
    expect(requests, hasLength(1));

    // A second service instance over the same file serves the same record
    // from the pure map read — zero further requests.
    final (client: secondClient, requests: secondRequests) =
        countingClient((request) async => okJson(tmdbHit));
    final second = buildService(client: secondClient);
    final cached = await second.lookup(videoPath, queryText: 'Inception');
    expect(cached.status, OnlineLookupStatus.fromCache);
    expect(cached.metadata!.title, 'Inception');
    expect(secondRequests, isEmpty);
  });

  test('corruptResponseDegradesAndIsNotCached', () async {
    // 降级：损坏响应（200 + 非 JSON 体）→ unavailable，不崩溃；且传输层
    // 失败绝不落缓存——下一次查询允许重试。
    final (:client, :requests) = countingClient(
        (request) async => http.Response('<<html>not json</html>', 200));
    final service = buildService(client: client);
    final videoPath = '${tempDir.path}/Movies/film.mkv';

    final result = await service.lookup(videoPath, queryText: 'Inception');
    expect(result.status, OnlineLookupStatus.unavailable);
    expect(File(cachePath()).existsSync(), isFalse,
        reason: 'transport failures are never cached');
    expect(service.infoFor(videoPath), isNull);

    // The retry actually re-requests (the failure was not remembered).
    final second = await service.lookup(videoPath, queryText: 'Inception');
    expect(second.status, OnlineLookupStatus.unavailable);
    expect(requests, hasLength(2));
  });

  test('httpErrorDegrades', () async {
    // 降级：HTTP 401（无效 key，R11 探针实测的在线形态）→ unavailable。
    final (:client, :requests) = countingClient((request) async =>
        http.Response(
            '{"status_code":7,"status_message":"Invalid API key.","success":false}',
            401));
    final service = buildService(client: client);

    final result = await service.lookup('${tempDir.path}/f.mkv',
        queryText: 'Inception');
    expect(result.status, OnlineLookupStatus.unavailable);
    expect(requests, hasLength(1));
  });

  test('timeoutDegrades', () async {
    // 降级：超时（悬挂的 mock + 注入的短超时）→ unavailable，且在超时窗
    // 内返回，绝不挂死调用方。
    final (:client, :requests) = countingClient((request) async {
      await Completer<http.Response>().future; // never completes
      throw StateError('unreachable');
    });
    final service = buildService(client: client,
        timeout: const Duration(milliseconds: 50));

    final sw = Stopwatch()..start();
    final result = await service.lookup('${tempDir.path}/f.mkv',
        queryText: 'Inception');
    sw.stop();
    expect(result.status, OnlineLookupStatus.unavailable);
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    expect(requests, hasLength(1));
  });

  test('successfulLookupPersistsToMediaOnlineJson', () async {
    // 正路：found 结果持久化为 media_online.json 的文档结构，重新加载
    // 后逐字段可读回。
    final (:client, :requests) = countingClient(hitHandler);
    final service = buildService(client: client);
    final videoPath = '${tempDir.path}/Movies/film.mkv';

    final result = await service.lookup(videoPath, queryText: 'Inception');
    expect(result.status, OnlineLookupStatus.found);
    expect(result.metadata!.provider, 'tmdb');
    expect(result.metadata!.providerId, 27205);
    expect(result.metadata!.year, 2010);

    final document =
        jsonDecode(File(cachePath()).readAsStringSync()) as Map;
    expect(document['version'], 1);
    final entry = (document['entries'] as Map)[videoPath] as Map;
    final metadata = entry['metadata'] as Map;
    expect(metadata['title'], 'Inception');
    expect(metadata['provider'], 'tmdb');
    expect(entry['fetchedAt'], isA<String>());
    expect(requests, hasLength(1));
  });

  test('definitiveMissIsCachedAsNegative', () async {
    // 明确未命中（合法空 results）也缓存为负记录——同一路径不再反复打扰
    // API；重启后仍为负记录、零请求。
    final (:client, :requests) =
        countingClient((request) async => okJson(<String, Object?>{
              'page': 1,
              'results': <Object?>[],
              'total_results': 0,
            }));
    final service = buildService(client: client);
    final videoPath = '${tempDir.path}/Movies/film.mkv';

    final miss = await service.lookup(videoPath, queryText: 'zz-no-such');
    expect(miss.status, OnlineLookupStatus.notFound);

    final again = await service.lookup(videoPath, queryText: 'zz-no-such');
    expect(again.status, OnlineLookupStatus.notFound);
    expect(requests, hasLength(1), reason: 'the negative answer is cached');

    // And the negative survives a reload.
    final reloaded = buildService(client: client);
    expect(reloaded.infoFor(videoPath), isNotNull);
    expect(reloaded.infoFor(videoPath)!.metadata, isNull);
    final cached = await reloaded.lookup(videoPath, queryText: 'zz-no-such');
    expect(cached.status, OnlineLookupStatus.notFound);
    expect(requests, hasLength(1));
  });

  test('forgetDropsEntry', () async {
    // forget()：单条清除后重新发起真实查询。
    final (:client, :requests) = countingClient(hitHandler);
    final service = buildService(client: client);
    final videoPath = '${tempDir.path}/Movies/film.mkv';
    await service.lookup(videoPath, queryText: 'Inception');
    expect(requests, hasLength(1));

    service.forget(videoPath);
    expect(service.infoFor(videoPath), isNull);
    await service.lookup(videoPath, queryText: 'Inception');
    expect(requests, hasLength(2));
  });
}

/// A [MetadataProvider] over a raw injected client with a fixed apiKey —
/// stands in for the real [TmdbProvider] here so the service tests never
/// depend on the adapter's URI building (that is tmdb_provider_test.dart's
/// job). Identical failure semantics: throws on transport problems.
class _StaticUriProvider implements MetadataProvider {
  _StaticUriProvider(this._client) : _apiKey = 'test-key';

  final http.Client _client;
  final String _apiKey;

  @override
  String get name => 'tmdb';

  @override
  Future<OnlineMetadata?> search(MetadataQuery query) async {
    final uri = Uri.parse('https://api.themoviedb.org/3/search/multi'
        '?api_key=$_apiKey&query=${Uri.encodeQueryComponent(query.text)}'
        '&language=zh-CN&page=1');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MetadataProviderException('tmdb: http ${response.statusCode}');
    }
    final Object? document;
    try {
      document = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw MetadataProviderException('tmdb: not JSON');
    }
    final results = (document as Map)['results'];
    if (results is! List) {
      throw MetadataProviderException('tmdb: no results list');
    }
    for (final result in results) {
      if (result is Map && result['media_type'] == 'movie') {
        return OnlineMetadata(
          provider: name,
          providerId: result['id'] is int ? result['id'] as int : 0,
          mediaType: 'movie',
          title: result['title'] is String ? result['title'] as String : '',
          year: result['release_date'] is String &&
                  (result['release_date'] as String).length >= 4
              ? int.tryParse(
                  (result['release_date'] as String).substring(0, 4))
              : null,
          plot: result['overview'] is String
              ? result['overview'] as String
              : '',
          query: query.text,
        );
      }
    }
    return null;
  }
}
