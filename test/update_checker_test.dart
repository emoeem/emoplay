import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:emoplay/services/update_checker.dart';

// Case-for-case port of mpv-emo tests/test_update_checker.cpp; assertion
// values are the behavioural contract and are copied verbatim. The two
// values that changed deliberately follow the endpoint move to this
// repository (docs/SPEC.md §1: the 2.0 update source is
// repos/emoeem/emoplay/releases/latest, the 1.x source was
// repos/emoeem/mpv-emo/releases/latest):
//   - releasesUrlAssembly expects the emoplay path;
//   - every loopback request-line / release-page-URL assertion uses the
//     emoplay release page base.
//
// The C++ LoopbackServer (raw QTcpServer answering one canned response and
// recording request bytes) is emulated with a dart:io HttpServer bound to
// 127.0.0.1:0 — all UpdateChecker network tests run against localhost, no
// request ever leaves the machine. dart:io's HttpClient (what package:http
// drives here) does not consult proxy environment variables, which is the
// same insurance the C++ suite bought with QNetworkProxy::NoProxy.
void main() {
  // Minimal loopback HTTP server: answers every connection with one canned
  // response and records the request line plus the User-Agent header.
  Future<_LoopbackServer> startServer() => _LoopbackServer.start();

  // The 1.x releaseJson() helper: compact {"tag_name":..,"html_url":..}.
  String releaseJson(String tag, String htmlUrl) =>
      jsonEncode({'tag_name': tag, 'html_url': htmlUrl});

  // QTRY_* stand-in: pump the event loop until [condition] holds or the
  // timeout expires.
  Future<void> pumpUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('tagParsing', () {
    expect(UpdateChecker.tagToVersion('v0.2.0-beta'), '0.2.0-beta');
    expect(UpdateChecker.tagToVersion('V1.2.3'), '1.2.3');
    expect(UpdateChecker.tagToVersion('0.1.0'), '0.1.0');
    expect(UpdateChecker.tagToVersion('  v0.3.0 '), '0.3.0');
    // 'v' not followed by a digit is not a version prefix.
    expect(UpdateChecker.tagToVersion('verbose-1'), 'verbose-1');
    // Degenerate inputs pass through.
    expect(UpdateChecker.tagToVersion(''), '');
    expect(UpdateChecker.tagToVersion('v'), 'v');
  });

  test('versionComparison', () {
    // Equal numbers with different component counts.
    expect(UpdateChecker.compareVersions('1.0', '1.0.0'), 0);
    expect(UpdateChecker.compareVersions('0.1.0-alpha', '0.1.0-alpha'), 0);
    // Numeric ordering, left to right; not lexicographic.
    expect(UpdateChecker.compareVersions('0.3.0', '0.2.9') > 0, isTrue);
    expect(UpdateChecker.compareVersions('0.2.0', '1.0.0') < 0, isTrue);
    expect(UpdateChecker.compareVersions('10.0.0', '9.0.0') > 0, isTrue);
    // A release outranks its own pre-releases.
    expect(UpdateChecker.compareVersions('1.0.0', '1.0.0-beta') > 0, isTrue);
    expect(UpdateChecker.compareVersions('1.0.0-rc.1', '1.0.0') < 0, isTrue);
    // Pre-release ranks: alpha < beta < rc, numeric tails compare as numbers.
    expect(UpdateChecker.compareVersions('1.0.0-alpha', '1.0.0-beta') < 0,
        isTrue);
    expect(UpdateChecker.compareVersions('1.0.0-beta', '1.0.0-rc.1') < 0,
        isTrue);
    expect(UpdateChecker.compareVersions('1.0.0-rc.1', '1.0.0-rc.2') < 0,
        isTrue);
    expect(UpdateChecker.compareVersions('1.0.0-alpha.2', '1.0.0-alpha.10') < 0,
        isTrue);
    // Unrecognized identifiers order deterministically and tie on equality.
    expect(UpdateChecker.compareVersions('1.0.0-dev', '1.0.0-dev'), 0);
    expect(UpdateChecker.compareVersions('1.0.0-dev.1', '1.0.0-dev.2') < 0,
        isTrue);
    // 'v' prefixes are normalized inside the comparison.
    expect(UpdateChecker.compareVersions('v0.2.0-beta', '0.2.0-beta'), 0);
    expect(UpdateChecker.compareVersions('v0.3.0-beta', '0.2.0-beta') > 0,
        isTrue);
  });

  test('isNewerCases', () {
    // A newer prerelease beats an older one.
    expect(UpdateChecker.isNewer('0.2.0-beta', '0.3.0-alpha'), isTrue);
    // A release beats its own pre-release; never the other way around.
    expect(UpdateChecker.isNewer('0.2.0-beta', 'v0.2.0'), isTrue);
    expect(UpdateChecker.isNewer('0.2.0', '0.2.0-beta'), isFalse);
    // Same version is never newer (identity includes the 'v' normalization).
    expect(UpdateChecker.isNewer('0.2.0-beta', '0.2.0-beta'), isFalse);
    expect(UpdateChecker.isNewer('0.1.0', 'v0.1.0'), isFalse);
    // Rank progress within one release candidate series.
    expect(UpdateChecker.isNewer('0.2.0-beta', '0.2.0-rc.1'), isTrue);
    expect(UpdateChecker.isNewer('1.0.0-rc.2', '1.0.0-rc.10'), isTrue);
    expect(UpdateChecker.isNewer('1.0.0-rc.10', '1.0.0-rc.2'), isFalse);
  });

  test('releasesUrlAssembly', () {
    final checker = UpdateChecker('0.1.0');
    expect(
      checker.releasesUrl(),
      Uri.parse('https://api.github.com/repos/emoeem/emoplay/releases/latest'),
    );
    // Injectable base (used by the loopback cases); a trailing slash is
    // trimmed so the path never doubles.
    checker.apiBase = 'http://127.0.0.1:8080/';
    expect(
      checker.releasesUrl(),
      Uri.parse('http://127.0.0.1:8080/repos/emoeem/emoplay/releases/latest'),
    );
  });

  test('loopbackFindsNewerRelease', () async {
    final server = await startServer();
    try {
      server.setResponse(
          200,
          'OK',
          releaseJson('v99.0.0',
              'https://github.com/emoeem/emoplay/releases/tag/v99.0.0'));

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      final found = <List<String>>[];
      final done = Completer<void>();
      checker.onUpdateAvailable = (version, url) => found.add([version, url]);
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await done.future.timeout(const Duration(seconds: 10));

      expect(found.length, 1);
      expect(found[0][0], '99.0.0');
      expect(found[0][1],
          'https://github.com/emoeem/emoplay/releases/tag/v99.0.0');
      expect(checker.hasUpdate, isTrue);
      expect(checker.latestVersion, '99.0.0');
      expect(checker.releaseUrl,
          'https://github.com/emoeem/emoplay/releases/tag/v99.0.0');

      // The request hit the loopback endpoint with the required User-Agent.
      expect(server.requestCount, 1);
      expect(server.lastRequestLine,
          startsWith('GET /repos/emoeem/emoplay/releases/latest'));
      expect(server.userAgentHeader, startsWith('EmoPlay/0.2.0-beta'));
    } finally {
      await server.close();
    }
  });

  test('loopbackMissingHtmlUrlFallsBackToReleasePage', () async {
    final server = await startServer();
    try {
      server.setResponse(200, 'OK', releaseJson('v31.0.0', ''));

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      final found = <List<String>>[];
      final done = Completer<void>();
      checker.onUpdateAvailable = (version, url) => found.add([version, url]);
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await done.future.timeout(const Duration(seconds: 10));

      expect(found.length, 1);
      expect(found[0][1],
          'https://github.com/emoeem/emoplay/releases/tag/v31.0.0');
    } finally {
      await server.close();
    }
  });

  test('loopbackSameVersionIsSilent', () async {
    final server = await startServer();
    try {
      server.setResponse(
          200,
          'OK',
          releaseJson('v0.2.0-beta',
              'https://github.com/emoeem/emoplay/releases/tag/v0.2.0-beta'));

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      var foundCount = 0;
      final done = Completer<void>();
      checker.onUpdateAvailable = (_, _) => foundCount++;
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await done.future.timeout(const Duration(seconds: 10));

      expect(server.requestCount, 1);
      expect(foundCount, 0);
      expect(checker.hasUpdate, isFalse);
      expect(checker.latestVersion, '');
    } finally {
      await server.close();
    }
  });

  test('loopbackHttpErrorIsSilent', () async {
    final server = await startServer();
    try {
      server.setResponse(404, 'Not Found', '{}');

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      var foundCount = 0;
      final done = Completer<void>();
      checker.onUpdateAvailable = (_, _) => foundCount++;
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await done.future.timeout(const Duration(seconds: 10));

      expect(server.requestCount, 1);
      expect(foundCount, 0);
      expect(checker.hasUpdate, isFalse);
    } finally {
      await server.close();
    }
  });

  test('loopbackMalformedJsonIsSilent', () async {
    final server = await startServer();
    try {
      server.setResponse(200, 'OK', 'not-json');

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      var foundCount = 0;
      final done = Completer<void>();
      checker.onUpdateAvailable = (_, _) => foundCount++;
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await done.future.timeout(const Duration(seconds: 10));

      expect(foundCount, 0);
      expect(checker.hasUpdate, isFalse);
    } finally {
      await server.close();
    }
  });

  test('secondCheckWhileInFlightIsIgnored', () async {
    final server = await startServer();
    try {
      server.setResponse(
          200,
          'OK',
          releaseJson('v99.0.0',
              'https://github.com/emoeem/emoplay/releases/tag/v99.0.0'));
      server.setHoldOpen(true);

      final checker = UpdateChecker('0.2.0-beta');
      checker.apiBase = 'http://127.0.0.1:${server.port}';
      var foundCount = 0;
      final done = Completer<void>();
      checker.onUpdateAvailable = (_, _) => foundCount++;
      checker.onCheckFinished = () {
        if (!done.isCompleted) done.complete();
      };

      checker.check();
      await pumpUntil(() => server.requestCount == 1);
      checker.check(); // a check is in flight: this must send nothing
      server.releaseHeld();
      await done.future.timeout(const Duration(seconds: 10));

      expect(server.requestCount, 1);
      expect(foundCount, 1);
      expect(checker.latestVersion, '99.0.0');
    } finally {
      await server.close();
    }
  });
}

