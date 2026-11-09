/// One-shot resume position carried into a playback session.
///
/// Port of mpv-emo `PlaybackController.m_pendingSeek`
/// (src/mpv/PlaybackController.h L134, consumed in
/// src/mpv/PlaybackController.cpp L264-268; docs/PORT-MAP.md §2, SPEC §4.4):
/// `openAt(path, startAt)` arms the position here and the first file-loaded
/// event consumes it exactly once. Two reasons, both from the 1.x source:
/// seeking before file-loaded is dropped by mpv, which is why the seek is
/// deferred instead of issued with the load command; and a later file in the
/// playlist must start from the beginning, which is why the value is one-shot.
class PendingResumeSeek {
  /// Armed resume position in seconds, or -1 while nothing is pending
  /// (the sentinel the 1.x controller used).
  double _pending = -1;

  bool get hasPending => _pending >= 0;

  /// Arms (or disarms, for [startAt] <= 0) the deferred seek for the next
  /// file-loaded event. A later call replaces the previous value, mirroring
  /// 1.x `openAt` being called again before the file loaded.
  void arm(double startAt) {
    _pending = startAt > 0 ? startAt : -1;
  }

  /// Returns the armed position exactly once, then stays disarmed.
  double? consume() {
    if (_pending < 0) {
      return null;
    }
    final target = _pending;
    _pending = -1;
    return target;
  }

  void clear() {
    _pending = -1;
  }
}
