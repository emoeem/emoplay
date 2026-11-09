// Dart port of mpv-emo src/plugins/RemoteManifestSource.{h,cpp} and
// PluginRemoteFetcher.{h,cpp} (PORT-MAP §1: QNAM → package:http; cache file
// name host+URL digest unchanged).
//
// P8 v2 online plugin manifest sources: fetches manager.json-compatible
// catalogs (docs/nativeization-plan.md §4.1) over HTTP(S), merges them with
// the local install state for the plugins page's online section, and caches
// every successful fetch so an offline machine still shows the last known
// list. Network failure is a hint, never a crash (graceful degradation
// contract): the cached manifests stay loaded and the error callback
// reports the problem.
//
// Sources: the default upstream manifest plus user-added custom URLs,
// persisted under <appDataDir>/plugin-sources/sources.json. Every successful
// fetch is cached to <appDataDir>/plugin-sources/<source>.json (a wrapper
// carrying the fetch time and the raw body) and reloaded from there on the
// next start, so entries are available before the first refresh.
//
// Cross-source rule: sources are polled in order (default first, custom in
// insertion order) and the FIRST source declaring a plugin name wins. The
// shipped builtin catalog keeps priority over ALL online sources via
// PluginManager.setRemoteCatalog (builtin names are never shadowed).
//
// The network goes through the injectable PluginRemoteFetcher seam (unit
// tests answer synchronously, no real HTTP); the merge logic is a pure
// static function unit-tested without network or git.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:emoplay/plugins/plugin_manager.dart';
import 'package:emoplay/plugins/plugin_manifest.dart';
import 'package:emoplay/services/logging/logger.dart';

/// Result of one manifest-source fetch (one HTTP GET) — the 1.x
/// PluginRemoteFetchResult.
class PluginRemoteFetchResult {
  const PluginRemoteFetchResult({
    this.httpStatus = 0,
    this.body = '',
    this.error = '',
    this.success = false,
  });

  /// HTTP status code; 0 when the request never got a reply (DNS failure,
  /// timeout, offline machine...).
  final int httpStatus;
  final String body;

  /// Human-readable failure reason; empty on success.
  final String error;

  /// Answered with a 2xx status; only then is [body] meaningful.
  final bool success;
}

/// Seam between RemoteManifestSource and the network, mirroring the
/// PluginGitRunner seam: unit tests inject a fake that answers
/// synchronously with fixture bytes and never touch the network.
abstract class PluginRemoteFetcher {
  /// Starts a GET for [url]. Exactly one completion is reported through
  /// [onFinished] per call. Synchronous reporting is allowed (fakes);
  /// RemoteManifestSource tolerates it.
  void fetch(Uri url);

  /// The 1.x finished(url, result) signal.
  void Function(Uri url, PluginRemoteFetchResult result)? onFinished;
}

/// Production implementation: one package:http GET per fetch, with a bounded
/// transfer timeout so an offline machine degrades to the cached manifest
/// list after a fixed wait instead of hanging the refresh forever.
class HttpPluginRemoteFetcher implements PluginRemoteFetcher {
  @override
  void Function(Uri url, PluginRemoteFetchResult result)? onFinished;

  http.Client? _client;
  Uri? _current;

  // Bounded wait per source: the graceful-degradation contract requires the
  // refresh to fail (and the cached list to show) even when the network
  // silently blackholes packets.
  static const Duration _transferTimeout = Duration(seconds: 15);

  @override
  void fetch(Uri url) {
    // Supersede any in-flight fetch: it is dropped from the current slot so
    // its late completion is ignored (exactly one completion per outstanding
    // fetch — the newest one). The 1.x QNAM runner aborted the stale reply;
    // here the stale result is discarded by the url check in
    // RemoteManifestSource._onFetchFinished.
    _current = url;
    _client ??= http.Client();
    final request = http.Request('GET', url)
      // Qt 6's default redirect policy was NoLessSafeRedirects; http follows
      // safe redirects automatically.
      ..followRedirects = true
      ..headers['Accept'] = 'application/json';
    final slot = url;
    unawaited(_runFetch(slot, request));
  }

