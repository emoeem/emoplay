import 'package:emoplay/models/media_item_mappers.dart';
import 'package:emoplay/models/playback_session.dart';
import 'package:emoplay/pages/player/controller/player_playlist_item.dart';
import 'package:emoplay/services/platform/display_mode_service.dart';
import 'package:emoplay/utils/device.dart';
import 'package:mobx/mobx.dart';
import 'package:window_manager/window_manager.dart';

// The row type stays importable from here (every pre-M4 caller imports this
// file): the class itself moved to player_playlist_item.dart in M4-T0b so
// the unified-model mappers can name it without an import cycle.
export 'package:emoplay/pages/player/controller/player_playlist_item.dart'
    show PlayerPlaylistItem;

part 'player_page_controller.g.dart';

/// Page-scope state for the player page.
///
/// M1 replacement for the stripped Kazumi [VideoPageController]: it owns the
/// local playlist, the current selection and window fullscreen/PIP flags.
/// Playback itself lives in [PlayerController].
///
/// M4-T0b (roadmap §四 step 2, "播放队列收编"): the playlist is no longer
/// the source of truth. [session] — the unified [PlaybackSession] — is, and
/// [playlist] / [currentItem] are derived views of it. The external
/// interface is unchanged: [setPlaylist] keeps its exact signature (plus an
/// additive optional [setPlaylist.origin] the roadmap's session origin
/// field needs), and the resume path is untouched — `openAt(path, seconds)`
/// semantics still flow `startAt` → PlaybackInitParams →
/// PendingResumeSeek (SPEC §4.4 invariant 4; this controller never arms or
/// consumes a resume seek, and [PlaybackSession.startPosition] is data
/// only).
class PlayerPageController = _PlayerPageController
    with _$PlayerPageController;

abstract class _PlayerPageController with Store {
  /// The playback queue in the unified model. Replaced wholesale by
  /// [setPlaylist] / [setSession]; [playlist] is derived from it.
  @observable
  PlaybackSession session = PlaybackSession.empty;

  /// Index of the entry passed to the player, -1 while nothing is loaded.
  ///
  /// Deliberately separate from [PlaybackSession.startIndex]: the session
  /// records where playback started, this field tracks where it is now
  /// (item advance, back-out to idle).
  @observable
  int currentIndex = -1;

  /// Playlist shown in the player page side panel — a derived view of
  /// [session] (roadmap §四 step 2). Recomputed only when the session
  /// changes; consumers read it like the ObservableList it replaced.
  @computed
  List<PlayerPlaylistItem> get playlist =>
      [for (final item in session.items) item.toPlaylistItem()];

  /// True while the route is still resolving the media for playback.
  @observable
  bool loading = false;

  /// Android picture-in-picture flag (mirrored from the native PiP handler).
  @observable
  bool isPip = false;

  /// Window fullscreen state.
  @observable
  bool isFullscreen = false;

  @computed
  PlayerPlaylistItem? get currentItem =>
      (currentIndex >= 0 && currentIndex < playlist.length)
          ? playlist[currentIndex]
          : null;

  /// Title of the media currently being played.
  @computed
  String get title => currentItem?.title ?? '';

  /// Path of the media currently being played.
  @computed
  String get src => currentItem?.path ?? '';

  PlayerPlaylistItem? itemAt(int index) {
    if (index < 0 || index >= playlist.length) {
      return null;
    }
    return playlist[index];
  }

  /// Replaces the queue (rows keep the pre-M4 constructor), keeping the
  /// external contract bit-for-bit: [initialIndex] lands in
  /// [currentIndex] verbatim (no clamping — the -1 idle sentinel and the
  /// caller-supplied start index both pass through), exactly as the
  /// ObservableList version did.
  ///
  /// The rows are lifted into [session] via the M4-T0b mapper
  /// ([PlayerPlaylistItemMediaMapper.toMediaItem]), so the queue the
  /// playlist panel, the progress pipeline and the audio binding see is
  /// the same list either way (path/title round-trip losslessly).
  ///
  /// [origin] is the additive seam for the roadmap's session origin
  /// ("library" | "history" | "picker" | "external"); existing callers
  /// omit it and get null, as before.
  @action
  void setPlaylist(List<PlayerPlaylistItem> items,
      {int initialIndex = -1, String? origin}) {
    session = PlaybackSession(
      items: [for (final item in items) item.toMediaItem()],
      startIndex: initialIndex,
      origin: origin,
    );
    currentIndex = initialIndex;
  }

  /// Installs a whole [PlaybackSession] (M4-T0 seam for the callers that
  /// build a session from library/history items and jump straight into
  /// playback). [currentIndex] seeds from the session's [startIndex] like
  /// [setPlaylist] does. Does not touch the resume machinery: a
  /// session-[PlaybackSession.startPosition] is consumed by whoever opens
  /// the player, through the unchanged openAt path.
  @action
  void setSession(PlaybackSession value) {
    session = value;
    currentIndex = value.startIndex;
  }

  @action
  void setCurrentIndex(int index) {
    if (index >= -1 && index < playlist.length) {
      currentIndex = index;
    }
  }

  @action
  void setLoading(bool value) {
    loading = value;
  }

  @action
  void setPip(bool value) {
    isPip = value;
  }

  /// Whether the player route is the outlet's current route. Driven by
  /// PlayerPage's ModalRoute.isCurrent; the shell keys chrome visibility and
  /// the tab highlight off this instead of the stale IndexPage tab index
  /// (programmatic jumps like home-card resume never touch that index).
  @observable
  bool pageCurrent = false;

  @action
  void setPageCurrent(bool value) {
    if (pageCurrent == value) {
      return;
    }
    pageCurrent = value;
  }

  /// Toggles fullscreen, per platform (PiliPlus triggerFullScreen split):
  ///
  /// - desktop: window fullscreen via window_manager;
  /// - mobile: landscape orientation lock + immersive system bars, through
  ///   [DisplayModeService] (its native `setSystemBarsHidden` channel and the
  ///   orientation apply were previously wired but never called).
  ///
  /// The fullscreen flag is owned here (not by the player surface) so that the
  /// route shell can react to it, mirroring the Kazumi fullscreen controller.
  @action
  Future<void> toggleFullscreen() async {
    await setFullscreen(!isFullscreen);
  }

  @action
  Future<void> setFullscreen(bool value) async {
    if (value == isFullscreen) {
      return;
    }
    if (isDesktop()) {
      await WindowManager.instance.setFullScreen(value);
      isFullscreen = value;
      return;
    }
    // PiliPlus enter/exit order: bars first, then the orientation lock; the
    // exit restores rotation before the bars so the layout lands with the
    // insets it lays out for.
    await DisplayModeService.applyVideoFullscreen(value);
    if (value) {
      await DisplayModeService.setSystemBarsHidden(owner: this, hidden: true);
    } else {
      DisplayModeService.releaseSystemBars(this);
    }
    isFullscreen = value;
  }
}
