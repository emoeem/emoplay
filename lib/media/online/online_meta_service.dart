import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:emoplay/media/library_store.dart' show LibraryStore;
import 'package:emoplay/media/nfo_meta_cache.dart';
import 'package:emoplay/media/online/metadata_provider.dart';

// The online metadata FALLBACK service (roadmap M4-T7, user redirection
// 2026-11-12): the联网补全 layer AFTER the local NFO/poster pass (M4-T6,
// NfoMetaCache) — LOCAL-FIRST by construction, it never queries the
// network for a video whose directory already carries an NFO file.
//
// Gate order (each step returns WITHOUT any network IO — locked by
// test/online_meta_service_test.dart):
//   1. the master switch is off            -> [OnlineLookupStatus.disabled]
//   2. no API key configured               -> [OnlineLookupStatus.noKey]
//   3. local NFO covers the video          -> [OnlineLookupStatus.localCovered]
//   4. media_online.json has an entry      -> fromCache / notFound (no request)
//   5. only now the provider fires;        -> found / notFound / unavailable
//
// Degrade contract: no key, offline, corrupt responses, HTTP errors and
// timeouts ALL resolve to a status — nothing throws out of [lookup],
// nothing hangs (the service enforces [requestTimeout] around the provider
// whatever the injected implementation does), and the caller keeps working
// with the local data it already had.
//
// Persistence: ONE new AppData file, `media_online.json` — the same
// new-file precedent media_nfo.json (M4-T6) set (adding files ≠ modifying
// the three §7 schemas; history.json / library.json / settings.json stay
// byte-compatible, guarded by test/data_compat_spec7_test.dart). Document
// shape `{"version":1,"entries":{"<videoPath>":{"fetchedAt":…,
// "metadata":{…}|null}}}`, keyed by the video's absolute path like
// media_nfo.json. House atomic write (sibling temp file + rename); a
// missing or corrupt file degrades to an empty in-memory cache. Positive
// hits AND definitive misses (a well-formed empty result) are cached; a
// transport failure (unavailable) is NEVER cached — the next lookup may
// retry on a restored network.
class OnlineMetaService extends ChangeNotifier {
  /// |filePath| is the media_online.json location (AppData); injected so
  /// tests use a temporary directory. The gates are injected as lambdas so
  /// this service depends on neither EmoPlaySettings nor a concrete
  /// provider — MediaStores wires them to settings.onlineEnabled /
  /// settings.onlineApiKey / a TmdbProvider factory, tests wire mocks.
  OnlineMetaService(
    this.filePath, {
    required bool Function() enabled,
    required String Function() apiKey,
    NfoMetaCache? nfoMeta,
    MetadataProvider? Function()? providerFactory,
    this.requestTimeout = const Duration(seconds: 12),
  })  : _enabled = enabled,
        _apiKey = apiKey,
        _nfoMeta = nfoMeta,
        _providerFactory = providerFactory {
    _load();
  }

