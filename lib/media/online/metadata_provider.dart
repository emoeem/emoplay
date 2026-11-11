// The online-metadata provider seam (roadmap M4-T7, user redirection
// 2026-11-12: 在线元数据联网源由「明确不做」改方向纳入，作为本地 NFO/海报
// （M4-T6）之后的联网兜底).
//
// One tiny interface plus one result record. Everything network-shaped
// lives behind [MetadataProvider]; the cache service
// (online_meta_service.dart) only ever sees results and a typed exception,
// which is what makes the whole degrade-path contract (no key / offline /
// corrupt response / timeout -> status, never a crash) testable with a mock
// and, per the local-first discipline, keeps every OTHER file in lib/media
// free of network calls.
//
// The framework round (this one) ships the interface + the TMDB adapter
// skeleton; the real data flow needs a user-supplied TMDB API key (settings
// → 在线元数据), so everything behind the seam is verified against a mock
// client in test/ and the live path is recorded as pending manual
// verification.
import 'package:flutter/foundation.dart';

/// One online metadata hit, already normalized to the facts the NFO layer
/// speaks (the same vocabulary as [NfoDocument]: title/plot/year/rating/
/// genres + a poster URL). All fields are best-effort: a provider that does
/// not know a fact leaves it null/empty — the UI degrades field by field.
@immutable
class OnlineMetadata {
  const OnlineMetadata({
    this.provider = '',
    this.providerId = 0,
    this.mediaType = '',
    this.title = '',
    this.originalTitle = '',
    this.year,
    this.rating,
    this.plot = '',
    this.genres = const <String>[],
    this.posterUrl = '',
    this.query = '',
  });

  /// Provider that produced this record ('tmdb' for the TMDB adapter).
  final String provider;

  /// The provider's own numeric id (TMDB id), 0 when unknown.
  final int providerId;

  /// 'movie' | 'tv' | '' — the search hit's media type.
  final String mediaType;

  /// Localized display title.
  final String title;

  /// Original-language title, when the provider offers one.
  final String originalTitle;

  /// Release year (parsed from the provider's date string), null unknown.
  final int? year;

  /// Provider rating (TMDB vote_average 0..10), null unknown.
  final double? rating;

  /// Overview / plot text.
  final String plot;

  /// Genre names. The search endpoint only carries numeric genre ids — the
  /// adapter leaves this empty until the name mapping lands with the real
  /// key (recorded pending; the field is wired so nothing else changes).
  final List<String> genres;

  /// Absolute poster image URL, '' when the hit has no artwork. DISPLAYED
  /// AS TEXT ONLY for now (local-first discipline: no UI-side fetches in
  /// this framework round; downloading poster art is the pending step).
  final String posterUrl;

  /// The query string this record answers (stored alongside the cache
  /// entry so the user can see what was searched).
  final String query;

  factory OnlineMetadata.fromJson(Map<Object?, Object?> json) {
    List<String> readList(Object? field) {
      if (field is! List) {
        return const <String>[];
      }
      return <String>[
        for (final value in field)
          if (value is String && value.isNotEmpty) value,
      ];
    }

    return OnlineMetadata(
      provider: json['provider'] is String ? json['provider'] as String : '',
      providerId: json['providerId'] is int
          ? json['providerId'] as int
          : (json['providerId'] is num
              ? (json['providerId'] as num).toInt()
              : 0),
      mediaType: json['mediaType'] is String ? json['mediaType'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      originalTitle:
          json['originalTitle'] is String ? json['originalTitle'] as String : '',
      year: json['year'] is int ? json['year'] as int : null,
      rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
      plot: json['plot'] is String ? json['plot'] as String : '',
      genres: readList(json['genres']),
      posterUrl: json['posterUrl'] is String ? json['posterUrl'] as String : '',
      query: json['query'] is String ? json['query'] as String : '',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': provider,
        'providerId': providerId,
        'mediaType': mediaType,
        'title': title,
        'originalTitle': originalTitle,
        if (year != null) 'year': year,
        if (rating != null) 'rating': rating,
        'plot': plot,
        'genres': List<String>.of(genres),
        'posterUrl': posterUrl,
        'query': query,
      };

  @override
  bool operator ==(Object other) =>
      other is OnlineMetadata &&
      other.provider == provider &&
      other.providerId == providerId &&
      other.mediaType == mediaType &&
      other.title == title &&
      other.originalTitle == originalTitle &&
      other.year == year &&
      other.rating == rating &&
      other.plot == plot &&
      other.posterUrl == posterUrl &&
      other.query == query;

  @override
  int get hashCode => Object.hash(
      provider, providerId, mediaType, title, originalTitle, year, rating);

  @override
  String toString() =>
      'OnlineMetadata($provider#$providerId, $mediaType, title=$title)';
}

/// One search request against a provider.
class MetadataQuery {
  const MetadataQuery({
    required this.text,
    this.year,
    this.episodeHint = false,
  });

  /// The search text (the video's file-derived title, i.e. what the user
  /// would type into the provider's web search).
  final String text;

  /// A year parsed from the file name, when one exists (narrows the search).
  final int? year;

  /// True when the file name looked like a TV episode (SxxEyy) — providers
  /// may prefer the TV search domain.
  final bool episodeHint;
}

/// The provider seam: ONE method. Throw [MetadataProviderException] for
/// transport/protocol failures (offline, HTTP error, non-JSON body, shape
/// mismatch) — the cache service maps a throw to its `unavailable` degrade
/// status. Return null for a DEFINITIVE "no such title" (a well-formed
/// empty result set) — the service caches that as a negative so the same
/// file does not hammer the API again. Never return a half-parsed record.
abstract class MetadataProvider {
  /// Human-facing provider id stored with every cache entry ('tmdb').
  String get name;

  /// Runs one search. Implementations must be total: any failure is either
  /// a thrown [MetadataProviderException] or a null — never a hang (bail
  /// out via the injected request timeout) and never a crash.
  Future<OnlineMetadata?> search(MetadataQuery query);
}

/// Typed transport/protocol failure. The message is for the log/toast only.
class MetadataProviderException implements Exception {
  const MetadataProviderException(this.message);

  final String message;

  @override
  String toString() => 'MetadataProviderException: $message';
}
