import 'package:flutter/foundation.dart';

import 'package:emoplay/models/media_item.dart';

/// One playback session: the queue the player page works from, expressed in
/// the unified model (EmoPlay 3.0 roadmap docs/EMOPLAY-3.0-ROADMAP.md §四,
/// task M4-T0 — structure copied from the roadmap's own sketch).
///
/// The player page (lib/pages/player/controller/player_page_controller.dart)
/// keeps a [PlaybackSession] as the source of truth and derives its
/// observable `PlayerPlaylistItem` list from [items], so the page's external
/// interface (playlist / currentIndex / setPlaylist) stays exactly as the
/// M1-M3 callers know it.
///
/// [startPosition] is data only: the resume *semantics* stay owned by
/// PendingResumeSeek (lib/pages/player/controller/pending_resume_seek.dart,
/// SPEC §4.4 invariant 4 — armed on the openAt-equivalent path, consumed
/// once at file-loaded). Nothing in this class arms, consumes or clears a
/// pending seek.
@immutable
class PlaybackSession {
  const PlaybackSession({
    this.items = const <MediaItem>[],
    this.startIndex = -1,
    this.startPosition,
    this.isMusic = false,
    this.origin,
  });

  /// The "nothing loaded" session (player page idle state).
  static const PlaybackSession empty = PlaybackSession();

  /// The playing queue, head first. Identity-free: entries are equal by
  /// value ([MediaItem.==]), and the same path may legitimately appear
  /// twice in a hand-built queue.
  final List<MediaItem> items;

  /// Index into [items] the session starts at; -1 while nothing is loaded
  /// (the player page's own currentIndex sentinel).
  final int startIndex;

  /// Resume position in seconds for [startIndex], or null when starting
  /// from the beginning. Carried for the callers that open playback from a
  /// resume point; the deferred one-shot seek itself remains
  /// PendingResumeSeek's job (invariant 4).
  final double? startPosition;

  /// Music-form vs video-form driver (roadmap §四). False for the video
  /// page the M1-M3 players render; M5 flips it for the music queue.
  final bool isMusic;

  /// Where the session came from: "library" | "history" | "picker" |
  /// "external" (roadmap §四 vocabulary). Null = not declared yet (the
  /// current setPlaylist callers do not say).
  final String? origin;

  /// The origin strings the roadmap names. Documentation constant — the
  /// field itself stays a plain String? so foreign callers can extend.
  static const List<String> knownOrigins = <String>[
    'library',
    'history',
    'picker',
    'external',
  ];

  bool get isEmpty => items.isEmpty;

  /// The item playback starts from, or null when [startIndex] is out of
  /// range (including the -1 idle sentinel).
  MediaItem? get startItem =>
      (startIndex >= 0 && startIndex < items.length) ? items[startIndex] : null;

  @override
  bool operator ==(Object other) =>
      other is PlaybackSession &&
      other.startIndex == startIndex &&
      other.startPosition == startPosition &&
      other.isMusic == isMusic &&
      other.origin == origin &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(
      Object.hashAll(items), startIndex, startPosition, isMusic, origin);

  @override
  String toString() => 'PlaybackSession(${items.length} items, start $startIndex,'
      ' position $startPosition, music $isMusic, origin $origin)';
}