  Future<void> _runFetch(Uri slot, http.Request request) async {
    try {
      final streamed =
          await _client!.send(request).timeout(_transferTimeout);
      final response =
          await http.Response.fromStream(streamed).timeout(_transferTimeout);
      if (_current != slot) {
        return; // stale reply from a superseded fetch
      }
      final ok = streamed.statusCode >= 200 && streamed.statusCode < 300;
      onFinished?.call(
        slot,
        PluginRemoteFetchResult(
          httpStatus: streamed.statusCode,
          body: ok ? utf8.decode(response.bodyBytes) : '',
          error: ok ? '' : 'HTTP ${streamed.statusCode}',
          success: ok,
        ),
      );
    } catch (e) {
      if (_current != slot) {
        return;
      }
      onFinished?.call(
        slot,
        PluginRemoteFetchResult(
          httpStatus: 0,
          body: '',
          error: e.toString(),
          success: false,
        ),
      );
    }
  }

  /// Closes the HTTP client (the 1.x runner died with its QObject owner).
  void dispose() {
    _client?.close();
    _client = null;
  }
}

/// Online manifest sources: one ChangeNotifier mirroring the 1.x
/// RemoteManifestSource QObject (entries / sources / refreshing).
class RemoteManifestSource extends ChangeNotifier {
  RemoteManifestSource({
    required String appDataDir,
    PluginManager? manager,
    PluginRemoteFetcher? fetcher,
    void Function(String message)? onError,
  })  : _cacheDir = '$appDataDir/plugin-sources',
        _sourceListPath = '$appDataDir/plugin-sources/sources.json',
        _manager = manager,
        _onError = onError {
    // Cache files are written via temp+rename, which does not create the
    // directory itself.
    Directory(_cacheDir).createSync(recursive: true);
    _fetcher = fetcher ?? HttpPluginRemoteFetcher();
    _fetcher.onFinished = _onFetchFinished;

    _loadSourceList();
    _loadCachedManifests();
    _rebuildEntries();

    // Re-merge when the local install state moves (install/uninstall/
    // enable/check), so the online section always mirrors the store.
    _manager?.addListener(_onManagerChanged);
  }

  final String _cacheDir;
  final String _sourceListPath;
  final PluginManager? _manager;
  final void Function(String message)? _onError;

  late final PluginRemoteFetcher _fetcher;

  final List<_SourceEntry> _sources = <_SourceEntry>[];
  // Key = url.toString(): per-source manifests + last successful fetch.
  final Map<String, List<PluginManifest>> _manifests =
      <String, List<PluginManifest>>{};
  final Map<String, DateTime> _lastRefresh = <String, DateTime>{};

  List<Map<String, Object?>> _entries = <Map<String, Object?>>[];
  List<Map<String, Object?>> _sourceRows = <Map<String, Object?>>[];
  final List<Uri> _fetchQueue = <Uri>[];
  Uri? _currentUrl;
  bool _refreshing = false;

  /// Merged display rows: remote manifests x local install state.
  List<Map<String, Object?>> get entries => _entries;

  /// One row per configured source: {url, isDefault, lastRefreshMs}.
  List<Map<String, Object?>> get sources => _sourceRows;

  /// True while a refresh cycle (possibly several queued fetches) runs.
  bool get refreshing => _refreshing;

  /// The most recent error report (network failure, corrupt cache, rejected
  /// source URL...) — the UI's hint line mirrors the 1.x errorOccurred
  /// signal through this field.
  String lastError = '';

  // ---- pure helpers (unit-tested without network or git) --------------------

  /// P8 v2 default source: the user repository's manager.json, the same
  /// format the builtin catalog was transcribed from
  /// (assets/plugins/builtin_sources.json).
  static String defaultSourceUrl() =>
      'https://raw.githubusercontent.com/emoeem/mpv/main/manager.json';

