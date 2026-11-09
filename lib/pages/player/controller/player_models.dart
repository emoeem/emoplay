/// Parameters for initializing a playback session.
///
/// EmoPlay 2.0 plays local media files; the Kazumi bangumi/episode identity
/// fields were removed with the bangumi business layer (docs/STRIP-LIST.md §2).
class PlaybackInitParams {
  final String videoUrl;
  final bool isLocalPlayback;
  final Map<String, String> httpHeaders;
  final String episodeTitle;
  final String? coverUrl;

  /// Resume position in seconds, the `startAt` of the sealed
  /// [LocalFilePlaybackArgs]. Ported from mpv-emo `openAt(path, seconds)`
  /// (docs/PORT-MAP.md §2): the seek is suspended until the file is loaded
  /// and consumed exactly once, so it must not be passed to the load command.
  final double startAt;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.isLocalPlayback,
    required this.httpHeaders,
    required this.episodeTitle,
    this.startAt = 0.0,
    this.coverUrl,
  });
}