  /// AppData/media_online.json path this cache persists to (the
  /// application support directory needs path_provider, hence async).
  static Future<String> defaultFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/media_online.json';
  }

  final String filePath;

  final bool Function() _enabled;
  final String Function() _apiKey;
  final NfoMetaCache? _nfoMeta;
  final MetadataProvider? Function()? _providerFactory;

  /// The wall-clock bail-out around one provider call. Default 12 s; tests
  /// inject a short one to exercise the timeout degrade path quickly.
  final Duration requestTimeout;

  // Video path -> record (positive or cached negative).
  final Map<String, OnlineInfo> _entries = <String, OnlineInfo>{};
  bool _disposed = false;

  /// The cached record for |path|, if any (pure map read, no IO) — the
  /// details sheet renders it before/without a lookup.
  OnlineInfo? infoFor(String pathOrUrl) =>
      _entries[LibraryStore.toLocalPath(pathOrUrl)];

  /// Runs the gate chain and, when every gate passes, one provider search
  /// for |pathOrUrl|. |queryText| is the search text (the library entry's
  /// file-derived title); |year|/|episodeHint| narrow the search. Never
  /// throws, never hangs.
  Future<OnlineLookupResult> lookup(
    String pathOrUrl, {
    required String queryText,
    int? year,
    bool episodeHint = false,
  }) async {
    if (_disposed) {
      return const OnlineLookupResult(OnlineLookupStatus.unavailable);
    }
    final path = LibraryStore.toLocalPath(pathOrUrl);
    if (path.isEmpty) {
      return const OnlineLookupResult(OnlineLookupStatus.unavailable);
    }

    // Gate 1: master switch (default off — local-first).
    if (!_enabled()) {
      return const OnlineLookupResult(OnlineLookupStatus.disabled);
    }
    // Gate 2: API key (the user fills it in the settings center).
    if (_apiKey().trim().isEmpty) {
      return const OnlineLookupResult(OnlineLookupStatus.noKey);
    }
    // Gate 3: local NFO already covers this video (M4-T6 data) — the
    // fallback exists FOR the videos the local pass could not answer.
    if (_nfoMeta?.infoFor(path)?.hasNfo == true) {
      return const OnlineLookupResult(OnlineLookupStatus.localCovered);
    }
    // Gate 4: cache hit — positive or negative, zero requests.
    final cached = _entries[path];
    if (cached != null) {
      return cached.metadata == null
          ? const OnlineLookupResult(OnlineLookupStatus.notFound)
          : OnlineLookupResult(OnlineLookupStatus.fromCache,
              metadata: cached.metadata);
    }

    // Gate 5: the provider itself. A missing provider (factory returned
    // null — e.g. the key vanished between the gate and here) degrades
    // like any other transport problem.
    final provider = _providerFactory?.call();
    if (provider == null) {
      return const OnlineLookupResult(OnlineLookupStatus.unavailable);
    }

    final OnlineMetadata? metadata;
    try {
      metadata = await provider
          .search(MetadataQuery(
            text: queryText,
            year: year,
            episodeHint: episodeHint,
          ))
          .timeout(requestTimeout);
    } on TimeoutException {
      // Not cached: a restored network deserves a real retry.
      return const OnlineLookupResult(OnlineLookupStatus.unavailable);
    } catch (_) {
      // MetadataProviderException (offline / http error / corrupt body /
      // shape mismatch) and anything a rogue provider invents — one
      // degrade path for all of them, never a crash.
      return const OnlineLookupResult(OnlineLookupStatus.unavailable);
    }

    final record = OnlineInfo(
      fetchedAt: DateTime.now().toUtc().toIso8601String(),
      provider: metadata?.provider ?? provider.name,
      metadata: metadata,
    );
    if (!_disposed) {
      _entries[path] = record;
      _save();
      notifyListeners();
    }
    return metadata == null
        ? OnlineLookupResult(OnlineLookupStatus.notFound,
            metadata: null, cached: true)
        : OnlineLookupResult(OnlineLookupStatus.found,
            metadata: metadata, cached: true);
  }

  /// Drops one entry (a future "re-check this file" action) and persists.
  void forget(String pathOrUrl) {
    final removed = _entries.remove(LibraryStore.toLocalPath(pathOrUrl));
    if (removed != null && !_disposed) {
      _save();
      notifyListeners();
    }
  }

  /// Drops every entry and persists (a future settings-page cache-clearing
  /// tile).
  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    if (!_disposed) {
      _save();
      notifyListeners();
    }
  }

  // --------------------------------------------------------- persistence

  // QSaveFile semantics (sibling temp + rename), the HistoryStore pattern.
  void _save() {
    final file = File(filePath);
    final dir = file.parent;
    try {
      dir.createSync(recursive: true);
      final temp = File('${dir.path}/${filePath.split('/').last}.tmp');
      temp.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': <String, Object?>{
              for (final entry in _entries.entries)
                entry.key: entry.value.toJson(),
            },
          }),
          flush: true);
      temp.renameSync(filePath);
    } catch (_) {
      // Same contract as QSaveFile::commit(): silent failure, the
      // in-memory state stays authoritative.
    }
  }

  /// Flushes now (test determinism / shutdown helpers).
  void flushForTest() => _save();

  void _load() {
    _entries.clear();

    String text;
    try {
      text = File(filePath).readAsStringSync();
    } catch (_) {
      return; // no cache yet
    }
    Object? document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      return; // corrupt file: start empty, the next lookup refills it
    }
    if (document is! Map) {
      return;
    }
    final entries = document['entries'];
    if (entries is! Map) {
      return;
    }
    for (final entry in entries.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && key.isNotEmpty && value is Map) {
        _entries[key] = OnlineInfo.fromJson(value);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Why a lookup answered without/with what it did — the UI maps every
/// status to one graceful message; nothing here is an error state.
enum OnlineLookupStatus {
  /// Master switch off (the default) — nothing was sent.
  disabled,

  /// No API key configured — nothing was sent.
  noKey,

  /// Local NFO covers the video (M4-T6) — nothing was sent, local-first.
  localCovered,

  /// Answered from media_online.json, zero requests.
  fromCache,

  /// The provider returned a usable hit (fresh, now also cached).
  found,

  /// A definitive miss (well-formed empty result); cached as a negative.
  notFound,

  /// Transport failure (offline / http error / corrupt body / timeout /
  /// no provider). NOT cached — the next lookup retries.
  unavailable,
}

/// The outcome of one [OnlineMetaService.lookup].
class OnlineLookupResult {
  const OnlineLookupResult(
    this.status, {
    this.metadata,
    this.cached = false,
  });

  final OnlineLookupStatus status;

  /// The hit (found / fromCache); null for every other status.
  final OnlineMetadata? metadata;

  /// True when this lookup's answer was just persisted (found / notFound
  /// with a provider answer); false for pure cache reads.
  final bool cached;
}

/// One video's online-metadata record (media_online.json entry).
@immutable
class OnlineInfo {
  const OnlineInfo({
    this.fetchedAt = '',
    this.provider = '',
    this.metadata,
  });

  /// ISO-8601 UTC timestamp of the provider round-trip that produced this
  /// record ('' never meaningful — the loader tolerates its absence).
  final String fetchedAt;

  /// The provider that answered ('tmdb'); kept for cached negatives too.
  final String provider;

  /// The hit; null for a cached definitive miss.
  final OnlineMetadata? metadata;

  factory OnlineInfo.fromJson(Map<Object?, Object?> json) {
    final metadataJson = json['metadata'];
    return OnlineInfo(
      fetchedAt:
          json['fetchedAt'] is String ? json['fetchedAt'] as String : '',
      provider: json['provider'] is String ? json['provider'] as String : '',
      metadata: metadataJson is Map
          ? OnlineMetadata.fromJson(metadataJson as Map<Object?, Object?>)
          : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'fetchedAt': fetchedAt,
        'provider': provider,
        'metadata': metadata?.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is OnlineInfo &&
      other.fetchedAt == fetchedAt &&
      other.provider == provider &&
      other.metadata == metadata;

  @override
  int get hashCode => Object.hash(fetchedAt, provider, metadata);

  @override
  String toString() => 'OnlineInfo($provider, ${metadata?.title})';
}

/// Derives the search text for a library video path the same way the
/// library model names it (the file's completeBaseName), stripping the
/// episode marker when one parses so TMDB hears the show title. Kept next
/// to the service so the sheet and any future caller share one convention.
String onlineQueryTextFor(String videoPath) {
  final name = p.basenameWithoutExtension(videoPath);
  return name;
}