  /// Cache file name (inside the plugin-sources directory) for a source
  /// URL: sanitized host + a short digest of the full URL, so two sources
  /// on one host with different paths never share a file.
  static String cacheFileName(Uri url) {
    final host = StringBuffer();
    for (final character in url.host.split('')) {
      final code = character.codeUnitAt(0);
      final letterOrNumber = (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A);
      if (letterOrNumber || character == '.' || character == '-') {
        host.write(character);
      } else {
        host.write('_');
      }
    }
    final digest =
        crypto.sha256.convert(utf8.encode(url.toString())).toString();
    return '${host.isEmpty ? 'source' : host}-${digest.substring(0, 12)}.json';
  }

  /// The merge the page displays: [manifests] (already the deduplicated
  /// union across sources) x [localPlugins] rows shaped like
  /// PluginManager.plugins(). Remote-only names default to "not
  /// installed"; known names copy installed/enabled/head/remoteHead/
  /// updateAvailable/locallyModified from the local row. The manifest
  /// fields (name/url/branch/source/destination/mode/baseline) keep their
  /// remote values — including the URL of a plugin that is ALSO in the
  /// builtin catalog (the manager's builtin row stays authoritative there).
  static List<Map<String, Object?>> mergeCatalog(
    List<PluginManifest> manifests,
    List<Map<String, Object?>> localPlugins,
  ) {
    final local = <String, Map<String, Object?>>{
      for (final row in localPlugins)
        (row['name'] as String? ?? ''): row,
    };

    final merged = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final manifest in manifests) {
      if (!manifest.valid || seen.contains(manifest.name)) {
        continue; // first source wins on cross-source name collisions
      }
      seen.add(manifest.name);
      final localRow = local[manifest.name] ?? const <String, Object?>{};
      merged.add(<String, Object?>{
        'name': manifest.name,
        'url': manifest.url,
        'branch': manifest.branch,
        'source': manifest.source,
        'destination': manifest.destination,
        'mode': manifest.mode,
        'baseline': manifest.baseline,
        'isScript': manifest.isScriptPlugin,
        'installed': localRow['installed'] ?? false,
        'enabled': localRow['enabled'] ?? false,
        'head': localRow['head'] ?? '',
        'remoteHead': localRow['remoteHead'] ?? '',
        'updateAvailable': localRow['updateAvailable'] ?? false,
        'locallyModified': localRow['locallyModified'] ?? false,
      });
    }
    return merged;
  }

  // ---- source list ------------------------------------------------------------

  void _loadSourceList() {
    _sources.clear();
    _sources.add(_SourceEntry(
      url: Uri.parse(defaultSourceUrl()),
      isDefault: true,
    ));

    String text;
    try {
      text = File(_sourceListPath).readAsStringSync();
    } catch (_) {
      return; // first run: only the default source
    }
    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return;
    }
    final sources = document is Map ? document['sources'] : null;
    if (sources is! List) {
      return;
    }
    final seen = <String>{for (final s in _sources) s.url.toString()};
    for (final value in sources) {
      final url = value is String ? Uri.tryParse(value) : null;
      // Tolerate garbage and a persisted copy of the default: neither
      // becomes a second source row. A repeated custom URL (only writable
      // by hand-editing sources.json — the app never saves duplicates)
      // loads once too: duplicates would mean duplicate rows and
      // duplicate network fetches.
      if (url == null || !_isFetchableUrl(url) || seen.contains(url.toString())) {
        continue;
      }
      seen.add(url.toString());
      _sources.add(_SourceEntry(url: url));
    }
  }

  bool _saveSourceList() {
    final root = <String, Object?>{
      'sources': <String>[
        for (final source in _sources)
          if (!source.isDefault) source.url.toString(),
      ],
    };
    try {
      final temp = File('$_sourceListPath.tmp');
      temp.writeAsStringSync(
          const JsonEncoder.withIndent('    ').convert(root),
          flush: true);
      temp.renameSync(_sourceListPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- cache ------------------------------------------------------------------

  String _cachePathFor(Uri url) => '$_cacheDir/${cacheFileName(url)}';

  void _storeCache(Uri url, String body) {
    // One wrapper per source: the raw body plus the fetch time (reloaded on
    // the next start so the "last refreshed" label survives restarts).
    final wrapper = <String, Object?>{
      'url': url.toString(),
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'body': body,
    };
    try {
      final temp = File('${_cachePathFor(url)}.tmp');
      temp.writeAsStringSync(
          const JsonEncoder.withIndent('    ').convert(wrapper),
          flush: true);
      temp.renameSync(_cachePathFor(url));
    } catch (_) {
      _emitError('cannot write plugin-source cache ${_cachePathFor(url)}');
      return; // non-fatal: the in-memory list is still updated
    }
  }

  void _loadCachedManifests() {
    for (final source in _sources) {
      _loadCachedManifestsFor(source.url);
    }
  }

  void _loadCachedManifestsFor(Uri url) {
    String text;
    try {
      text = File(_cachePathFor(url)).readAsStringSync();
    } catch (_) {
      return; // no cache yet: the source just has no offline copy
    }
    Object? wrapper;
    try {
      wrapper = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (wrapper is! Map) {
      return;
    }
    final fetchedAt =
        DateTime.tryParse(wrapper['fetchedAt'] as String? ?? '');
    final error = StringBuffer();
    final manifests = PluginManifest.parseList(
      wrapper['body'] as String? ?? '',
      errorOut: error,
    );
    if (error.isNotEmpty) {
      // Fail closed: a corrupt cache copy is dropped, never fed upstream.
      _emitError(
          'cached manifest ${_cachePathFor(url)} is corrupt: $error');
      return;
    }
    _manifests[url.toString()] = manifests;
    if (fetchedAt != null) {
      _lastRefresh[url.toString()] = fetchedAt;
    }
  }

  // ---- merge ------------------------------------------------------------------

  /// Deduplicated union across sources, in source order (first wins).
  List<PluginManifest> _unionManifests() {
    final union = <PluginManifest>[];
    final seen = <String>{};
    for (final source in _sources) {
      final manifests = _manifests[source.url.toString()];
      if (manifests == null) {
        continue;
      }
      for (final manifest in manifests) {
        if (!manifest.valid || seen.contains(manifest.name)) {
          continue;
        }
        seen.add(manifest.name);
        union.add(manifest);
      }
    }
    return union;
  }

  Map<String, Object?> _sourceRow(_SourceEntry source) {
    final refresh = _lastRefresh[source.url.toString()];
    return <String, Object?>{
      'url': source.url.toString(),
      'isDefault': source.isDefault,
      'lastRefreshMs': refresh == null
          ? 0
          : refresh.millisecondsSinceEpoch,
    };
  }

  void _recomputeEntries() {
    _entries = mergeCatalog(_unionManifests(), _manager?.plugins() ?? const []);
    _sourceRows = <Map<String, Object?>>[
      for (final source in _sources) _sourceRow(source),
    ];
  }

  /// _recomputeEntries + push the union into PluginManager (when present).
  void _rebuildEntries() {
    _recomputeEntries();
    if (_manager != null) {
      // Online manifests become installable/updateable like builtin ones.
      // The manager's notifyListeners then re-merges via
      // _onManagerChanged, which does NOT push again — no recursion.
      _manager.setRemoteCatalog(_unionManifests());
    }
    notifyListeners();
  }

  void _onManagerChanged() {
    _recomputeEntries();
    notifyListeners();
  }

  // ---- fetching ---------------------------------------------------------------

  /// Queues every configured source (default first); one HTTP fetch at a
  /// time, results cache + merge as the replies arrive. No-op while a
  /// refresh cycle is already running.
  void refreshAll() {
    if (_refreshing) {
      return; // one refresh cycle at a time; the queue drains itself
    }
    for (final source in _sources) {
      _fetchQueue.add(source.url);
    }
    _startNextFetch();
  }

  void _startNextFetch() {
    if (_currentUrl != null) {
      return; // a fetch is in flight; the queue drains as replies arrive
    }
    if (_fetchQueue.isEmpty) {
      if (_refreshing) {
        _refreshing = false;
        notifyListeners();
      }
      return;
    }
    _refreshing = true;
    _currentUrl = _fetchQueue.removeAt(0);
    notifyListeners();
    _fetcher.fetch(_currentUrl!);
    // (the non-null assertion above is load-bearing: _currentUrl is nullable
    // because "no fetch in flight" is represented by null)
  }

  void _onFetchFinished(Uri url, PluginRemoteFetchResult result) {
    if (url != _currentUrl) {
      return; // stale reply from a superseded fetch
    }
    _currentUrl = null;

    var sourceKnown = false;
    for (final source in _sources) {
      if (source.url == url) {
        sourceKnown = true;
        break;
      }
    }

    if (sourceKnown && result.success) {
      final error = StringBuffer();
      final manifests =
          PluginManifest.parseList(result.body, errorOut: error);
      if (error.isNotEmpty) {
        // Fail closed, same contract as the builtin catalog loader: the
        // previous cache + manifests stay untouched, so the last good
        // list remains visible instead of half-parsed entries.
        _emitError('source $url: $error');
      } else {
        _storeCache(url, result.body);
        _manifests[url.toString()] = manifests;
        _lastRefresh[url.toString()] = DateTime.now().toUtc();
        _rebuildEntries();
      }
    } else if (sourceKnown) {
      // Network failure: _manifests keeps the cached manifests loaded at
      // startup — the page degrades to the last known list.
      _emitError('cannot fetch $url: ${result.error} — showing the '
          'last cached list');
    }
    // No trailing notifyListeners here: every observable transition already
    // emits — _rebuildEntries() when entries/sources move, _startNextFetch()
    // when a fetch starts or the queue drains. Emitting again would reset
    // the page's list models up to three times per fetched source.
    _startNextFetch();
  }

  // ---- source management ------------------------------------------------------

  /// Adds a custom http(s) source, persists it and fetches it right away.
  /// False (with an error report) for invalid schemes, host-less URLs and
  /// duplicates of an already-configured source.
  bool addSource(Uri url) {
    if (!_isFetchableUrl(url)) {
      _emitError('invalid manifest source "$url" — '
          'expected an http(s) URL with a host');
      return false;
    }
    for (final source in _sources) {
      if (source.url == url) {
        _emitError('source $url is already configured');
        return false;
      }
    }
    _sources.add(_SourceEntry(url: url));
    if (!_saveSourceList()) {
      _emitError('cannot save $_sourceListPath');
    }
    // An offline add still shows the cached copy of the new source, if any.
    _loadCachedManifestsFor(url);
    _rebuildEntries();
    _fetchQueue.add(url);
    _startNextFetch();
    return true;
  }

  /// Removes a custom source (its cache file goes with it); the default
  /// source cannot be removed. False (with an error report) for the default
  /// and for unknown URLs.
  bool removeSource(Uri url) {
    var removed = false;
    final kept = <_SourceEntry>[];
    for (final source in _sources) {
      if (!source.isDefault && source.url == url) {
        removed = true;
      } else {
        kept.add(source);
      }
    }
    if (!removed) {
      _emitError(url.toString() == defaultSourceUrl()
          ? 'the default source cannot be removed'
          : 'source $url is not configured');
      return false;
    }
    _sources
      ..clear()
      ..addAll(kept);
    _manifests.remove(url.toString());
    _lastRefresh.remove(url.toString());
    _fetchQueue.remove(url);
    try {
      File(_cachePathFor(url)).deleteSync();
    } catch (_) {}
    if (!_saveSourceList()) {
      _emitError('cannot save $_sourceListPath');
    }
    _rebuildEntries();
    return true;
  }

  @override
  void dispose() {
    _manager?.removeListener(_onManagerChanged);
    final fetcher = _fetcher;
    if (fetcher is HttpPluginRemoteFetcher) {
      fetcher.dispose();
    }
    super.dispose();
  }

  void _emitError(String message) {
    EmoLogger().w('plugins: $message');
    lastError = message;
    notifyListeners();
    _onError?.call(message);
  }

  static bool _isFetchableUrl(Uri url) {
    return url.host.isNotEmpty &&
        (url.scheme == 'https' || url.scheme == 'http');
  }
}

class _SourceEntry {
  const _SourceEntry({required this.url, this.isDefault = false});

  final Uri url;
  final bool isDefault;
}