// dart:io emulation of the C++ LoopbackServer (QTcpServer): bind to an
// ephemeral loopback port, answer every connection with one canned response,
// record the request line and User-Agent header, and optionally hold
// connections open instead of answering (releaseHeld() answers them — used
// to verify a second check() while one is in flight is a no-op).
class _LoopbackServer {
  _LoopbackServer._(this._server) {
    _subscription = _server.listen(_onRequest, onError: (_) {});
  }

  final HttpServer _server;
  StreamSubscription<void>? _subscription;

  int _status = 200;
  String _reason = 'OK';
  List<int> _body = utf8.encode('');

  int _requestCount = 0;
  String? _lastRequestLine;
  String? _userAgentHeader;

  bool _holdOpen = false;
  final List<HttpRequest> _held = [];

  static Future<_LoopbackServer> start() async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LoopbackServer._(server);
  }

  int get port => _server.port;
  int get requestCount => _requestCount;
  String? get lastRequestLine => _lastRequestLine;
  String? get userAgentHeader => _userAgentHeader;

  void setResponse(int status, String reason, String body) {
    _status = status;
    _reason = reason;
    _body = utf8.encode(body);
  }

  void setHoldOpen(bool hold) => _holdOpen = hold;

  void releaseHeld() {
    final held = List<HttpRequest>.from(_held);
    _held.clear();
    for (final request in held) {
      _respond(request);
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  void _onRequest(HttpRequest request) {
    _requestCount++;
    _lastRequestLine = '${request.method} ${request.uri.path} HTTP/1.1';
    final userAgent = request.headers.value('User-Agent');
    if (userAgent != null) {
      _userAgentHeader = userAgent;
    }
    if (_holdOpen) {
      _held.add(request);
      return;
    }
    _respond(request);
  }

  // C++ respond(): "HTTP/1.1 <status> <reason>\r\nContent-Type:
  // application/json\r\nConnection: close\r\nContent-Length: <n>\r\n\r\n"
  // followed by the canned body, then disconnect.
  void _respond(HttpRequest request) {
    request.response.statusCode = _status;
    request.response.reasonPhrase = _reason;
    request.response.headers.set('Content-Type', 'application/json');
    request.response.contentLength = _body.length;
    request.response.persistentConnection = false; // Connection: close
    request.response.add(_body);
    unawaited(request.response.close().then((_) {}, onError: (_) {}));
  }
}
