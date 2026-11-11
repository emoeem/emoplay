import 'package:flutter/foundation.dart';

/// The unified in-memory media model (EmoPlay 3.0 roadmap docs/
/// EMOPLAY-3.0-ROADMAP.md §四, task M4-T0).
///
/// One immutable fact set about a playable media file, assembled from what
/// the 1.x-shaped stores already know plus the 3.0 metadata extensions:
///
///  - [path] is the unique key, with the 1.x semantics (an absolute local
///    path; a remote URL degrades to an empty-type item — see
///    media_item_mappers.dart).
///  - The base fields ([title], [type], [size], [duration], [lastPlayed])
///    carry exactly what the SPEC §7 stores hold: `type` uses the
///    classifier vocabulary ("video" | "audio", never extended),
///    [duration] is seconds with 0.0 meaning "unknown" (the same sentinel
///    history.json writes), [lastPlayed] is the parsed ISO 8601 instant or
///    null when the store wrote "" / null.
///  - The trailing fields are the 3.0 extension slots (roadmap §四: "全部
///    可空、不落三份 JSON"). They are filled from the metadata cache
///    (lib/media/media_meta_cache.dart, M4-T4) and are NEVER written into
///    history.json / library.json / settings.json — the §7 schemas are the
///    1.x release promise and stay byte-compatible
///    (test/data_compat_spec7_test.dart guards that).
///
/// This class is a read-only view: it owns no persistence. Mappers live in
/// media_item_mappers.dart; nothing in this file imports the stores.
@immutable
class MediaItem {
  const MediaItem({
    required this.path,
    this.title = '',
    this.type = '',
    this.size = 0,
    this.duration = 0.0,
    this.lastPlayed,
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
  });

  /// Absolute local path (1.x unique-key semantics).
  final String path;

  /// Display name (file name without extensions).
  final String title;

  /// "video" | "audio" (classifier vocabulary, not extended; "" when the
  /// source record did not know).
  final String type;

  /// File size in bytes; 0 when the source record did not know.
  final int size;

  /// Duration in seconds; 0.0 = unknown (history.json's own sentinel).
  final double duration;

  /// Last-played instant, or null when never played / unparseable. The
  /// ISO 8601 string inside the §7 files stays authoritative; this is the
  /// parsed view of it.
  final DateTime? lastPlayed;

  // ---- 3.0 extension slots (nullable, metadata-cache fed, never §7). ----

  /// Container format (ffprobe format_name, e.g. "matroska,webm").
  final String? container;

  /// Primary video stream codec (ffprobe codec_name, e.g. "h264").
  final String? videoCodec;

  /// Primary audio stream codec (ffprobe codec_name, e.g. "aac").
  final String? audioCodec;

  /// Video dimensions in pixels (cover-art streams are not reported).
  final int? width;
  final int? height;

  /// True when a positive duration is known (0.0/NaN are "unknown").
  bool get hasDuration => duration > 0.0;

  /// Field-wise copy; the metadata-cache merge path (M4-T4) uses this to
  /// fill the extension slots of a store-derived item. Null arguments keep
  /// the current value (setting a slot back to null is not needed by any
  /// caller — an edited file changes its cache key instead).
  MediaItem copyWith({
    String? path,
    String? title,
    String? type,
    int? size,
    double? duration,
    DateTime? lastPlayed,
    String? container,
    String? videoCodec,
    String? audioCodec,
    int? width,
    int? height,
  }) =>
      MediaItem(
        path: path ?? this.path,
        title: title ?? this.title,
        type: type ?? this.type,
        size: size ?? this.size,
        duration: duration ?? this.duration,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        container: container ?? this.container,
        videoCodec: videoCodec ?? this.videoCodec,
        audioCodec: audioCodec ?? this.audioCodec,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.path == path &&
      other.title == title &&
      other.type == type &&
      other.size == size &&
      other.duration == duration &&
      other.lastPlayed == lastPlayed &&
      other.container == container &&
      other.videoCodec == videoCodec &&
      other.audioCodec == audioCodec &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(path, title, type, size, duration, lastPlayed,
      container, videoCodec, audioCodec, width, height);

  @override
  String toString() => 'MediaItem($path, $title, $type, $size, $duration, '
      '$lastPlayed, $container, $videoCodec/$audioCodec, ${width}x$height)';
}
