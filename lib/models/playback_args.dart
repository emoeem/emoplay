/// Route arguments for playback entry points.
///
/// Kazumi handed bangumi episodes to `/video/` through sealed playback args
/// (docs/STRIP-LIST.md §3); EmoPlay keeps the sealed-args mechanism but the
/// only concrete kind is a local media file. [startAt] is a resume position
/// in seconds; wiring it into the player's pending-seek semantics is part of
/// the PlaybackController port (docs/PORT-MAP.md §2).
sealed class PlaybackArgs {
  const PlaybackArgs();
}

class LocalFilePlaybackArgs extends PlaybackArgs {
  const LocalFilePlaybackArgs({
    required this.path,
    required this.title,
    this.startAt = 0.0,
  });

  /// Absolute path of the media file.
  final String path;

  /// Display title (file name unless a library entry provides one).
  final String title;

  /// Resume position in seconds.
  final double startAt;
}
