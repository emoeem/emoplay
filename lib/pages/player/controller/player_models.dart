/// Parameters for initializing a playback session.
///
/// EmoPlay 2.0 plays local media files; the Kazumi bangumi/episode identity
/// fields were removed with the bangumi business layer (docs/STRIP-LIST.md §2).
class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final Map<String, String> httpHeaders;
  final String episodeTitle;
  final String? coverUrl;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.httpHeaders,
    required this.episodeTitle,
    this.coverUrl,
  });
}
